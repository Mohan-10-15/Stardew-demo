extends TestSuite
## M2 time and calendar.
##
## Every case here is either a direct transcription of the calendar model in
## `docs/SALVAGED_DESIGN.md` or an edge case the retired Unity build broke at
## some point. The list is deliberately not "what the code happens to do" — the
## value is in the cases that would catch a regression nobody would notice.
##
## The service is a thin driver over [Clock]. If a case here needs the service
## to make sense, the split is wrong.

func get_cases() -> Array[StringName]:
	return [
		&"day_start_is_absolute_minute_zero",
		&"pre_dawn_times_belong_to_the_end_of_the_day",
		&"game_minutes_are_monotonic_across_midnight",
		&"advancing_past_midnight_does_not_roll_the_day",
		&"advancing_just_before_midnight_does_not_roll",
		&"collapse_at_2am_rolls_the_day",
		&"advancing_past_collapse_clamps",
		&"passed_out_stays_set",
		&"a_full_day_of_ticks_advances_exactly_one_day",
		&"the_season_rolls_after_day_28",
		&"the_year_rolls_after_winter",
		&"next_day_morning_works_from_a_late_night_clock",
		&"next_day_morning_does_not_mutate_its_input",
		&"sleeping_rolls_the_day_but_collapsing_does_not",
		&"the_service_freezes_the_clock_after_a_collapse",
		&"the_lighting_cycle_tracks_the_clock",
		&"the_lighting_cycle_is_darkest_at_the_collapse",
		&"the_clock_hud_shows_the_current_date",
		&"weather_survives_the_advance",
		&"day_of_week_stays_in_range_across_a_year",
		&"week_of_is_zero_based",
		&"days_until_is_signed",
		&"describe_date_reads_as_a_sentence",
		&"saves_round_trip_without_changing_the_clock",
		&"negative_values_are_clamped_not_wrapped",
		&"a_corrupt_save_degrades_field_by_field",
		&"the_service_publishes_time_signals",
		&"a_day_has_the_same_weather_however_you_reach_it",
		&"a_year_contains_more_than_one_kind_of_weather",
		&"snow_only_falls_in_winter",
		&"the_weather_weights_hold_across_a_whole_year",
		&"rain_waters_the_plot",
		&"the_day_boundary_announces_the_new_weather",
		&"a_save_written_before_the_weather_existed_loads_with_a_sky",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"day_start_is_absolute_minute_zero":
			return _t_day_start(case)
		&"pre_dawn_times_belong_to_the_end_of_the_day":
			return _t_pre_dawn(case)
		&"game_minutes_are_monotonic_across_midnight":
			return _t_monotonic(case)
		&"advancing_past_midnight_does_not_roll_the_day":
			return _t_no_roll_at_midnight(case)
		&"advancing_just_before_midnight_does_not_roll":
			return _t_no_roll_before_midnight(case)
		&"collapse_at_2am_rolls_the_day":
			return _t_collapse_rolls(case)
		&"advancing_past_collapse_clamps":
			return _t_clamps(case)
		&"passed_out_stays_set":
			return _t_passed_out_sticks(case)
		&"a_full_day_of_ticks_advances_exactly_one_day":
			return _t_full_day(case)
		&"the_season_rolls_after_day_28":
			return _t_season_roll(case)
		&"the_year_rolls_after_winter":
			return _t_year_roll(case)
		&"next_day_morning_works_from_a_late_night_clock":
			return _t_morning_from_late_night(case)
		&"next_day_morning_does_not_mutate_its_input":
			return _t_morning_is_pure(case)
		&"sleeping_rolls_the_day_but_collapsing_does_not":
			return _t_sleep_vs_collapse(case)
		&"the_service_freezes_the_clock_after_a_collapse":
			return _t_service_freezes(case)
		&"the_lighting_cycle_tracks_the_clock":
			return _t_lighting_tracks_clock(case)
		&"the_lighting_cycle_is_darkest_at_the_collapse":
			return _t_lighting_darkest(case)
		&"the_clock_hud_shows_the_current_date":
			return _t_clock_hud_reads_service(case)
		&"weather_survives_the_advance":
			return _t_weather_survives(case)
		&"day_of_week_stays_in_range_across_a_year":
			return _t_day_of_week_range(case)
		&"week_of_is_zero_based":
			return _t_week_of(case)
		&"days_until_is_signed":
			return _t_days_until(case)
		&"describe_date_reads_as_a_sentence":
			return _t_describe(case)
		&"saves_round_trip_without_changing_the_clock":
			return _t_save_round_trip(case)
		&"negative_values_are_clamped_not_wrapped":
			return _t_negative_values(case)
		&"a_corrupt_save_degrades_field_by_field":
			return _t_corrupt_save(case)
		&"the_service_publishes_time_signals":
			return _t_service_signals(case)
		&"a_day_has_the_same_weather_however_you_reach_it":
			return _t_weather_is_derived(case)
		&"a_year_contains_more_than_one_kind_of_weather":
			return _t_weather_varies(case)
		&"snow_only_falls_in_winter":
			return _t_snow_is_winter_only(case)
		&"the_weather_weights_hold_across_a_whole_year":
			return _t_weather_distribution(case)
		&"rain_waters_the_plot":
			return _t_rain_waters(case)
		&"the_day_boundary_announces_the_new_weather":
			return _t_weather_signal(case)
		&"a_save_written_before_the_weather_existed_loads_with_a_sky":
			return _t_old_save_gets_weather(case)
	return fail(case, "unhandled case")


## 6:00 AM is absolute minute zero. Everything else in the system is offset
## from this one fact.
func _t_day_start(case: StringName) -> Dictionary:
	if Clock.to_absolute_minutes(6, 0) != 0:
		return fail(case, "6:00 AM should be absolute minute 0, got %d" % Clock.to_absolute_minutes(6, 0))
	if Clock.to_absolute_minutes(7, 30) != 90:
		return fail(case, "7:30 AM should be 90 minutes in, got %d" % Clock.to_absolute_minutes(7, 30))
	if Clock.to_absolute_minutes(0, 0) != Clock.MIDNIGHT_ABSOLUTE:
		return fail(case, "midnight should be %d, got %d" % [Clock.MIDNIGHT_ABSOLUTE, Clock.to_absolute_minutes(0, 0)])
	if Clock.to_absolute_minutes(2, 0) != Clock.PASS_OUT_ABSOLUTE:
		return fail(case, "2:00 AM should be %d, got %d" % [Clock.PASS_OUT_ABSOLUTE, Clock.to_absolute_minutes(2, 0)])
	return succeeded(case, "6AM=0, midnight=%d, 2AM=%d" % [Clock.MIDNIGHT_ABSOLUTE, Clock.PASS_OUT_ABSOLUTE])


## The subtle one. Pre-dawn display times are the *tail* of the current day, not
## the head of the next one. Without this the day would start twice and the
## collapse hour would land before the player had woken up.
##
## There are two distinct bands here and conflating them is the bug this catches:
##
## - 0:00-2:00 AM is the *playable* tail, and must land inside the window.
## - 2:01-5:59 AM is the player being asleep, and must land *past* the collapse
##   point. These are not valid clock readings; nothing should ever produce them.
##   If a caller ever does, `to_display_time` clamps it back to 2:00 AM rather
##   than teleporting the player to the wrong hour.
func _t_pre_dawn(case: StringName) -> Dictionary:
	for probe: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 30), Vector2i(2, 0)]:
		var absolute := Clock.to_absolute_minutes(probe.x, probe.y)
		if absolute < Clock.MIDNIGHT_ABSOLUTE:
			return fail(case, "%d:%02d AM should be at or past midnight, got %d" % [probe.x, probe.y, absolute])
		if absolute > Clock.PASS_OUT_ABSOLUTE:
			return fail(case, "playable %d:%02d AM is past the collapse point, got %d" % [probe.x, probe.y, absolute])

	for probe: Vector2i in [Vector2i(2, 1), Vector2i(4, 0), Vector2i(5, 59)]:
		var absolute := Clock.to_absolute_minutes(probe.x, probe.y)
		if absolute <= Clock.PASS_OUT_ABSOLUTE:
			return fail(case, "%d:%02d AM is asleep and must be past the collapse point, got %d" % [probe.x, probe.y, absolute])

	# The ordering that makes it work: 0:00 AM is before 2:00 AM inside the day.
	if not (Clock.to_absolute_minutes(0, 0) < Clock.to_absolute_minutes(2, 0)):
		return fail(case, "2:00 AM should be later in the day than midnight")

	# A sleep hour read back through the clamp must not teleport the player.
	var asleep := Clock.to_display_time(Clock.to_absolute_minutes(5, 0))
	if asleep != Vector2i(Clock.PASS_OUT_HOUR, 0):
		return fail(case, "an asleep hour should clamp back to 2:00 AM, got %s" % str(asleep))
	return succeeded(case, "playable pre-dawn is inside the window, sleeping hours are past it")


