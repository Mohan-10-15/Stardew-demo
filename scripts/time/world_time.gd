class_name WorldTime
extends Resource
## The complete state of the game's calendar and clock, as a value.
##
## Deliberately a `Resource` holding only primitives: it is copied on every
## advance, serialised to a save file, and compared field-by-field in tests. No
## node references, so a save can never capture a freed object.
##
## [Clock] owns all the arithmetic. This class is the data it operates on.
##
## The clock runs 6:00 AM to 2:00 AM. A day is bounded by the collapse hour, not
## by midnight — see [Clock.advance] for why, and `docs/DECISIONS.md` D13.

enum Season { SPRING, SUMMER, FALL, WINTER }
## Weather ids are placeholders until M9; the weights table lives in
## `docs/SALVAGED_DESIGN.md`. They are carried on the time value from the start
## so a save taken today is still readable after M9 ships.
enum Weather { SUN, RAIN, STORM, SNOW, WIND }
const WEATHER_NAMES: Array[String] = ["Sunny", "Rain", "Storm", "Snow", "Windy"]

## 1-based.
var year: int = 1
## A [Season] value.
var season: int = Season.SPRING
## 1-based, 1..28.
var day_of_month: int = 1
## Display hour, 0..23. 6 is 6:00 AM.
var hour: int = Clock.DAY_START_HOUR
## Display minute, 0..59.
var minute: int = 0
## Today's [Weather] value. Survives a day rollover.
var weather: int = Weather.SUN
## Tomorrow's [Weather] value, so the forecast shown tonight is tomorrow's.
var forecast: int = Weather.SUN
## Set once the player collapses at 2:00 AM and never cleared. A new day is
## started by [Clock.start_new_day] or [Clock.next_day_morning], not by
## forgetting this happened.
var passed_out: bool = false


func _init(
	p_year: int = 1,
	p_season: int = Season.SPRING,
	p_day: int = 1,
	p_hour: int = Clock.DAY_START_HOUR,
	p_minute: int = 0
) -> void:
	year = p_year
	season = p_season
	day_of_month = p_day
	hour = p_hour
	minute = p_minute


## An independent copy. Every mutating clock operation copies before changing,
## so `next_day_morning(world)` leaving its input untouched is structural rather
## than a rule the caller has to remember.
func copy() -> WorldTime:
	var out := WorldTime.new(year, season, day_of_month, hour, minute)
	out.weather = weather
	out.forecast = forecast
	out.passed_out = passed_out
	return out


## "Year 1 Spring 4"
func describe_date() -> String:
	return "Year %d %s %d" % [year, Clock.season_name(season), day_of_month]


## "Rain"
##
## Out-of-range ids resolve to Sunny rather than crashing, so a save written by a
## later build with extra weather values still loads in this one.
static func weather_name(weather: int) -> String:
	if weather < 0 or weather >= WEATHER_NAMES.size():
		return WEATHER_NAMES[Weather.SUN]
	return WEATHER_NAMES[weather]


## "6:30 AM"
func describe_time() -> String:
	var suffix := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, suffix]


func to_dict() -> Dictionary:
	return {
		"year": year,
		"season": season,
		"day_of_month": day_of_month,
		"hour": hour,
		"minute": minute,
		"weather": weather,
		"forecast": forecast,
		"passed_out": passed_out,
	}


## Restores from [method to_dict].
##
## Every field is clamped independently rather than the payload being accepted
## whole or rejected whole. A save that lost one field loads with that field at
## its default; a save with an out-of-range field loads at the nearest valid
## value. Rejecting the whole payload loses a year of progress over a single
## corrupt int, which is worse than losing one field.
static func from_dict(data: Dictionary) -> WorldTime:
	var out := WorldTime.new()
	out.year = maxi(int(data.get("year", 1)), 1)
	# `clampi`, not `posmod`, on the enums. `posmod(-1, 4)` is 3, which is Winter —
	# a corrupt save would silently load the last season of the year. Clamping
	# negatives to 0 loads Spring, which is the first season and the sane default.
	out.season = clampi(int(data.get("season", Season.SPRING)), 0, Clock.SEASONS_PER_YEAR - 1)
	out.day_of_month = clampi(int(data.get("day_of_month", 1)), 1, Clock.DAYS_PER_SEASON)
	out.hour = clampi(int(data.get("hour", Clock.DAY_START_HOUR)), 0, 23)
	out.minute = clampi(int(data.get("minute", 0)), 0, 59)
	out.weather = clampi(int(data.get("weather", Weather.SUN)), 0, Weather.size() - 1)
	out.forecast = clampi(int(data.get("forecast", Weather.SUN)), 0, Weather.size() - 1)
	out.passed_out = bool(data.get("passed_out", false))
	return out
