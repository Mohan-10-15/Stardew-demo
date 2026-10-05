class_name NpcScheduleEntry
extends Resource
## One block of a villager's day: a time window, a place, and the conditions under
## which it applies.
##
## ## The time window
##
## Authored in [method Clock.to_game_minutes], which is HHMM where 6:00 AM is `600`,
## midnight is `2400` and 2:00 AM is `2600`. Not real minutes from midnight: the unit
## exists so a window that spans midnight stays **monotonic**. "The tavern is busy from
## 22:00" reads as 2200, and "until 02:00" reads as 2600, so one window can cross
## midnight without wrapping to zero and splitting into two.
##
## [member from_minute] is inclusive and [member to_minute] is exclusive, so a window
## ending at 1200 and the next starting at 1200 leave no gap and no overlap. At the top
## of the day the window is open-ended: an entry whose [member to_minute] is
## [constant OPEN_END] runs to 2:00 AM, which is when the day ends whether the player
## went to bed or collapsed.
##
## ## Conditions
##
## [member seasons] and [member weathers] are empty-means-always. An empty filter is not
## the same as a filter containing every value: a block that says "rain or storm" is a
## different block from one that says nothing, and collapsing the two would make a
## rain-only routine unreachable.

## Sentinel for [member to_minute] meaning "until the end of the day".
const OPEN_END := 9999

## Start of the window, inclusive, in [method Clock.to_game_minutes] units.
@export var from_minute: int = Clock.DAY_START_HOUR * 100

## End of the window, exclusive, or [constant OPEN_END].
@export var to_minute: int = OPEN_END

## Id of a [LocationData] this block sends the villager to.
@export var location: StringName = &""

## Seasons this block applies to, as [constant WorldTime.Season] values. Empty is any.
@export var seasons: Array[int] = []

## Weathers this block applies to, as [constant WorldTime.Weather] values. Empty is any.
@export var weathers: Array[int] = []

## What the villager is doing here, for logs and later dialogue. Free-form.
@export var activity: StringName = &""


## Whether [param time] falls in this block's window, on the monotonic day scale.
##
## A window whose end is below its start is treated as wrapping through the small hours
## rather than as invalid, because "11pm until 2am" is a thing a person means and an
## author should be able to write it the way they say it.
func covers(time: WorldTime) -> bool:
	return covers_minute(minute_of(time))


func covers_minute(minute: int) -> bool:
	if to_minute >= OPEN_END:
		return minute >= from_minute
	if to_minute >= from_minute:
		return minute >= from_minute and minute < to_minute
	# Wrapped: starts late, ends in the small hours.
	return minute >= from_minute or minute < to_minute


## Whether this block applies on [param time] at all, ignoring the clock.
##
## The time window is [method covers]; this is only the date and sky. Kept separate
## because the two get confused when reading a schedule, and because a content test
## wants to ask "is this block ever reachable on a summer day" without also caring what
## time it is.
func applies_on(time: WorldTime) -> bool:
	if not seasons.is_empty() and not seasons.has(time.season):
		return false
	if not weathers.is_empty() and not weathers.has(time.weather):
		return false
	return true


## The window this block covers, as a readable range for logs and tests.
func describe_window() -> String:
	if to_minute >= OPEN_END:
		return "%s-end" % _hhmm(from_minute)
	return "%s-%s" % [_hhmm(from_minute), _hhmm(to_minute)]


func is_valid() -> bool:
	if location.is_empty():
		return false
	if from_minute < 0 or to_minute > OPEN_END:
		return false
	if to_minute != OPEN_END and to_minute <= from_minute and to_minute < Clock.DAY_START_HOUR * 100:
		# Only a wrapped window may have an end below its start, and the end has to be in
		# the small hours for that to be what the author meant.
		return false
	for season: int in seasons:
		if season < 0 or season >= Clock.SEASONS_PER_YEAR:
			return false
	for weather: int in weathers:
		if weather < 0 or weather >= WorldTime.WEATHER_NAMES.size():
			return false
	return true


## The current time on the monotonic day scale.
static func minute_of(time: WorldTime) -> int:
	return Clock.to_game_minutes(time.hour, time.minute)


static func _hhmm(value: int) -> String:
	return "%02d:%02d" % [value / 100, value % 100]