## A schedule window of "22:00 to 02:00" must read as one continuous span. If
## these wrap, NPC schedules oscillate and the town empties at midnight.
func _t_monotonic(case: StringName) -> Dictionary:
	# The anchors the salvaged design pinned down. These are what authored
	# schedule windows are written against, so they are the contract.
	if Clock.to_game_minutes(6, 0) != 600:
		return fail(case, "6:00 AM should be 600, got %d" % Clock.to_game_minutes(6, 0))
	if Clock.to_game_minutes(0, 0) != 2400:
		return fail(case, "midnight should be 2400, got %d" % Clock.to_game_minutes(0, 0))
	if Clock.to_game_minutes(2, 0) != 2600:
		return fail(case, "2:00 AM should be 2600, got %d" % Clock.to_game_minutes(2, 0))

	# Walk the whole playable day in 10-minute steps, in *chronological* order,
	# and check game minutes never go backwards. Note the walk starts at 6:00 AM:
	# the scale is monotonic across a day, not across an arbitrary 24-hour
	# sweep. 23:59 -> 0:00 is a 1-step increase (2359 -> 2400), but 5:59 -> 6:00
	# is 2950 -> 600, which is the start of the *next* day, not a step backwards.
	var absolute := 0
	var previous := -1
	while absolute <= Clock.PASS_OUT_ABSOLUTE:
		var hour := (absolute / Clock.MINUTES_PER_HOUR + Clock.DAY_START_HOUR) % 24
		var minute := absolute % Clock.MINUTES_PER_HOUR
		var game_minutes := Clock.to_game_minutes(hour, minute)
		if game_minutes < previous:
			return fail(case, "game minutes went backwards at %d:%02d (%d after %d)" % [hour, minute, game_minutes, previous])
		previous = game_minutes
		absolute += Clock.TICK_MINUTES
	if Clock.to_game_minutes(23, 59) >= Clock.to_game_minutes(0, 0):
		return fail(case, "a 23:59 -> 00:00 window must read as increasing")
	return succeeded(case, "game minutes increase monotonically across midnight (6AM=600, midnight=2400, 2AM=2600)")


## Midnight is *interior* to the day, not a boundary. This is decision D13: the
## calendar rolls at the collapse point (2:00 AM), because 2:00 AM is the last
## instant a player can occupy. Rolling at midnight instead would mean a
## rollover with no gameplay event to justify it, and would put the day boundary
## two hours *before* the player is forced to stop.
func _t_no_roll_at_midnight(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 4, 23, 55)
	var result := Clock.advance(time, 5)
	var rolled: WorldTime = result["time"]
	if result["day_rolled"]:
		return fail(case, "crossing midnight must not roll the day, got %s" % rolled.describe_date())
	if rolled.day_of_month != 4:
		return fail(case, "expected to still be day 4, got %d" % rolled.day_of_month)
	if rolled.hour != 0 or rolled.minute != 0:
		return fail(case, "expected 0:00 AM, got %s" % rolled.describe_time())
	if result["passed_out"]:
		return fail(case, "midnight is not the collapse point")
	# Two more hours of the same day are still playable, and nothing about
	# crossing midnight has ended the day yet.
	if Clock.to_display_time(Clock.to_absolute_minutes(rolled.hour, rolled.minute) + 10) != Vector2i(0, 10):
		return fail(case, "0:00 AM should still be mid-session")
	return succeeded(case, "midnight is interior: still day 4 at %s" % rolled.describe_time())


## One minute short of midnight stays on the same day. If this also rolled, the
## player would silently lose a day every evening.
func _t_no_roll_before_midnight(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 4, 23, 54)
	var result := Clock.advance(time, 5)
	var rolled: WorldTime = result["time"]
	if result["day_rolled"]:
		return fail(case, "23:54 -> 23:59 must not roll the day")
	if rolled.day_of_month != 4:
		return fail(case, "day changed to %d without a rollover" % rolled.day_of_month)
	if rolled.hour != 23 or rolled.minute != 59:
		return fail(case, "expected 23:59, got %s" % rolled.describe_time())
	return succeeded(case, "still day 4 at 23:59")


