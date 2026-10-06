extends TestSuite
## M5 content: the places a villager can be sent, and the day that sends them.
##
## Two directories, one question each. [LocationRegistry] answers "does this id
## name a real place"; [ScheduleRegistry] answers "where is this person at 10:00".
## Both are content-only, so every case here runs with no scene tree at all — which
## is what makes it cheap to ask the awkward ones, like *every* hour of *every*
## season for *every* villager.
##
## ## Why the overlap pair is tested with blocks built in the test
##
## `NpcSchedule.is_valid` refuses two blocks that claim the same clock, and the only
## reason the shipped content passes is that this check used to sweep
## `range(600, 300)` — an *empty* range, so it rejected nothing and an unconditional
## block sat on top of Halda's whole Fall. A test that only asserted "the six files
## load" would have passed then too. So the rule itself is pinned here with blocks
## written in the test, where a regression cannot hide behind content that happens
## to be well-formed.
##
## `haldas_harvest_block_wins_in_fall_and_only_in_fall` is the same bug pointed the
## other way: the content as shipped, asserting what a player in October actually
## sees.

const HALDA := &"halda"
const VILLAGE_SQUARE := &"village_square"
const VILLAGE_ORCHARD := &"village_orchard"


func get_cases() -> Array[StringName]:
	return [
		&"schedules_load_from_disk",
		&"every_schedule_is_valid",
		&"schedule_ids_are_unique",
		&"every_schedule_belongs_to_a_villager_in_the_content",
		&"every_schedule_only_names_real_locations",
		&"every_schedule_resolves_all_day_in_every_season",
		&"a_villager_with_no_schedule_has_none",
		&"cottage_locations_match_the_homes_they_came_from",
		&"locations_load_from_disk",
		&"every_location_is_valid",
		&"location_ids_are_unique",
		&"every_location_kind_is_one_the_game_knows",
		&"two_blocks_on_the_same_clock_are_refused",
		&"two_blocks_for_disjoint_seasons_may_share_a_clock",
		&"haldas_harvest_block_wins_in_fall_and_only_in_fall",
		&"every_block_is_reachable_in_its_own_time",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"schedules_load_from_disk":
			return check_greater(case, float(ScheduleRegistry.all_schedules().size()), 0.0)
		&"every_schedule_is_valid":
			var bad: Array[String] = []
			for schedule: NpcSchedule in ScheduleRegistry.all_schedules():
				if not schedule.is_valid():
					bad.append("%s: %s" % [schedule.npc_id, schedule.describe()])
			return check_equals(case, bad, [] as Array[String])
		&"schedule_ids_are_unique":
			return check_equals(
				case, ScheduleRegistry.duplicate_ids(), [] as Array[StringName]
			)
		&"every_schedule_belongs_to_a_villager_in_the_content":
			var bad: Array[String] = []
			for schedule: NpcSchedule in ScheduleRegistry.all_schedules():
				if NpcRegistry.get_npc(schedule.npc_id) == null:
					bad.append(String(schedule.npc_id))
			return check_equals(case, bad, [] as Array[String])
		&"every_schedule_only_names_real_locations":
			# A block naming a place with no [LocationData] behind it is not a bug the
			# player sees as a bug: the villager simply does not leave home, and the
			# only trace is one warning in a log nobody opened.
			var bad: Array[String] = []
			for schedule: NpcSchedule in ScheduleRegistry.all_schedules():
				for id: StringName in schedule.destinations():
					if LocationRegistry.get_location(id) == null:
						bad.append("%s -> %s" % [schedule.npc_id, id])
			return check_equals(case, bad, [] as Array[String])
		&"every_schedule_resolves_all_day_in_every_season":
			return _check_resolves_everywhere(case)
		&"a_villager_with_no_schedule_has_none":
			# Null, not an empty schedule. An empty schedule would be a day with no
			# blocks in it, which `is_valid` calls an oversight; "nobody wrote one" is
			# a different and perfectly ordinary answer.
			return check_null(case, ScheduleRegistry.schedule_for(&"nobody_at_all"))
		&"cottage_locations_match_the_homes_they_came_from":
			# The spawn point and the place a schedule sends someone home are the same
			# number, derived from the same field by the generator. Pinned because a
			# generator that writes one correctly today and the other after a hand edit
			# is exactly what nobody notices until someone wakes up inside a wall.
			var bad: Array[String] = []
			for data: NpcData in NpcRegistry.all_npcs():
				var id := StringName("%s_cottage" % data.id)
				var place := LocationRegistry.get_location(id)
				if place == null:
					bad.append("%s has no cottage" % data.id)
					continue
				if place.position != data.home:
					bad.append("%s cottage at %s, home at %s" % [data.id, place.position, data.home])
			return check_equals(case, bad, [] as Array[String])
		&"locations_load_from_disk":
			return check_greater(case, float(LocationRegistry.all_locations().size()), 0.0)
		&"every_location_is_valid":
			var bad: Array[String] = []
			for place: LocationData in LocationRegistry.all_locations():
				if not place.is_valid():
					bad.append(place.describe())
			return check_equals(case, bad, [] as Array[String])
		&"location_ids_are_unique":
			return check_equals(
				case, LocationRegistry.duplicate_ids(), [] as Array[StringName]
			)
		&"every_location_kind_is_one_the_game_knows":
			var bad: Array[String] = []
			for place: LocationData in LocationRegistry.all_locations():
				if not LocationData.KINDS.has(place.kind):
					bad.append("%s = %s" % [place.id, place.kind])
			return check_equals(case, bad, [] as Array[String])
		&"two_blocks_on_the_same_clock_are_refused":
			return _check_overlap_refused(case, false)
		&"two_blocks_for_disjoint_seasons_may_share_a_clock":
			return _check_overlap_refused(case, true)
		&"haldas_harvest_block_wins_in_fall_and_only_in_fall":
			return _check_halda(case)
		&"every_block_is_reachable_in_its_own_time":
			return _check_reachable(case)
	return fail(case, "unhandled case")


## Resolves every schedule at every hour of every day, in every season and weather.
##
## Deliberately exhaustive rather than one sample per season. `location_at` is a
## filter chain — window, then season, then weather — and each of the three can fail
## on its own: a window that never opens, a season list missing a value, a weather
## gate that no weather satisfies. One sample at noon finds the first and misses the
## other two entirely.
func _check_resolves_everywhere(case: StringName) -> Dictionary:
	var hours: Array[int] = []
	for hour: int in range(Clock.DAY_START_HOUR, 24):
		hours.append(hour)
	# The small hours belong to the tail of the same day on the monotonic scale.
	for hour: int in range(0, Clock.PASS_OUT_HOUR + 1):
		hours.append(hour)
	var seasons: Array[int] = [
		WorldTime.Season.SPRING, WorldTime.Season.SUMMER,
		WorldTime.Season.FALL, WorldTime.Season.WINTER,
	]
	var weathers: Array[int] = []
	for weather: int in range(WorldTime.WEATHER_NAMES.size()):
		weathers.append(weather)

	for schedule: NpcSchedule in ScheduleRegistry.all_schedules():
		var home_id := StringName("%s_cottage" % schedule.npc_id)
		for season: int in seasons:
			for weather: int in weathers:
				for hour: int in hours:
					for minute: int in [0, 30]:
						var time := WorldTime.new(1, season, 1, hour, minute)
						time.weather = weather
						var loc := schedule.location_at(time, home_id)
						if loc.is_empty():
							return fail(case, "%s resolved to nothing at %s" % [
								schedule.npc_id, time.describe_time(),
							])
						if LocationRegistry.get_location(loc) == null:
							return fail(case, "%s wants '%s' in %s, which has no location" % [
								schedule.npc_id, loc, time.describe_date(),
							])
	return succeeded(case)


## Whether a pair of blocks sharing a window is refused, when they share a season.
##
## [param disjoint] true builds the pair for two different seasons, which is legal and
## is how the rain-only routines in the shipped content are written; false builds both
## for every season, which is the authoring mistake.
func _check_overlap_refused(case: StringName, disjoint: bool) -> Dictionary:
	var morning := _block(700, 1700, VILLAGE_SQUARE)
	var late_morning := _block(700, 1200, VILLAGE_ORCHARD)
	if disjoint:
		morning.seasons = [WorldTime.Season.FALL]
		late_morning.seasons = [
			WorldTime.Season.SPRING, WorldTime.Season.SUMMER, WorldTime.Season.WINTER,
		]
	var schedule := NpcSchedule.new()
	schedule.npc_id = &"overlap_probe"
	var entries: Array[NpcScheduleEntry] = [morning, late_morning]
	schedule.entries = entries
	if disjoint:
		return check_true(case, schedule.is_valid(), "disjoint seasons should be allowed")
	return check_false(case, schedule.is_valid(), "two blocks on the same clock should be refused")


## The shipped Fall bug, asserted from the player's side: at 10:00 Halda is in the
## orchard all year except Fall, when she minds the harvest instead.
func _check_halda(case: StringName) -> Dictionary:
	var schedule := ScheduleRegistry.schedule_for(HALDA)
	if schedule == null:
		return fail(case, "no schedule for Halda")
	var home := StringName("%s_cottage" % HALDA)
	var spring := schedule.location_at(WorldTime.new(1, WorldTime.Season.SPRING, 1, 10, 0), home)
	var fall := schedule.location_at(WorldTime.new(1, WorldTime.Season.FALL, 1, 10, 0), home)
	if spring != VILLAGE_ORCHARD:
		return fail(case, "a spring morning sent her to %s, not %s" % [spring, VILLAGE_ORCHARD])
	if fall != VILLAGE_SQUARE:
		return fail(case, "a fall morning sent her to %s, not %s" % [fall, VILLAGE_SQUARE])
	return succeeded(case)


func _block(from: int, to: int, where: StringName) -> NpcScheduleEntry:
	var entry := NpcScheduleEntry.new()
	entry.from_minute = from
	entry.to_minute = to
	entry.location = where
	entry.activity = &"probing"
	return entry


## Whether every block is stood in for at least some of the time it claims.
##
## A schedule block says "be at the well from noon to one". It does not say how long
## getting there takes, and nothing in the content reserves the time: the clock crosses
## the boundary and the villager is handed a new post, with whatever distance separates
## the two places still in front of them. When that walk outlasts the block they arrive
## somewhere the block has already ended, and the post they were meant to be at is never
## occupied by anyone. There is no error and no warning — just a place in the content
## that no player will ever see anybody stand in.
##
## This is the case that found Bram's one-hour block at the well, 61 m from the forest
## edge he was hauling timber at and a 1.5 m/s walk: 40.7 real seconds against a 30
## second window. The walk is content, the window is content, and both were written
## separately by hand, which is exactly the sort of thing a test exists for.
##
## The predecessor considered is the worst one the clock could have just left rather
## than the one resolution picks, because two blocks may share a boundary across
## seasons and there are four seasons. "Whichever they came from, they can make it"
## cannot let a near miss through.
func _check_reachable(case: StringName) -> Dictionary:
	var seconds_per_minute := _seconds_per_in_game_minute()
	var failures: Array[String] = []
	for schedule: NpcSchedule in ScheduleRegistry.all_schedules():
		var data := NpcRegistry.get_npc(schedule.npc_id)
		if data == null or data.walk_speed <= 0.0:
			continue
		var home_id := StringName("%s_cottage" % schedule.npc_id)
		for index: int in schedule.entries.size():
			var entry := schedule.entries[index]
			if entry.location.is_empty():
				continue
			if LocationRegistry.get_location(entry.location) == null:
				# Named by nowhere real: `every_schedule_only_names_real_locations`.
				continue
			var walk := _worst_walk_to(schedule, index, home_id, data.walk_speed)
			var window := _minutes(entry.to_minute) - _minutes(entry.from_minute)
			var presence := window * seconds_per_minute - walk
			if presence <= 0.0:
				failures.append("%s @ %s from %d: walks %.1f s into a %.1f s block" % [
					schedule.npc_id,
					entry.location,
					entry.from_minute,
					walk,
					window * seconds_per_minute,
				])
	return check_equals(case, failures, [] as Array[String])


## Longest time to reach `index`, over every block the clock could have just left.
func _worst_walk_to(
	schedule: NpcSchedule, index: int, home_id: StringName, speed: float
) -> float:
	var entry := schedule.entries[index]
	var here := LocationRegistry.get_location(entry.location)
	if here == null:
		return 0.0
	var worst := -1.0
	for other: int in schedule.entries.size():
		if other == index:
			continue
		var previous := schedule.entries[other]
		if previous.to_minute > entry.from_minute:
			continue
		if previous.location == entry.location:
			continue
		var there := LocationRegistry.get_location(previous.location)
		if there == null:
			continue
		worst = maxf(worst, here.position.distance_to(there.position) / speed)
	if worst >= 0.0:
		return worst
	# Nothing precedes it, so it is the first block of the day and they start at home.
	var home := LocationRegistry.get_location(home_id)
	if home == null:
		return 0.0
	return here.position.distance_to(home.position) / speed


## Real seconds that one in-game minute lasts, read off the shipped clock.
##
## Derived rather than asserted so that changing the length of a day re-tightens these
## windows instead of leaving them measured against the number they used to be.
func _seconds_per_in_game_minute() -> float:
	var service := TimeService.new()
	var seconds := service.seconds_per_day / float(
		service.ticks_per_day * Clock.TICK_MINUTES
	)
	service.free()
	return seconds


## [param value] in [method Clock.to_game_minutes] units, as minutes past the start of
## the day. The small hours are `2400` and up, which is why this is not a division.
func _minutes(value: int) -> int:
	var clock := mini(value, Clock.to_game_minutes(Clock.PASS_OUT_HOUR, 0))
	var hour := int(clock / 100.0)
	if hour < Clock.DAY_START_HOUR:
		hour += 24
	return hour * Clock.MINUTES_PER_HOUR + clock % 100
