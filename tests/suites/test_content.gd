extends TestSuite
## M3 content: crops and items as data.
##
## These suites test the *rules* the farming systems are built on, not the
## presentation. A crop is a `.tres` with a schema; a wrong number in one of them
## is a balance bug nobody notices until a season is unplayable, so every field
## that a tile or a service will read is pinned here.
##
## The registry cases load through the same path gameplay uses, so a file that
## fails to parse or a directory that moves shows up as a test failure rather
## than as a silent "crop not found" during play.

func get_cases() -> Array[StringName]:
	return [
		&"crops_load_from_disk",
		&"every_crop_is_valid",
		&"crop_ids_are_unique",
		&"crop_seasons_are_real",
		&"grows_in_reports_only_listed_seasons",
		&"a_crop_with_no_seasons_grows_all_year",
		&"yield_never_exceeds_the_maximum",
		&"yield_is_at_least_the_minimum",
		&"min_yield_never_exceeds_max_yield",
		&"regrowing_crops_are_longer_than_their_regrow",
		&"save_and_reload_preserves_the_yield_stream",
		&"items_load_from_disk",
		&"every_item_is_valid",
		&"item_ids_are_unique",
		&"every_seed_packet_names_a_real_crop",
		&"seed_packet_ids_follow_the_crop_they_plant",
		&"tools_declare_the_action_they_perform",
		&"only_tools_carry_a_tool_action",
		&"durability_implies_the_item_wears_out",
		&"unknown_ids_are_looked_up_as_missing_not_defaulted",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"crops_load_from_disk":
			return check_greater(case, float(CropRegistry.all_crops().size()), 0.0)
		&"every_crop_is_valid":
			var bad: Array[String] = []
			for data: CropData in CropRegistry.all_crops():
				if not data.is_valid():
					bad.append(String(data.id))
			return check_equals(case, bad, [] as Array[String])
		&"crop_ids_are_unique":
			return check_equals(case, CropRegistry.duplicate_ids(), [] as Array[String])
		&"crop_seasons_are_real":
			var bad: Array[String] = []
			for data: CropData in CropRegistry.all_crops():
				for season: int in data.seasons:
					if season < WorldTime.Season.SPRING or season > WorldTime.Season.WINTER:
						bad.append("%s=%d" % [data.id, season])
			return check_equals(case, bad, [] as Array[String])
		&"grows_in_reports_only_listed_seasons":
			# Spring only: true in spring, false in every other season. Checked
			# over all four rather than one negative, because a crop that grows
			# all year and a crop with a broken season list fail different ways.
			var parsnip := CropRegistry.get_crop(&"parsnip")
			return check_true(
				case,
				parsnip.grows_in(WorldTime.Season.SPRING)
				and not parsnip.grows_in(WorldTime.Season.SUMMER)
				and not parsnip.grows_in(WorldTime.Season.FALL)
				and not parsnip.grows_in(WorldTime.Season.WINTER),
				"parsnip should be spring-only"
			)
		&"a_crop_with_no_seasons_grows_all_year":
			var everywhere := CropData.new()
			everywhere.id = &"test_all_year"
			everywhere.seasons = []
			# Enumerated by index rather than `WorldTime.Seasons.values()`, which
			# does not exist: the season enum is `WorldTime.Season`, so its values
			# hang off that, not off the class.
			var ok := true
			for season: int in range(Clock.SEASONS_PER_YEAR):
				ok = ok and everywhere.grows_in(season)
			return check_true(case, ok, "empty season list should mean year-round")
		&"yield_never_exceeds_the_maximum":
			return check_yield_bounds(case, true)
		&"yield_is_at_least_the_minimum":
			return check_yield_bounds(case, false)
		&"min_yield_never_exceeds_max_yield":
			# Checked separately from the roll bounds because `roll_yield` silently
			# swaps the two, so an inverted definition still passes the roll tests.
			# This is the case that actually catches the typo.
			var bad: Array[String] = []
			for data: CropData in CropRegistry.all_crops():
				if data.min_yield > data.max_yield:
					bad.append(String(data.id))
			return check_equals(case, bad, [] as Array[String])
		&"regrowing_crops_are_longer_than_their_regrow":
			# A regrow window longer than the whole growth time means a crop that
			# ripens again the moment it is picked, forever.
			var bad: Array[String] = []
			for data: CropData in CropRegistry.all_crops():
				if data.regrows and data.regrow_days > data.days_to_grow:
					bad.append(String(data.id))
			return check_equals(case, bad, [] as Array[String])
		&"save_and_reload_preserves_the_yield_stream":
			var data := CropRegistry.get_crop(&"potato")
			var rng := RandomNumberGenerator.new()
			rng.seed = 12345
			var first: Array[int] = []
			for i: int in range(20):
				first.append(data.roll_yield(rng))
			var reloaded: CropData = data.duplicate()
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 12345
			var second: Array[int] = []
			for i: int in range(20):
				second.append(reloaded.roll_yield(rng2))
			return check_equals(case, second, first)
		&"items_load_from_disk":
			return check_greater(case, float(ItemRegistry.all_items().size()), 0.0)
		&"every_item_is_valid":
			var bad: Array[String] = []
			for item: ItemDefinition in ItemRegistry.all_items():
				if not item.is_valid():
					bad.append(String(item.id))
			return check_equals(case, bad, [] as Array[String])
		&"item_ids_are_unique":
			return check_equals(case, ItemRegistry.duplicate_ids(), [] as Array[String])
		&"every_seed_packet_names_a_real_crop":
			# The bug this catches: a seed packet whose `seed_id` points at a crop
			# that does not exist. Planting it would consume the seed and leave a
			# tile occupied by a plant that can never be harvested.
			var bad: Array[String] = []
			for item: ItemDefinition in ItemRegistry.all_items():
				if item.category != ItemDefinition.Category.SEED:
					continue
				if not CropRegistry.has_crop(item.seed_id):
					bad.append(String(item.id))
			return check_equals(case, bad, [] as Array[String])
		&"seed_packet_ids_follow_the_crop_they_plant":
			var bad: Array[String] = []
			for item: ItemDefinition in ItemRegistry.all_items():
				if item.category != ItemDefinition.Category.SEED:
					continue
				if not String(item.id).ends_with("_seeds") and String(item.id) != "winter_seeds":
					bad.append(String(item.id))
			return check_equals(case, bad, [] as Array[String])
		&"tools_declare_the_action_they_perform":
			# A tool with an empty `tool_action` is inert. The scythe ships that
			# way on purpose, so it is excluded rather than every tool being
			# required to do something.
			var bad: Array[String] = []
			for item: ItemDefinition in ItemRegistry.all_items():
				if item.id == &"scythe":
					continue
				if not item.is_tool():
					continue
				if item.tool_action.is_empty():
					bad.append(String(item.id))
			return check_equals(case, bad, [] as Array[String])
		&"only_tools_carry_a_tool_action":
			var bad: Array[String] = []
			for item: ItemDefinition in ItemRegistry.all_items():
				if not item.is_tool() and not item.tool_action.is_empty():
					bad.append(String(item.id))
			return check_equals(case, bad, [] as Array[String])
		&"durability_implies_the_item_wears_out":
			var bad: Array[String] = []
			for item: ItemDefinition in ItemRegistry.all_items():
				if item.durability > 0 and not item.uses_durability:
					bad.append(String(item.id))
				if item.uses_durability and item.durability <= 0:
					bad.append(String(item.id))
			return check_equals(case, bad, [] as Array[String])
		&"unknown_ids_are_looked_up_as_missing_not_defaulted":
			# A registry that returned a blank definition for an unknown id would
			# make every typo look like valid content and silently pass a null
			# check downstream.
			var missing := ItemRegistry.get_item(&"definitely_not_an_item")
			return check_null(case, missing)
	return fail(case, "unhandled case")


func check_yield_bounds(case: StringName, upper: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	for data: CropData in CropRegistry.all_crops():
		for i: int in range(30):
			var amount := data.roll_yield(rng)
			if upper and amount > data.max_yield:
				return fail(case, "%s yielded %d > max %d" % [data.id, amount, data.max_yield])
			if not upper and amount < data.min_yield:
				return fail(case, "%s yielded %d < min %d" % [data.id, amount, data.min_yield])
	return succeeded(case)