## At 2:00 AM the player collapses *and* the day rolls. Both, not either.
func _t_collapse_rolls(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 4, 1, 55)
	var result := Clock.advance(time, 5)
	var rolled: WorldTime = result["time"]
	if not result["passed_out"]:
		return fail(case, "reaching 2:00 AM should pass the player out")
	if not result["day_rolled"]:
		return fail(case, "the collapse should roll the day")
	if not rolled.passed_out:
		return fail(case, "passed_out was not set on the resulting time")
	if rolled.day_of_month != 5:
		return fail(case, "expected day 5, got %d" % rolled.day_of_month)
	return succeeded(case, "collapsed at 2AM, rolled to %s" % rolled.describe_date())


## A large advance must not skip past the collapse into the next morning. The
## clamp is what makes "the leftover minutes are always zero" true.
func _t_clamps(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 4, 1, 0)
	var result := Clock.advance(time, 100000)
	var rolled: WorldTime = result["time"]
	if int(result["minutes_advanced"]) >= 100000:
		return fail(case, "advance did not clamp: moved %d minutes" % result["minutes_advanced"])
	if rolled.day_of_month != 5:
		return fail(case, "expected exactly one day rollover, got %d" % rolled.day_of_month)
	if rolled.hour != Clock.DAY_START_HOUR or rolled.minute != 0:
		return fail(case, "expected 6:00 AM after clamping, got %s" % rolled.describe_time())
	return succeeded(case, "clamped to the collapse, one day rolled, morning is 6:00 AM")


## Once the player has passed out, that stays true. A later tick must not
## quietly revive them.
func _t_passed_out_sticks(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 4, 2, 0)
	var first := Clock.advance(time, 1)
	var once: WorldTime = first["time"]
	if not once.passed_out:
		return fail(case, "expected passed_out after collapsing")
	var second := Clock.advance(once, 1)
	var twice: WorldTime = second["time"]
	if not twice.passed_out:
		return fail(case, "passed_out was cleared by a later advance")
	return succeeded(case, "passed_out survives subsequent advances")


## The headline determinism property: 120 ten-minute ticks is exactly one day.
## This is also what a bot simulation depends on.
func _t_full_day(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 1, 6, 0)
	for _i: int in range(Clock.ticks_per_day()):
		var step := Clock.advance(time, Clock.TICK_MINUTES)
		time = step["time"]
	var expected_day := 2
	if time.day_of_month != expected_day:
		return fail(case, "%d ticks should land on day %d, got %d (%s)" % [Clock.ticks_per_day(), expected_day, time.day_of_month, time.describe_date()])
	if time.hour != Clock.DAY_START_HOUR or time.minute != 0:
		return fail(case, "expected 6:00 AM, got %s" % time.describe_time())
	return succeeded(case, "%d ticks = 1 day, ending at %s" % [Clock.ticks_per_day(), time.describe_date()])


func _t_season_roll(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, Clock.DAYS_PER_SEASON, 2, 0)
	var result := Clock.advance(time, 1)
	var rolled: WorldTime = result["time"]
	if not result["season_rolled"]:
		return fail(case, "advancing past day %d should roll the season" % Clock.DAYS_PER_SEASON)
	if rolled.season != WorldTime.Season.SUMMER:
		return fail(case, "expected Summer, got %s" % Clock.season_name(rolled.season))
	if rolled.day_of_month != 1:
		return fail(case, "expected day 1 of the new season, got %d" % rolled.day_of_month)
	return succeeded(case, "rolled to %s" % rolled.describe_date())


func _t_year_roll(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.WINTER, Clock.DAYS_PER_SEASON, 2, 0)
	var result := Clock.advance(time, 1)
	var rolled: WorldTime = result["time"]
	if not result["year_rolled"]:
		return fail(case, "the year should roll after winter ends")
	if rolled.year != 2 or rolled.season != WorldTime.Season.SPRING:
		return fail(case, "expected Year 2 Spring, got %s" % rolled.describe_date())
	return succeeded(case, "rolled to %s" % rolled.describe_date())


## Sleeping at 1 AM gets you 6:00 AM of the *following* day.
##
## 1:00 AM is the tail of day 9, so day 9's 6:00 AM has already gone by. There
## is no same-day morning left to wake into, and returning one would hand the
## player a second 6 AM on a day they already played.
func _t_morning_from_late_night(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 9, 1, 0)
	var morning := Clock.next_day_morning(time)
	if morning.hour != Clock.DAY_START_HOUR or morning.minute != 0:
		return fail(case, "expected 6:00 AM, got %s" % morning.describe_time())
	if morning.day_of_month != 10:
		return fail(case, "waking at 1 AM should land on day 10, got %d" % morning.day_of_month)
	if morning.passed_out:
		return fail(case, "a morning start should not be passed out")
	# Weather belongs to the day, so it must survive the rollover.
	morning.weather = WorldTime.Weather.SNOW
	var again := Clock.next_day_morning(morning)
	if again.weather != WorldTime.Weather.SNOW:
		return fail(case, "weather was lost across the rollover")
	return succeeded(case, "woke at 6:00 AM on %s" % morning.describe_date())


## Both day-ending paths are copy-then-mutate. If either edited in place, every
## caller holding a reference would see the day change underneath them — and the
## caller that just published `day_ended` would be reporting a day it had already
## mutated.
func _t_morning_is_pure(case: StringName) -> Dictionary:
	var time := WorldTime.new(2, WorldTime.Season.FALL, 14, 13, 37)
	var before := time.to_dict()
	Clock.next_day_morning(time)
	if time.to_dict() != before:
		return fail(case, "next_day_morning mutated its input: %s" % str(time.to_dict()))
	Clock.wake_after_collapse(time)
	if time.to_dict() != before:
		return fail(case, "wake_after_collapse mutated its input: %s" % str(time.to_dict()))
	Clock.advance(time, 10)
	if time.to_dict() != before:
		return fail(case, "advance mutated its input: %s" % str(time.to_dict()))
	return succeeded(case, "all three day-ending operations left the input at %s" % time.describe_date())


