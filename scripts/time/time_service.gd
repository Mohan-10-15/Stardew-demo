class_name TimeService
extends Node
## Drives the game clock in real time and publishes transitions on [EventBus].
##
## Deliberately thin. Every rule about *what* the time is lives in [Clock] as
## pure functions; this node only converts elapsed seconds into ticks and
## announces the results. That split is why the calendar can be tested without a
## scene tree and why a bot simulation can advance 112 days in microseconds.
##
## Nothing else in the game reads this directly — lighting, schedules, shops and
## crop growth all subscribe to the `EventBus` signals, so the clock can be
## swapped, fast-forwarded or stubbed without touching any of them.

## Real seconds for one in-game day. A 10-minute day matches the session shape
## in the GDD: a day is ~10 real minutes, a year is 112 in-game days.
@export var seconds_per_day: float = 600.0
## Ticks per [member seconds_per_day]. Lowering this speeds the whole game up
## without touching any system's logic.
@export var ticks_per_day: int = Clock.ticks_per_day()
## When false the clock does not advance, but the current time is still
## readable. Pausing the game does not go through here.
@export var running: bool = true
## Multiplies tick rate without changing the tick size, so event granularity
## stays the same while the day gets shorter. Used by the dev console only.
@export var time_scale: float = 1.0

## The current world time. Public for the HUD and for saves; treat as
## read-only outside this class.
var time: WorldTime = WorldTime.new()

var _elapsed := 0.0
var _seconds_per_tick := 10.0


func _ready() -> void:
	_recalculate_tick_length()
	WeatherCalendar.apply(time)
	Log.info("Time", "Clock ready (%s, %d ticks/day)" % [time.describe_date(), ticks_per_day])
	# Publish the starting state so anything subscribing late still converges.
	_publish_clock()
	_publish_weather(false)
	EventBus.day_started.emit(time.day_of_month)


func _process(delta: float) -> void:
	if not running or time_scale <= 0.0:
		return
	_elapsed += delta * time_scale
	# A long frame or a backgrounded window can deliver a huge delta; consume it
	# in whole ticks so the day does not silently lose time.
	var guard := 0
	while _elapsed >= _seconds_per_tick and guard < Clock.ticks_per_day() * 4:
		_elapsed -= _seconds_per_tick
		advance_tick()
		guard += 1


## Advances the clock by exactly one tick and publishes whatever changed.
##
## Public and synchronous so tests and the bot simulation can step time without
## waiting on real seconds.
##
## A tick after the collapse point is a no-op. The clock is frozen from 2:00 AM
## until the player sleeps, because otherwise the calendar would spin through
## empty days while the game waits for the "you passed out" prompt to be
## answered. The end of the day is [method sleep_until_morning], not another
## tick.
func advance_tick() -> Dictionary:
	if time.passed_out:
		return {
			"time": time,
			"day_rolled": false,
			"season_rolled": false,
			"year_rolled": false,
			"passed_out": true,
			"minutes_advanced": 0,
		}

	var before_hour := time.hour
	var before_day := time.day_of_month

	var transition := Clock.advance(time, Clock.TICK_MINUTES)
	time = transition["time"]

	if bool(transition["day_rolled"]):
		# day_ended carries the day that just finished, which is not the new one.
		EventBus.day_ended.emit(before_day)
		EventBus.day_started.emit(time.day_of_month)
		# The sky belongs to the day, so it is recomputed here rather than left to roll.
		# Announced after day_started so a listener reading the date off the signal gets
		# the new day and the weather that goes with it, in that order.
		_publish_weather(true)
		if bool(transition["season_rolled"]):
			EventBus.season_changed.emit(time.season)
		if bool(transition["year_rolled"]):
			EventBus.year_changed.emit(time.year)

	if time.hour != before_hour:
		EventBus.time_hour_changed.emit(time.hour)
	EventBus.time_minute_changed.emit(time.hour * Clock.MINUTES_PER_HOUR + time.minute)
	return transition


## True while the player is unconscious or asleep. The clock is frozen and the
## only legal transitions out are [method wake_after_collapse] and
## [method sleep_until_morning].
func is_asleep() -> bool:
	return time.passed_out


## Goes to bed and ends the day. Both `day_ended` (carrying the day that just
## finished) and `day_started` fire, and the calendar advances.
func sleep_until_morning() -> WorldTime:
	var finished_day := time.day_of_month
	time = Clock.next_day_morning(time)
	EventBus.day_ended.emit(finished_day)
	EventBus.day_started.emit(time.day_of_month)
	_publish_weather(true)
	_publish_clock()
	return time


## Clears the collapse and resumes the morning. No day boundary fires, because
## the collapse already rolled the calendar — see [method Clock.wake_after_collapse].
func wake_after_collapse() -> WorldTime:
	time = Clock.wake_after_collapse(time)
	_publish_clock()
	return time


func _publish_clock() -> void:
	EventBus.time_hour_changed.emit(time.hour)
	EventBus.time_minute_changed.emit(time.hour * Clock.MINUTES_PER_HOUR + time.minute)


## Jumps to a specific date and time. Dev console and save loading only.
##
## Publishes a day boundary only when the date actually changed, so loading a save
## taken mid-morning does not announce a day that never ended.
func set_time(new_time: WorldTime) -> void:
	var previous_day := time.day_of_month
	var previous_season := time.season
	var previous_year := time.year
	time = new_time.copy()
	# Weather is derived from the date, so a save's stored weather is a cache and not
	# an input. This is what makes an old save — written back when every day was Sunny
	# because nothing had rolled it yet — come back with a real sky.
	_publish_weather(true)
	_publish_clock()
	if time.day_of_month != previous_day:
		EventBus.day_started.emit(time.day_of_month)
	if time.season != previous_season:
		EventBus.season_changed.emit(time.season)
	if time.year != previous_year:
		EventBus.year_changed.emit(time.year)


## Recomputes today's weather and tomorrow's forecast, publishing whichever moved.
##
## [param announce] false means "the day did not change", which is only true at boot —
## where the value is published without a signal, because a listener that has not
## subscribed yet cannot be told about a change that happened before it existed. Every
## real day boundary announces.
func _publish_weather(announce: bool) -> void:
	var changed := WeatherCalendar.apply(time)
	if not announce:
		return
	if bool(changed.get("weather", false)):
		EventBus.weather_changed.emit(time.weather)


## Today's [WorldTime.Weather] value. Weather selection itself is M9; this
## exists so callers do not need to reach into `time` for a read-only value.
##
## The *selection* is no longer M9's alone — [WeatherCalendar] landed with the schedule
## group so a rain override could mean something. Everything a player sees about weather
## (sky colour, rain, wind, thunder, what fishing does) is still M9.
func get_weather() -> int:
	return time.weather


## Tomorrow's weather, for the forecast shown at the end of the day.
func get_forecast() -> int:
	return time.forecast


## Convenience for the HUD: "Year 1 Spring 4, 6:30 AM".
func get_display_text() -> String:
	return "%s, %s" % [time.describe_date(), time.describe_time()]


func to_dict() -> Dictionary:
	return time.to_dict()


func from_dict(data: Dictionary) -> void:
	set_time(WorldTime.from_dict(data))


func _recalculate_tick_length() -> void:
	var ticks := maxi(ticks_per_day, 1)
	_seconds_per_tick = maxf(seconds_per_day / float(ticks), 0.001)
