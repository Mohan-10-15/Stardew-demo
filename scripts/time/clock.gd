class_name Clock
extends RefCounted
## Pure calendar and clock arithmetic. No scene, no signals, no side effects.
##
## Everything here is a static function over [WorldTime]. That is what makes the
## whole system testable in milliseconds and lets a bot simulation run 112
## game-days cheaply, which is the reason the simulation lane is kept free of
## scene dependencies in the first place.
##
## ## The model
##
## The clock runs from 6:00 AM to 2:00 AM. Internally time is measured in
## **absolute minutes from the 6:00 AM day start**:
##
## | Moment | Absolute minute |
## |---|---|
## | 6:00 AM (day start) | `0` |
## | midnight | `1080` (`18 * 60`) |
## | 2:00 AM (collapse) | `1200` (`(18 + PASS_OUT_HOUR) * 60`) |
##
## [method to_absolute_minutes] is the whole trick: a display time before 6 AM
## belongs to the *end* of the day, so it gets `+ 1080`; anything from 6 AM on
## gets `- 360`. Because the conversion is pure, a headless bot and a real
## playthrough stay in lockstep.
##
## ## Why the day ends at 2 AM and not midnight
##
## The retired Unity build rolled the calendar at midnight. That is unreachable
## as a *play* boundary here, because the player collapses at 2 AM and midnight
## sits in the middle of a normal session. So the day boundary is the collapse
## point and the calendar rolls there. See `docs/DECISIONS.md` D13.

const MINUTES_PER_HOUR := 60
## Waking time, and where a new day starts.
const DAY_START_HOUR := 6
## The player collapses here.
const PASS_OUT_HOUR := 2
## One simulation tick advances this many in-game minutes.
const TICK_MINUTES := 10
## A season is exactly 4 weeks.
const DAYS_PER_SEASON := 28
const SEASONS_PER_YEAR := 4
## `DAYS_PER_SEASON * SEASONS_PER_YEAR`.
const DAYS_PER_YEAR := 112

## Absolute minute at which the display clock reads midnight.
const MIDNIGHT_ABSOLUTE := 18 * MINUTES_PER_HOUR
## Absolute minute at which the player collapses.
const PASS_OUT_ABSOLUTE := (18 + PASS_OUT_HOUR) * MINUTES_PER_HOUR

const MONTH_NAMES: Array[String] = ["Spring", "Summer", "Fall", "Winter"]
const DAY_NAMES: Array[String] = [
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
]


## Converts a display time to absolute minutes from the 6:00 AM day start.
##
## The one subtle piece of the whole system: 0:00 through 5:59 AM is the tail of
## the current day, not the head of the next one.
static func to_absolute_minutes(hour: int, minute: int) -> int:
	if hour < DAY_START_HOUR:
		return hour * MINUTES_PER_HOUR + minute + MIDNIGHT_ABSOLUTE
	return hour * MINUTES_PER_HOUR + minute - DAY_START_HOUR * MINUTES_PER_HOUR


## The inverse. [param absolute] is clamped into the playable window.
static func to_display_time(absolute: int) -> Vector2i:
	var clamped := clampi(absolute, 0, PASS_OUT_ABSOLUTE)
	return Vector2i(
		(clamped / MINUTES_PER_HOUR + DAY_START_HOUR) % 24,
		clamped % MINUTES_PER_HOUR
	)


## Schedule-friendly time where 6:00 AM is `600`, midnight is `2400` and 2:00 AM
## is `2600`. The unit is HHMM, not minutes.
##
## Authored NPC schedule windows use these so that a window spanning midnight
## stays **monotonic** instead of wrapping to zero. A schedule that says "the
## tavern is busy from 22:00 to 02:00" must read as busy-from-2200 to
## busy-from-2600, not busy-from-2200 busy-from-0200 busy-from-2200.
##
## Hours below [constant DAY_START_HOUR] are shifted past 24 for exactly that
## reason. Note this is a *display* scale, not a duration: it is not comparable
## with [method to_absolute_minutes], which is in real minutes from 6:00 AM.
static func to_game_minutes(hour: int, minute: int) -> int:
	var scaled_hour := hour if hour >= DAY_START_HOUR else hour + 24
	return scaled_hour * 100 + minute