## Sleep ends the day, a collapse does not — the collapse already ended it.
##
## Getting this backwards is a day-loss bug in either direction: rolling twice on
## a collapse throws away a day, and not rolling on a sleep leaves the player
## stuck on the same date forever. Both are silent, which is why this is pinned.
func _t_sleep_vs_collapse(case: StringName) -> Dictionary:
	# Collapse path: `advance` already rolled, so waking must not roll again.
	var collapsed := Clock.advance(WorldTime.new(1, WorldTime.Season.SPRING, 4, 1, 55), 5)
	var after_collapse: WorldTime = collapsed["time"]
	if not collapsed["day_rolled"] or after_collapse.day_of_month != 5:
		return fail(case, "the collapse should have rolled to day 5, got %d" % after_collapse.day_of_month)
	var woken := Clock.wake_after_collapse(after_collapse)
	if woken.day_of_month != 5:
		return fail(case, "waking after a collapse must stay on day 5, got %d" % woken.day_of_month)
	if woken.passed_out or woken.hour != Clock.DAY_START_HOUR or woken.minute != 0:
		return fail(case, "waking should clear the collapse and land on 6:00 AM, got %s passed_out=%s" % [woken.describe_time(), woken.passed_out])

	# Sleep path: rolling is the whole point.
	var bed := WorldTime.new(1, WorldTime.Season.SPRING, 4, 21, 0)
	var morning := Clock.next_day_morning(bed)
	if morning.day_of_month != 5:
		return fail(case, "sleeping on the evening of day 4 should wake on day 5, got %d" % morning.day_of_month)
	if morning.hour != Clock.DAY_START_HOUR or morning.minute != 0:
		return fail(case, "expected 6:00 AM, got %s" % morning.describe_time())

	# A late sleep rolls too — 1 AM is the tail of day 4, and day 4's 6:00 AM
	# has already gone by, so there is no same-day morning left to wake into.
	var late := WorldTime.new(1, WorldTime.Season.SPRING, 4, 1, 0)
	var late_morning := Clock.next_day_morning(late)
	if late_morning.day_of_month != 5:
		return fail(case, "sleeping at 1:00 AM should wake on day 5, got %d" % late_morning.day_of_month)
	return succeeded(case, "collapse keeps its day, sleep rolls one")


## The clock must stop at 2 AM, not roll silently through empty days while the
## game waits for the player to acknowledge passing out.
func _t_service_freezes(case: StringName) -> Dictionary:
	var service := TimeService.new()
	var holder := Node.new()
	holder.add_child(service)
	root().add_child(holder)

	for _i: int in range(Clock.ticks_per_day() + 10):
		service.advance_tick()

	if not service.is_asleep():
		holder.free()
		return fail(case, "expected the service to have passed out by 2:00 AM")
	var frozen := service.time
	if frozen.hour != Clock.DAY_START_HOUR or frozen.minute != 0:
		holder.free()
		return fail(case, "expected the frozen clock at 6:00 AM, got %s" % frozen.describe_time())
	for _i: int in range(50):
		service.advance_tick()
	if service.time.day_of_month != frozen.day_of_month or service.time.hour != frozen.hour:
		holder.free()
		return fail(case, "the clock kept advancing after passing out: %s" % service.time.describe_date())
	if service.time.hour != Clock.DAY_START_HOUR:
		holder.free()
		return fail(case, "extra ticks moved the clock to %s" % service.time.describe_time())

	# Waking resumes the same morning rather than skipping to the next day.
	var woke_day := service.time.day_of_month
	service.wake_after_collapse()
	if service.time.day_of_month != woke_day:
		holder.free()
		return fail(case, "waking should stay on day %d, got %d" % [woke_day, service.time.day_of_month])
	if service.is_asleep():
		holder.free()
		return fail(case, "waking did not clear passed_out")
	service.advance_tick()
	if service.time.hour == Clock.DAY_START_HOUR and service.time.minute == 0:
		holder.free()
		return fail(case, "the clock did not resume after waking")

	holder.free()
	return succeeded(case, "frozen at 2 AM, resumes on the same morning")


## The day/night cycle must actually move as the clock moves, and it must react
## to the [signal EventBus.time_minute_changed] signal rather than only to direct
## calls — otherwise wiring it into the scene does nothing.
##
## Driven through a real `EventBus` signal emission, because the whole design is
## that lighting never holds a reference to the clock.
func _t_lighting_tracks_clock(case: StringName) -> Dictionary:
	var rig := _build_lighting_rig()
	if rig == null:
		return skip(case, "could not build the lighting rig")

	var cycle: DayNightCycle = rig["cycle"]
	var sun: DirectionalLight3D = rig["sun"]
	var bus := autoload(&"EventBus")
	if bus == null:
		rig["holder"].free()
		return skip(case, "EventBus autoload is not available in this run")

	var readings: Array[Dictionary] = []
	for hour: int in [6, 12, 18, 23, 0, 1, 2]:
		bus.time_minute_changed.emit(hour * Clock.MINUTES_PER_HOUR)
		readings.append({
			"hour": hour,
			"energy": sun.light_energy,
			"elevation": sun.rotation_degrees.x,
		})

	# The valley is brightest in the afternoon and darkest at 2 AM.
	var peak := 0.0
	var trough := INF
	for reading: Dictionary in readings:
		peak = maxf(peak, reading["energy"])
		trough = minf(trough, reading["energy"])
	if is_equal_approx(peak, trough):
		rig["holder"].free()
		return fail(case, "sun energy never changed across the day (always %s)" % str(peak))

	# Midnight must be darker than 3 PM. This is the assertion that would fail if
	# the gradient were keyed on display hours instead of absolute minutes: 12 AM
	# and 6 AM are six display hours apart but a full day apart in absolute terms.
	var midnight: float = readings[4]["energy"]
	var afternoon: float = readings[2]["energy"]
	if not midnight < afternoon:
		rig["holder"].free()
		return fail(case, "midnight energy %s should be below afternoon %s" % [str(midnight), str(afternoon)])

	# The sun should be below the horizon once it is properly dark.
	if not (readings[4]["elevation"] < 0.0):
		rig["holder"].free()
		return fail(case, "the sun should be below the horizon at midnight, got %s deg" % str(readings[4]["elevation"]))

	rig["holder"].free()
	return succeeded(case, "energy ranged %s..%s across the day" % [str(trough), str(peak)])


