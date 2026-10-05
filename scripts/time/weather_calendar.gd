class_name WeatherCalendar
extends RefCounted
## What the sky is doing on a given date, as a pure function of the date.
##
## ## Why this is derived and not rolled
##
## Weather is **not** drawn from a running generator. It is a function of the absolute
## day index, so `Year 1 Spring 3` is wet whether you reach it by playing for three days,
## by loading a save made on day 40, or by jumping there with the dev console. That buys
## three things a rolling generator cannot:
##
## - A save never disagrees with itself. Reload a save and the weather is the weather you
##   left, without one byte of weather in the save file.
## - [method TimeService.set_time] and the bot simulation both land on the same sky, so a
##   112-day balance run and a 40-day playthrough are comparable.
## - A failed day can be replayed. Determinism was already non-negotiable for villager
##   movement — see `scripts/npc/npc.gd` — and it would be strange for the weather to be
##   the one thing that rolled differently on the second attempt.
##
## ## The table
##
## Recovered from the retired Unity sim, `docs/SALVAGED_DESIGN.md` §"Weather weights per
## season": spring 6/2/1/0/1, summer 7/2/1/0/0, fall 6/2/1/0/1, winter 6/0/0/3/1 across
## Sun/Rain/Storm/Snow/Wind. Winter trades rain for snow and summer is driest. The full
## weather *system* — VFX, sky, what fishing does — is milestone M9. This group pulled
## forward only the daily roll, because NPC schedules were promised weather-aware variants
## and there is no honest way to ship a rain override against a permanently sunny sky.
##
## ## Consecutive days
##
## [method weather_for] and [method forecast_for] hash the day index separately, so a
## rainy today does not imply a wet tomorrow. Consecutive days are correlated in reality
## and uncorrelated here; that is a fair simplification for a table this small, and it is
## recorded rather than hidden. Weather is re-examined if M9 wants persistence.


## Weight per [enum WorldTime.Weather] per [enum WorldTime.Season], indexed
## `[season][weather]`. Ordered to match the enum so a row can be read straight off.
const WEIGHTS: Array[Array] = [
	[6, 2, 1, 0, 1],  # Spring
	[7, 2, 1, 0, 0],  # Summer
	[6, 2, 1, 0, 1],  # Fall
	[6, 0, 0, 3, 1],  # Winter
]

## Mixed into the day index so a neighbouring day does not land in a neighbouring bucket.
##
## Without it, `day_index * k` bands the five outcomes across consecutive days in a
## visible rhythm — three wet days, then three dry, forever.
const SALT := 0x27D4EB2F


## The sky on the day at [param index], a [method Clock.day_index] value.
##
## Never returns a value outside [enum WorldTime.Weather]: an out-of-range season falls
## back to the spring row rather than indexing off the end of the table, because a
## corrupt save should give an ordinary day, not a crash on the first frame.
static func weather_for_index(index: int) -> int:
	return _weighted_pick(index, _weights_for(index))


## The sky on [param time]'s date.
static func weather_for(time: WorldTime) -> int:
	return weather_for_index(Clock.day_index(time))


## The sky on the day after [param index], for the forecast shown tonight.
static func forecast_for_index(index: int) -> int:
	return weather_for_index(index + 1)


## The sky on the day after [param time]'s date.
static func forecast_for(time: WorldTime) -> int:
	return forecast_for_index(Clock.day_index(time))


## Every weather id that can occur on the day at [param index].
##
## Exposed so a test can assert the realised distribution against the table rather than
## against a handful of hand-picked days, which would pass just as happily if the hash
## only ever produced rain.
static func possible_weather(index: int) -> Array[int]:
	var out: Array[int] = []
	var row := _weights_for(index)
	for i: int in range(row.size()):
		if int(row[i]) > 0:
			out.append(i)
	return out


## The weight row for the day at [param index].
##
## Uses the season of that day, which means tomorrow's forecast obeys tomorrow's season —
## the last day of winter forecasts the first day of spring.
static func _weights_for(index: int) -> Array:
	var season := posmod(floori(float(index) / Clock.DAYS_PER_SEASON), Clock.SEASONS_PER_YEAR)
	return WEIGHTS[season]


## Picks one entry from the row for [param index], weighted and deterministically.
##
## Returns an index into the row, which is already a [enum WorldTime.Weather] value. The
## accumulator walks the row in enum order, so the result depends only on the hash —
## never on iteration order or the order anyone wrote the table in.
static func _weighted_pick(index: int, weights: Array) -> int:
	var total := 0
	for w: Variant in weights:
		total += maxi(int(w), 0)
	if total <= 0:
		return WorldTime.Weather.SUN
	var roll := _mix(index) % total
	var running := 0
	for i: int in range(weights.size()):
		running += maxi(int(weights[i]), 0)
		if roll < running:
			return i
	return WorldTime.Weather.SUN


## A 32-bit avalanche, so nearby day indices land in unrelated buckets.
##
## A plain multiply spreads index 5 and index 6 into nearby buckets and the bands show up
## as weather patterns. Three xors, two multiplies and a shift fixes it, and 32 bits is
## plenty: a row of weights sums to ten, so there are ten buckets to choose between.
##
## Deliberately not the 64-bit SplitMix64 constants — GDScript integer literals are
## signed 64-bit and those values do not fit, so using them means writing them as
## negatives and relying on wraparound for no benefit.
static func _mix(index: int) -> int:
	var h := (index ^ SALT) * 0x45D9F3B
	h = h ^ (h >> 15)
	h *= 0x45D9F3B
	h = h ^ (h >> 13)
	return absi(h)


## Sets [param time]'s weather and forecast from its own date, and reports what changed.
##
## Returns `{"weather": bool, "forecast": bool}` — which of the two actually moved — so a
## caller emits one signal per field instead of guessing. Mutates in place; [WorldTime] is
## copied on every clock operation, so this runs once per day boundary and is cheap.
static func apply(time: WorldTime) -> Dictionary:
	var today := weather_for(time)
	var tomorrow := forecast_for(time)
	var changed := {
		"weather": time.weather != today,
		"forecast": time.forecast != tomorrow,
	}
	time.weather = today
	time.forecast = tomorrow
	return changed