## Display-clock arithmetic that wraps at midnight, independent of the day
## model. Used for things that care only about a wall clock.
static func add_minutes(hour: int, minute: int, delta: int) -> Vector2i:
	var total := hour * MINUTES_PER_HOUR + minute + delta
	total = posmod(total, 24 * MINUTES_PER_HOUR)
	return Vector2i(total / MINUTES_PER_HOUR, total % MINUTES_PER_HOUR)


## Zero-based week of the month, so a 28-day season is always `0..3`.
static func week_of(day_of_month: int) -> int:
	return (day_of_month - 1) / 7


## Absolute 0-based day. Day 1 of year 1 is `0`.
static func day_index(time: WorldTime) -> int:
	return (time.year - 1) * DAYS_PER_YEAR \
		+ time.season * DAYS_PER_SEASON \
		+ (time.day_of_month - 1)


## `0 = Sunday`, kept in range across a whole year.
static func day_of_week(time: WorldTime) -> int:
	return posmod(day_index(time), 7)


static func day_name(time: WorldTime) -> String:
	return DAY_NAMES[day_of_week(time)]


## Signed whole days from one date to another. Negative when the target is in
## the past.
static func days_until(from_date: WorldTime, to_date: WorldTime) -> int:
	return day_index(to_date) - day_index(from_date)


static func season_name(season: int) -> String:
	return MONTH_NAMES[posmod(season, SEASONS_PER_YEAR)]


static func day_name_of(index: int) -> String:
	return DAY_NAMES[posmod(index, 7)]


## Moves forward, clamps at the collapse point, and rolls the calendar when the
## day ends.
##
## Returns a dictionary describing what happened, so a caller driving a HUD or
## an event bus does not have to diff the old and new values:
##
## ```
## { time, day_rolled, season_rolled, year_rolled, passed_out, minutes_advanced }
## ```
##
## `time` is always a new object. The input is never modified.
##
## The rollover note that matters: when the day rolls, the leftover minutes are
## written as `remaining + DAY_START_HOUR * MINUTES_PER_HOUR`. Writing the raw
## overflow instead puts the new morning at 00:00, which
## [method to_absolute_minutes] reads back as 18:00 the previous day, so the
## very next tick rolls the day over again, forever. That was a real bug in the
## Unity build and the reason this method has a comment rather than three lines.
static func advance(time: WorldTime, minutes: int) -> Dictionary:
	var result := time.copy()
	var absolute := to_absolute_minutes(result.hour, result.minute)
	var requested := maxi(minutes, 0)

	# The collapse point is a hard wall. A farmer cannot play past 2 AM; a bot
	# simulating 112 days must not silently skip into the next morning either.
	# `maxi` because a clock already at or past the collapse would otherwise get a
	# negative budget, and a negative `moved` would rewind the day.
	var playable := maxi(PASS_OUT_ABSOLUTE - absolute, 0)
	var moved := mini(requested, playable)
	var target := absolute + moved

	# `passed_out` is sticky. Once the player has collapsed, a later advance must
	# not quietly revive them — the morning belongs to [method wake_after_collapse]
	# or [method next_day_morning], which are explicit about ending the day.
	var collapsed := result.passed_out or target >= PASS_OUT_ABSOLUTE
	var transition := {
		"time": result,
		"day_rolled": false,
		"season_rolled": false,
		"year_rolled": false,
		"passed_out": collapsed,
		"minutes_advanced": moved,
	}
	result.passed_out = collapsed

	if target >= PASS_OUT_ABSOLUTE:
		# The player collapses here and the day rolls. Midnight is not the day
		# boundary: 2 AM is, because that is where the collapse point sits and
		# the player cannot play past it.
		var rolled := _roll_day(result)
		transition["day_rolled"] = true
		transition["season_rolled"] = rolled["season_rolled"]
		transition["year_rolled"] = rolled["year_rolled"]
		# The new morning is 6:00 AM, not midnight. Writing the raw leftover
		# overflow here is the bug the Unity build shipped: a 00:00 morning is
		# read back by `to_absolute_minutes` as 18:00 on the *previous* day, so
		# the next tick rolls the day over again — forever.
		#
		# `moved` is clamped to the collapse point, so there is no leftover to
		# carry into the morning and this is always exactly 6:00 AM. The clamp
		# is what makes that true, and the comment is here so nobody "fixes" it
		# into a carry-over without also reworking the clamp.
		result.hour = DAY_START_HOUR
		result.minute = 0
	else:
		var display := to_display_time(target)
		result.hour = display.x
		result.minute = display.y

	return transition