## 2:00 AM is the darkest point of the cycle, and the hours either side of it must
## not be darker. The 2:00-6:00 AM window is the player being asleep, so the light
## holds rather than continuing to fall or starting to rise.
func _t_lighting_darkest(case: StringName) -> Dictionary:
	var rig := _build_lighting_rig()
	if rig == null:
		return skip(case, "could not build the lighting rig")

	var cycle: DayNightCycle = rig["cycle"]
	var sun: DirectionalLight3D = rig["sun"]
	var bus := autoload(&"EventBus")
	if bus == null:
		rig["holder"].free()
		return skip(case, "EventBus autoload is not available in this run")

	# Drive to the collapse point *through the signal*, since that is the path the
	# game uses. Reading the energy before doing so would just measure the rig's
	# own 6:00 AM startup value.
	bus.time_minute_changed.emit(Clock.PASS_OUT_HOUR * Clock.MINUTES_PER_HOUR)
	var at_collapse := sun.light_energy
	cycle.apply_minute_of_day(Clock.PASS_OUT_HOUR * Clock.MINUTES_PER_HOUR)
	var at_collapse_direct := sun.light_energy
	if not is_equal_approx(at_collapse, at_collapse_direct):
		rig["holder"].free()
		return fail(case, "2:00 AM gave different results via the signal (%s) and directly (%s)" % [str(at_collapse), str(at_collapse_direct)])

	# Every asleep hour should match 2:00 AM, not drift.
	for hour: int in [3, 4, 5]:
		cycle.apply_minute_of_day(hour * Clock.MINUTES_PER_HOUR)
		if not is_equal_approx(sun.light_energy, at_collapse):
			rig["holder"].free()
			return fail(case, "%d:00 AM should hold the 2:00 AM light, got %s vs %s" % [hour, str(sun.light_energy), str(at_collapse)])

	# And no readable hour before the collapse may be darker than it.
	cycle.apply_minute_of_day(Clock.PASS_OUT_HOUR * Clock.MINUTES_PER_HOUR)
	var collapse_elevation := sun.rotation_degrees.x
	for hour: int in range(Clock.DAY_START_HOUR, 24):
		cycle.apply_minute_of_day(hour * Clock.MINUTES_PER_HOUR)
		if sun.light_energy < at_collapse - 0.001:
			rig["holder"].free()
			return fail(case, "%d:00 AM is darker (%s) than the collapse point (%s)" % [hour, str(sun.light_energy), str(at_collapse)])
	for hour: int in range(0, Clock.PASS_OUT_HOUR):
		cycle.apply_minute_of_day(hour * Clock.MINUTES_PER_HOUR)
		if sun.light_energy < at_collapse - 0.001:
			rig["holder"].free()
			return fail(case, "%d:00 AM is darker (%s) than the collapse point (%s)" % [hour, str(sun.light_energy), str(at_collapse)])

	if not (collapse_elevation < 0.0):
		rig["holder"].free()
		return fail(case, "the sun should be below the horizon at 2:00 AM, got %s deg" % str(collapse_elevation))

	rig["holder"].free()
	return succeeded(case, "2:00 AM is the floor at %s energy, %s deg" % [str(at_collapse), str(collapse_elevation)])


## The clock readout is the only way a player learns what time it is, so it has to
## read the real service through the real scene and render the real date.
func _t_clock_hud_reads_service(case: StringName) -> Dictionary:
	const HUD_SCENE := "res://scenes/ui/clock_hud.tscn"
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return fail(case, "Clock HUD scene missing at %s" % HUD_SCENE)

	var service := TimeService.new()
	service.running = false
	var hud := packed.instantiate() as CanvasLayer
	if hud == null:
		service.free()
		return fail(case, "Clock HUD root is not a CanvasLayer")

	var holder := Node.new()
	holder.add_child(service)
	# The service must exist before the HUD: the HUD finds it by walking the tree,
	# exactly as it does at runtime.
	root().add_child(holder)
	root().add_child(hud)

	var date_label := hud.get_node_or_null(^"Panel/Column/DateLabel") as Label
	var time_label := hud.get_node_or_null(^"Panel/Column/TimeLabel") as Label
	if date_label == null or time_label == null:
		hud.free()
		holder.free()
		return fail(case, "Clock HUD is missing its date or time label")

	# Start the day somewhere specific and assert both labels.
	service.set_time(WorldTime.new(2, WorldTime.Season.FALL, 17, 14, 30))
	var expected_date := service.time.describe_date()
	var expected_time := service.time.describe_time()
	if date_label.text != expected_date:
		hud.free()
		holder.free()
		return fail(case, "date label shows '%s', expected '%s'" % [date_label.text, expected_date])
	if time_label.text != expected_time:
		hud.free()
		holder.free()
		return fail(case, "time label shows '%s', expected '%s'" % [time_label.text, expected_time])

	# A tick must move the readout.
	service.advance_tick()
	if time_label.text == expected_time:
		hud.free()
		holder.free()
		return fail(case, "the time label did not update after a tick")
	# Read before freeing: the label belongs to the HUD, and the HUD is about to go.
	var final_time := time_label.text
	hud.free()
	holder.free()
	return succeeded(case, "readout tracked %s %s -> %s" % [expected_date, expected_time, final_time])


## Builds `Sun` + `Environment` + a `DayNightCycle` sibling, matching the node
## layout `world.tscn` ships, and adds the whole thing to the tree so `_ready`
## runs and the EventBus subscription is live.
func _build_lighting_rig() -> Dictionary:
	var holder := Node3D.new()
	holder.name = "LightingRig"
	root().add_child(holder)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	holder.add_child(sun)

	var environment := WorldEnvironment.new()
	environment.name = "Environment"
	var env := Environment.new()
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	sky.sky_material = material
	env.sky = sky
	environment.environment = env
	holder.add_child(environment)

	var cycle := DayNightCycle.new()
	cycle.name = "DayNightCycle"
	holder.add_child(cycle)

	return {"holder": holder, "cycle": cycle, "sun": sun, "environment": environment}


## Weather belongs to the day, not the clock. Rolling the calendar must not
## silently drop it, or a save taken at 1 AM loses the forecast.
func _t_weather_survives(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 5, 23, 50)
	time.weather = WorldTime.Weather.RAIN
	time.forecast = WorldTime.Weather.STORM
	var result := Clock.advance(time, 20)
	var rolled: WorldTime = result["time"]
	if rolled.weather != WorldTime.Weather.RAIN:
		return fail(case, "weather changed to %d across the rollover" % rolled.weather)
	if rolled.forecast != WorldTime.Weather.STORM:
		return fail(case, "forecast changed to %d across the rollover" % rolled.forecast)
	return succeeded(case, "weather and forecast preserved across the rollover")


## A 112-day year must not produce a day index outside 0..6, or the calendar
## widget shows a day that does not exist.
func _t_day_of_week_range(case: StringName) -> Dictionary:
	for day: int in range(Clock.DAYS_PER_YEAR):
		var time := WorldTime.new(1, WorldTime.Season.SPRING, day + 1, 6, 0)
		var index := Clock.day_of_week(time)
		if index < 0 or index > 6:
			return fail(case, "day %d produced weekday index %d" % [day + 1, index])
	# Day 1 of year 1 is the first day, index 0.
	var first := WorldTime.new(1, WorldTime.Season.SPRING, 1, 6, 0)
	if Clock.day_of_week(first) != 0:
		return fail(case, "day 1 of year 1 should be weekday 0, got %d" % Clock.day_of_week(first))
	return succeeded(case, "all %d days map to weekdays 0..6" % Clock.DAYS_PER_YEAR)


## A 28-day season is four whole weeks, so week 4 must never exist.
func _t_week_of(case: StringName) -> Dictionary:
	if Clock.week_of(1) != 0:
		return fail(case, "day 1 should be week 0, got %d" % Clock.week_of(1))
	if Clock.week_of(7) != 0:
		return fail(case, "day 7 should be week 0, got %d" % Clock.week_of(7))
	if Clock.week_of(8) != 1:
		return fail(case, "day 8 should be week 1, got %d" % Clock.week_of(8))
	if Clock.week_of(Clock.DAYS_PER_SEASON) != 3:
		return fail(case, "day %d should be week 3, got %d" % [Clock.DAYS_PER_SEASON, Clock.week_of(Clock.DAYS_PER_SEASON)])
	return succeeded(case, "weeks 0..3 across a %d-day season" % Clock.DAYS_PER_SEASON)


## Negative when the target is in the past — the shop needs to know whether a
## festival is coming or has been.
func _t_days_until(case: StringName) -> Dictionary:
	var today := WorldTime.new(1, WorldTime.Season.SPRING, 1, 6, 0)
	var later := WorldTime.new(1, WorldTime.Season.SPRING, 11, 6, 0)
	var earlier := WorldTime.new(1, WorldTime.Season.WINTER, 20, 6, 0)
	if Clock.days_until(today, later) != 10:
		return fail(case, "10 days forward should be 10, got %d" % Clock.days_until(today, later))
	if Clock.days_until(later, today) != -10:
		return fail(case, "10 days back should be -10, got %d" % Clock.days_until(later, today))
	if Clock.days_until(today, earlier) <= 0:
		return fail(case, "a date in the previous season should be negative, got %d" % Clock.days_until(today, earlier))
	# Year 1 Spring 1 to Year 2 Spring 1 is exactly one year of days. This is
	# the cross-year case a festival scheduler hits every spring.
	var next_spring := WorldTime.new(2, WorldTime.Season.SPRING, 1, 6, 0)
	if Clock.days_until(today, next_spring) != Clock.DAYS_PER_YEAR:
		return fail(case, "a full year should be %d days, got %d" % [Clock.DAYS_PER_YEAR, Clock.days_until(today, next_spring)])
	return succeeded(case, "signed day differences across season and year boundaries")


func _t_describe(case: StringName) -> Dictionary:
	var time := WorldTime.new(1, WorldTime.Season.SPRING, 4, 6, 0)
	if time.describe_date() != "Year 1 Spring 4":
		return fail(case, "expected 'Year 1 Spring 4', got '%s'" % time.describe_date())
	if time.describe_time() != "6:00 AM":
		return fail(case, "expected '6:00 AM', got '%s'" % time.describe_time())
	var midnight := WorldTime.new(1, WorldTime.Season.SPRING, 4, 0, 0)
	if midnight.describe_time() != "12:00 AM":
		return fail(case, "expected '12:00 AM' at midnight, got '%s'" % midnight.describe_time())
	var afternoon := WorldTime.new(1, WorldTime.Season.SPRING, 4, 14, 5)
	if afternoon.describe_time() != "2:05 PM":
		return fail(case, "expected '2:05 PM', got '%s'" % afternoon.describe_time())
	return succeeded(case, "dates and times read as sentences")


## Save and reload must not perturb the clock, or time drifts every session.
func _t_save_round_trip(case: StringName) -> Dictionary:
	var original := WorldTime.new(3, WorldTime.Season.FALL, 22, 19, 45)
	original.weather = WorldTime.Weather.WIND
	original.forecast = WorldTime.Weather.SNOW
	original.passed_out = true
	var restored := WorldTime.from_dict(original.to_dict())
	if restored.to_dict() != original.to_dict():
		return fail(case, "round trip changed the clock: %s -> %s" % [str(original.to_dict()), str(restored.to_dict())])
	return succeeded(case, "round trip preserved every field")


## A partial or garbage payload must never produce a clock stuck at hour 47.
##
## Each field is recovered independently: what is readable is kept, what is
## missing takes its default, what is out of range is clamped. Rejecting the
## whole payload would throw away a year of progress over one corrupt int.
func _t_corrupt_save(case: StringName) -> Dictionary:
	var from_empty := WorldTime.from_dict({})
	if from_empty.year != 1 or from_empty.day_of_month != 1 or from_empty.hour != Clock.DAY_START_HOUR:
		return fail(case, "empty payload should be a new game, got %s" % from_empty.describe_date())
	var from_partial := WorldTime.from_dict({"year": 2})
	if from_partial.year != 2 or from_partial.day_of_month != 1:
		return fail(case, "partial payload should default the rest, got %s" % from_partial.describe_date())
	var from_out_of_range := WorldTime.from_dict({
		"year": 1, "season": 9, "day_of_month": 99, "hour": 47, "minute": 90,
	})
	if from_out_of_range.season > 3:
		return fail(case, "season %d should be clamped" % from_out_of_range.season)
	if from_out_of_range.day_of_month > Clock.DAYS_PER_SEASON:
		return fail(case, "day %d should be clamped" % from_out_of_range.day_of_month)
	if from_out_of_range.hour > 23 or from_out_of_range.minute > 59:
		return fail(case, "hour/minute should be clamped, got %d:%d" % [from_out_of_range.hour, from_out_of_range.minute])
	return succeeded(case, "empty, partial and out-of-range payloads all load safely")