## Ends the day and jumps to the next 6:00 AM, bypassing the collapse clamp.
##
## This is the *sleep* path. It always ends the current day, so it always rolls
## the calendar: a player who goes to bed at 1:00 AM wakes on the following
## morning, because the 6:00 AM that starts their day has already gone by.
##
## It is deliberately not the path used after a collapse — see
## [method wake_after_collapse] for that, which does not roll. Collapsing already
## rolls the calendar in [method advance], and rolling twice would skip a day.
static func next_day_morning(time: WorldTime) -> WorldTime:
	var result := time.copy()
	_roll_day(result)
	result.hour = DAY_START_HOUR
	result.minute = 0
	result.passed_out = false
	return result


## Clears [member WorldTime.passed_out] and puts the clock at 6:00 AM on the day
## it is *already* on.
##
## Used when a player collapses and is carried home. [method advance] has already
## rolled the calendar at the collapse point, so the morning they wake on is the
## current date. Rolling again here would cost the player a day for having
## collapsed, which is exactly the outcome the collapse penalty is meant to be.
static func wake_after_collapse(time: WorldTime) -> WorldTime:
	var result := time.copy()
	result.hour = DAY_START_HOUR
	result.minute = 0
	result.passed_out = false
	return result


## Resets to 6:00 AM on the *same* day, keeping weather. Used by a new game and
## by "start a new day" debug paths.
static func start_new_day(time: WorldTime) -> WorldTime:
	var result := time.copy()
	result.hour = DAY_START_HOUR
	result.minute = 0
	result.passed_out = false
	return result


## Advances the calendar by one day. Returns which boundaries were crossed, so
## the caller can publish `season_changed` / `year_changed` without comparing
## old and new values itself.
static func _roll_day(result: WorldTime) -> Dictionary:
	result.day_of_month += 1
	var season_rolled := false
	var year_rolled := false
	if result.day_of_month > DAYS_PER_SEASON:
		result.day_of_month = 1
		result.season += 1
		season_rolled = true
		if result.season >= SEASONS_PER_YEAR:
			result.season = 0
			result.year += 1
			year_rolled = true
	return {"season_rolled": season_rolled, "year_rolled": year_rolled}


## Convenience: how many [constant TICK_MINUTES] ticks make up a whole day.
static func ticks_per_day() -> int:
	return PASS_OUT_ABSOLUTE / TICK_MINUTES


## How many real seconds one in-game tick should take at `scale`.
##
## A full day is `ticks_per_day()` ticks, so a 10-minute day is 120 ticks.
## `minutes_per_second` of 10 makes a day 120 seconds; the default below gives a
## roughly 10-minute day, matching the session shape in the GDD.
static func seconds_per_tick(seconds_per_day: float) -> float:
	var ticks := float(ticks_per_day())
	return seconds_per_day / maxf(ticks, 1.0)