## `posmod` vs `clamp` is not a style preference here. A `season` of `-1` read
## with a modulo-style wrap lands on Winter 3, which indexes past the end of
## every season-name array. Clamping to 0 loads Spring instead.
func _t_negative_values(case: StringName) -> Dictionary:
	var restored := WorldTime.from_dict({
		"year": -3, "season": -1, "day_of_month": -7, "hour": -5, "minute": -30,
	})
	if restored.year < 1 or restored.day_of_month < 1 or restored.hour < 0 or restored.minute < 0:
		return fail(case, "negative values leaked through: %s" % str(restored.to_dict()))
	if restored.season != WorldTime.Season.SPRING:
		return fail(case, "season -1 should load as Spring, got %d" % restored.season)
	if restored.season < 0 or restored.season >= Clock.SEASONS_PER_YEAR:
		return fail(case, "season %d is out of range" % restored.season)
	if Clock.season_name(restored.season) != "Spring":
		return fail(case, "season name for %d did not resolve" % restored.season)
	if restored.weather < 0 or restored.forecast < 0:
		return fail(case, "negative weather leaked through: %s" % str(restored.to_dict()))
	return succeeded(case, "negatives clamp to the start of the calendar, not the end")


## The service's whole job is turning clock transitions into bus signals, so
## that nothing else has to know the clock exists. Asserted through the real
## autoload rather than a mock, because a mock proves nothing about the wiring.
func _t_service_signals(case: StringName) -> Dictionary:
	var bus := autoload(&"EventBus")
	if bus == null:
		return skip(case, "EventBus autoload is not available in this run")

	var seen := {"minute": 0, "hour": 0, "day": 0}
	var on_minute := func(minute_of_day: int) -> void: seen["minute"] += 1
	var on_hour := func(hour: int) -> void: seen["hour"] += 1
	var on_day := func(day: int) -> void: seen["day"] += 1
	bus.time_minute_changed.connect(on_minute)
	bus.time_hour_changed.connect(on_hour)
	bus.day_started.connect(on_day)

	var service := TimeService.new()
	service.seconds_per_day = 60.0
	var holder := Node.new()
	holder.name = "TimeServiceHolder"
	holder.add_child(service)
	root().add_child(holder)

	# Enough ticks to cross at least one hour boundary and reach the collapse.
	for _i: int in range(Clock.ticks_per_day()):
		service.advance_tick()

	bus.time_minute_changed.disconnect(on_minute)
	bus.time_hour_changed.disconnect(on_hour)
	bus.day_started.disconnect(on_day)

	if seen["minute"] < 1:
		return fail(case, "no time_minute_changed signals were published")
	if seen["hour"] < 1:
		return fail(case, "no time_hour_changed signals were published")
	if seen["day"] < 1:
		holder.free()
		return fail(case, "no day_started signals were published")
	# The service is day 2 at 6:00 AM and asleep, having collapsed at 2:00 AM.
	if service.time.day_of_month != 2:
		holder.free()
		return fail(case, "expected the service to roll to day 2, got %d" % service.time.day_of_month)
	if not service.is_asleep():
		holder.free()
		return fail(case, "expected the service to have passed out at 2:00 AM")

	# Sleeping is what ends the day for real, and it is a separate signal pair.
	var slept := service.sleep_until_morning()
	if slept.day_of_month != 3 or slept.passed_out:
		holder.free()
		return fail(case, "sleeping should wake on day 3, got %s" % slept.describe_date())
	if seen["day"] < 2:
		holder.free()
		return fail(case, "sleeping should publish a second day_started, saw %d" % seen["day"])

	holder.free()
	return succeeded(case, "%d minute, %d hour, %d day signals published" % [seen["minute"], seen["hour"], seen["day"]])


## The weather calendar is derived, so the whole case is that the same date gives the
## same sky no matter who asks.
##
## Four different routes, because each one fails differently: the calendar on its own, the
## forecast path a save load takes, a fresh service booted to the same date, and a service
## jumped there with `set_time`. A rolled generator passes the first and fails the rest.
func _t_weather_is_derived(case: StringName) -> Dictionary:
	var date := WorldTime.new(2, WorldTime.Season.FALL, 17, 13, 20)
	var from_calendar := WeatherCalendar.weather_for(date)
	for other: WorldTime in [
		date, date.copy(), WorldTime.from_dict(date.to_dict()),
	]:
		if WeatherCalendar.weather_for(other) != from_calendar:
			return fail(case, "%s gave %s, expected %s" % [
				other.describe_date(), WorldTime.weather_name(WeatherCalendar.weather_for(other)),
				WorldTime.weather_name(from_calendar),
			])

	var booted := TimeService.new()
	booted.set_time(date)
	if booted.get_weather() != from_calendar:
		return fail(case, "a service set to the date reported %s" % WorldTime.weather_name(booted.get_weather()))
	if booted.get_forecast() != WeatherCalendar.forecast_for(date):
		return fail(case, "the forecast disagrees with the calendar")
	booted.free()
	return succeeded(case, "%s is %s however you reach it" % [
		date.describe_date(), WorldTime.weather_name(from_calendar),
	])


## The table could be implemented and still produce one weather forever, if the hash
## only ever landed in one bucket. A whole year has to contain more than one answer.
func _t_weather_varies(case: StringName) -> Dictionary:
	var seen := {}
	for index: int in range(Clock.DAYS_PER_YEAR):
		seen[WeatherCalendar.weather_for_index(index)] = true
	if seen.size() < 3:
		return fail(case, "a whole year produced %d kinds of weather: %s" % [
			seen.size(), str(seen.keys()),
		])
	return succeeded(case, "a year contains %d kinds of weather" % seen.size())


## Snow has a weight of 0 in every season but winter. That is the entire point of the
## table, and a hash bug would show it as snow in July.
func _t_snow_is_winter_only(case: StringName) -> Dictionary:
	var offenders: Array[String] = []
	for index: int in range(Clock.DAYS_PER_YEAR):
		var season := posmod(floori(float(index) / Clock.DAYS_PER_SEASON), Clock.SEASONS_PER_YEAR)
		if WeatherCalendar.weather_for_index(index) == WorldTime.Weather.SNOW and season != WorldTime.Season.WINTER:
			offenders.append("%d (season %d)" % [index, season])
	if not offenders.is_empty():
		return fail(case, "snow fell outside winter on %d days, first at day %s" % [
			offenders.size(), offenders[0],
		])
	return succeeded(case, "snow only ever fell in winter across %d days" % Clock.DAYS_PER_YEAR)


## The realised distribution has to follow the weights, or the table is decorative.
##
## Sampled over several years rather than one season, because the assertion is about
## proportions and 28 days is not enough of a sample to say anything about a weight of
## 1 in 10 — a single unlucky day moves that share by four points, which is noise, not
## a bug. The band is therefore proportional and generous enough for hash noise, and
## tight enough to catch the failure that matters: a mis-indexed row, which would send
## snow to spring or put winter's zero on a season that can have rain.
##
## The exact-zero half is asserted per season with no tolerance at all, because a zero
## weight must never be produced whatever the hash does.
func _t_weather_distribution(case: StringName) -> Dictionary:
	var years := 8
	var per_season := Clock.DAYS_PER_SEASON * years
	var rows: Array = WeatherCalendar.WEIGHTS
	for season: int in range(Clock.SEASONS_PER_YEAR):
		var counts := {}
		for year: int in range(years):
			for offset: int in range(Clock.DAYS_PER_SEASON):
				var index := year * Clock.DAYS_PER_YEAR + season * Clock.DAYS_PER_SEASON + offset
				counts[WeatherCalendar.weather_for_index(index)] = \
					int(counts.get(WeatherCalendar.weather_for_index(index), 0)) + 1
		for weather: int in rows[season].size():
			var weight := int(rows[season][weather])
			if weight <= 0:
				continue
			var expected := float(weight) / float(_row_total(rows[season]))
			var share := float(int(counts.get(weather, 0))) / float(per_season)
			if absf(share - expected) > expected * 0.35:
				return fail(case, "%s: %s came up %.1f%% of %d days, expected %.1f%%" % [
					Clock.season_name(season), WorldTime.weather_name(weather),
					share * 100.0, per_season, expected * 100.0,
				])
	return succeeded(case, "the realised weather follows the weights across %d years" % years)


## A weight row's total.
func _row_total(row: Array) -> int:
	var out := 0
	for w: Variant in row:
		out += maxi(int(w), 0)
	return out


## The rain hook in `farm_service.gd` has been dead since the time group left it open —
## nothing ever emitted `weather_changed`, so a rainy day never reached it. This asserts
## it now runs, which is the whole reason the daily roll was pulled forward.
func _t_rain_waters(case: StringName) -> Dictionary:
	var bus := autoload(&"EventBus")
	if bus == null:
		return skip(case, "EventBus autoload is not available in this run")

	var service: Object = load("res://scripts/farming/farm_service.gd").new()
	var grid := FarmGrid.new()
	grid.columns = 4
	grid.rows = 4
	var rig := Node3D.new()
	root().add_child(rig)
	rig.add_child(grid)
	rig.add_child(service)
	# Through the real registration method, not by poking the exported field: the grid is
	# built inside the world scene and `main.gd` hands it over, so a case that assigns the
	# field directly would pass while the shipped wiring stayed broken.
	service.call("attach_grid", grid)

	var tile := grid.tile_at(grid.global_position)
	if tile == null:
		rig.free()
		return fail(case, "the grid has no centre tile to till")
	if not tile.till():
		rig.free()
		return fail(case, "the centre tile refused to be tilled")

	var wetted := {"count": 0, "tiles": 0}
	var on_watered := func(_index: Vector2i, tiles: int) -> void:
		wetted["count"] = int(wetted["count"]) + 1
		wetted["tiles"] = int(wetted["tiles"]) + tiles
	bus.soil_watered.connect(on_watered)

	# Call the private handler the way the bus would, so the case is about the rule
	# rather than about how the signal gets here.
	service.call("_on_weather_changed", WorldTime.Weather.RAIN)
	var after_rain := int(wetted["tiles"])
	# Read the tile before the rig goes: the tile is a child of it, so touching it
	# afterwards is use-after-free and reports as a script error rather than a failure.
	var watered_by_rain := tile.is_watered

	# A clear sky must not water anything, and a snow day must not either — carrying a
	# can on a snow day is the whole reason the hook only counts rain and storm.
	service.call("_on_weather_changed", WorldTime.Weather.SUN)
	var after_sun := int(wetted["tiles"])
	service.call("_on_weather_changed", WorldTime.Weather.SNOW)
	var after_snow := int(wetted["tiles"])

	bus.soil_watered.disconnect(on_watered)
	rig.free()

	if after_rain < 1 or not watered_by_rain:
		return fail(case, "rain published %d tiles and left the soil watered=%s" % [
			after_rain, str(watered_by_rain),
		])
	if after_sun != after_rain:
		return fail(case, "a sunny day published %d more tiles" % (after_sun - after_rain))
	if after_snow != after_rain:
		return fail(case, "a snowy day published %d more tiles" % (after_snow - after_rain))
	return succeeded(case, "rain watered %d tiles; sun and snow watered none" % after_rain)


## The signal has to fire on the boundary, or nothing listening can react.
func _t_weather_signal(case: StringName) -> Dictionary:
	var bus := autoload(&"EventBus")
	if bus == null:
		return skip(case, "EventBus autoload is not available in this run")

	var seen: Array[int] = []
	var on_weather := func(weather: int) -> void: seen.append(weather)
	bus.weather_changed.connect(on_weather)

	var service := TimeService.new()
	service.seconds_per_day = 60.0
	var holder := Node.new()
	holder.add_child(service)
	root().add_child(holder)

	# Enough ticks to cross a day boundary or two.
	for _i: int in range(Clock.ticks_per_day()):
		service.advance_tick()
	bus.weather_changed.disconnect(on_weather)
	holder.free()

	if seen.is_empty():
		return fail(case, "the day rolled but weather_changed never fired")
	for weather: int in seen:
		if weather < 0 or weather >= WorldTime.WEATHER_NAMES.size():
			return fail(case, "weather_changed published %d" % weather)
	return succeeded(case, "%d weather changes announced over a full day" % seen.size())


## A save written before weather existed stores Sunny for every day, because nothing
## rolled it. Loading it must still produce the right sky for that date, or the first
## thing a returning player sees is a schedule that disagrees with yesterday.
func _t_old_save_gets_weather(case: StringName) -> Dictionary:
	var legacy := WorldTime.new(1, WorldTime.Season.SPRING, 9, 10, 0)
	legacy.weather = WorldTime.Weather.SUN
	legacy.forecast = WorldTime.Weather.SUN

	var service := TimeService.new()
	service.set_time(WorldTime.from_dict(legacy.to_dict()))
	var got := service.get_weather()
	var expected := WeatherCalendar.weather_for(legacy)
	service.free()
	if got != expected:
		return fail(case, "a save storing Sunny loaded as %s, expected %s" % [
			WorldTime.weather_name(got), WorldTime.weather_name(expected),
		])
	return succeeded(case, "a save with Sunny stored it loaded as %s" % WorldTime.weather_name(got))
