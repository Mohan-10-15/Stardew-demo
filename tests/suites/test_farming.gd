extends TestSuite
## M3 farming: the plot, the tiles, and the loop of till / plant / water / grow /
## harvest.
##
## Most cases here drive [SoilTile] directly, because the tile is where the rules
## live. The cases that matter most, though, are the last three: they build the
## *real* generated world, walk the player onto the plot, aim the real camera and
## press the real interact key. A tile that passes every unit test but cannot be
## aimed at is not a farm, and the farm is the whole point.
##
## ## Async on purpose
##
## Every case goes through `_run_async` and awaits physics frames, because the
## interaction probe casts its ray in `_physics_process`. A synchronous case
## would assert against a focus that has not been computed yet, and would pass
## for the wrong reason.

var _rig: Node3D = null


func get_cases() -> Array[StringName]:
	return [
		# --- grid geometry ---------------------------------------------------
		&"a_new_grid_has_one_tile_per_cell",
		&"the_grid_is_centred_on_its_own_position",
		&"tile_to_world_round_trips_through_world_to_tile",
		&"world_to_tile_puts_a_seam_on_the_boundary",
		&"tile_at_returns_null_off_the_plot",
		&"tiles_in_radius_is_ordered_nearest_first",
		&"the_farm_plot_fits_inside_the_fence",
		# --- tile rules ------------------------------------------------------
		&"tilling_is_idempotent",
		&"watering_untilled_soil_is_refused",
		&"watering_twice_is_refused",
		&"planting_untilled_soil_is_refused",
		&"planting_an_unknown_crop_is_refused",
		&"planting_twice_on_one_tile_is_refused",
		&"an_unwatered_crop_does_not_grow",
		&"a_watered_crop_grows_one_day",
		&"a_crop_is_ripe_exactly_on_its_last_day",
		&"harvesting_early_is_refused_and_names_the_reason",
		&"harvesting_an_empty_tile_is_refused",
		&"harvesting_a_one_shot_crop_clears_the_tile",
		&"a_regrowing_crop_stays_and_resets_its_clock",
		&"a_regrowing_crop_needs_exactly_its_regrow_window",
		&"an_unknown_crop_on_a_tile_is_cleared_not_left_stuck",
		&"a_tile_save_round_trips",
		&"a_grid_save_round_trips",
		# --- inventory -------------------------------------------------------
		&"a_new_bag_is_empty",
		&"adding_merges_into_a_matching_stack",
		&"adding_splits_across_free_slots",
		&"adding_is_all_or_nothing",
		&"removing_spends_lowest_quality_first",
		&"removal_nulls_the_slot_it_empties",
		&"different_qualities_never_merge",
		&"moving_between_slots_swaps_or_merges",
		&"shrinking_refuses_when_items_would_be_lost",
		# --- hotbar ----------------------------------------------------------
		&"the_hotbar_wraps_in_both_directions",
		&"the_hotbar_shows_nine_slots",
		&"the_held_tool_comes_from_the_held_item",
		&"the_held_seed_comes_from_the_held_item",
		# --- the real thing --------------------------------------------------
		&"the_generated_world_contains_a_farm_grid",
		&"every_farm_tile_is_aimable_on_foot",
		&"tilling_through_the_real_interact_key_works",
		&"planting_and_harvesting_through_the_real_interact_key_works",
	]


func is_async() -> bool:
	return true


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"a_new_grid_has_one_tile_per_cell":
			var grid := _make_grid(4, 3)
			return check_equals(case, grid.tile_count(), 12)
		&"the_grid_is_centred_on_its_own_position":
			var grid := _make_grid(7, 5)
			var centre: Vector3 = grid.global_position
			var sum := Vector3.ZERO
			for tile: SoilTile in grid.get_tiles():
				sum += tile.global_position
			var mean := sum / float(grid.tile_count())
			return check_in_range(case, mean.distance_to(centre), 0.0, 0.001)
		&"tile_to_world_round_trips_through_world_to_tile":
			var grid := _make_grid(7, 5)
			var bad: Array[String] = []
			for tile: SoilTile in grid.get_tiles():
				var back := grid.world_to_tile(grid.tile_to_world(tile.tile_index))
				if back != tile.tile_index:
					bad.append("%s -> %s" % [str(tile.tile_index), str(back)])
			return check_equals(case, bad, [] as Array[String])
		&"world_to_tile_puts_a_seam_on_the_boundary":
			# The seam between two tiles belongs to exactly one of them. Flooring
			# rather than rounding is what guarantees that; rounding would send
			# the boundary to a neighbour depending on which side you stood.
			var grid := _make_grid(2, 1)
			var seam: Vector3 = grid.tile_to_world(Vector2i(0, 0)) + Vector3(grid.tile_size, 0, 0)
			return check_equals(case, grid.world_to_tile(seam), Vector2i(1, 0))
		&"tile_at_returns_null_off_the_plot":
			var grid := _make_grid(3, 3)
			var inside := grid.tile_at(grid.global_position)
			var outside := grid.tile_at(grid.global_position + Vector3(500, 0, 0))
			return check_true(
				case, inside != null and outside == null,
				"inside=%s outside=%s" % [inside, outside]
			)
		&"tiles_in_radius_is_ordered_nearest_first":
			# Measured against the centre tile's *world position*, which is the
			# same point the grid sorts by — comparing against `grid.global_position`
			# instead looks equivalent on a centred grid but is a different
			# assertion, and would pass for the wrong reason if the grid were ever
			# hung off its first tile again.
			var grid := _make_grid(5, 5)
			var found := grid.tiles_in_radius(grid.global_position, 3.0)
			if found.size() < 2:
				return fail(case, "expected several tiles, got %d" % found.size())
			var centre: Vector3 = found[0].global_position
			var last := INF
			var order: Array[String] = []
			for tile: SoilTile in found:
				var d := tile.global_position.distance_to(centre)
				order.append("%.2f" % d)
				if d > last + 0.001:
					return fail(case, "distances went backwards: %s" % ", ".join(order))
				last = d
			return succeeded(case, "nearest-first over %d tiles" % found.size())
		&"the_farm_plot_fits_inside_the_fence":
			# The soil plane is 22x16 and the fence is 11m either side of the farm
			# centre. A 7x5 plot at 2m is 14x10, which fits; a grid that grew past
			# that would put tillable tiles through the fence.
			var grid := _make_grid(7, 5)
			var extents: Vector2 = grid.plot_extents()
			return check_true(
				case,
				extents.x <= 22.0 and extents.y <= 16.0,
				"plot %s exceeds the 22x16 soil plane" % str(extents)
			)
		&"tilling_is_idempotent":
			var tile := _make_tile(0, 0)
			var first := tile.till()
			var second := tile.till()
			return check_true(
				case, first and not second,
				"first=%s second=%s" % [first, second]
			)
		&"watering_untilled_soil_is_refused":
			var tile := _make_tile(0, 0)
			return check_false(case, tile.water())
		&"watering_twice_is_refused":
			var tile := _make_tile(0, 0)
			tile.till()
			return check_true(case, tile.water() and not tile.water())
		&"planting_untilled_soil_is_refused":
			var tile := _make_tile(0, 0)
			return check_false(case, tile.plant(&"parsnip"))
		&"planting_an_unknown_crop_is_refused":
			var tile := _make_tile(0, 0)
			tile.till()
			return check_false(case, tile.plant(&"not_a_crop"))
		&"planting_twice_on_one_tile_is_refused":
			var tile := _make_tile(0, 0)
			tile.till()
			tile.plant(&"parsnip")
			return check_false(case, tile.plant(&"potato"))
		&"an_unwatered_crop_does_not_grow":
			# The single most important farming rule, and the one this suite exists
			# to protect: no water means no growth, ever. Two nights in a row,
			# because the failure mode is a crop that advances one night and then
			# mysteriously stalls, which a one-night check would not catch.
			var tile := _make_tile(0, 0)
			tile.till()
			tile.plant(&"parsnip")
			tile.on_new_day()
			var after_one: int = tile.growth_days
			tile.on_new_day()
			return check_equals(
				case, [after_one, tile.growth_days], [0, 0] as Array[int]
			)
		&"a_watered_crop_grows_one_day":
			var tile := _make_tile(0, 0)
			tile.till()
			tile.plant(&"parsnip")
			tile.water()
			tile.on_new_day()
			return check_equals(case, tile.growth_days, 1)
		&"a_crop_is_ripe_exactly_on_its_last_day":
			var data := CropRegistry.get_crop(&"parsnip")
			var tile := _make_tile(0, 0)
			tile.till()
			tile.plant(&"parsnip")
			tile.growth_days = data.days_to_grow - 1
			var early := tile.is_ripe()
			tile.growth_days = data.days_to_grow
			return check_true(
				case, not early and tile.is_ripe(),
				"early=%s ripe=%s days=%d" % [early, tile.is_ripe(), data.days_to_grow]
			)
		&"harvesting_early_is_refused_and_names_the_reason":
			var tile := _make_tile(0, 0)
			tile.till()
			tile.plant(&"parsnip")
			var result := tile.harvest()
			return check_equals(case, String(str(result.get("reason", ""))), "not_ripe")
		&"harvesting_an_empty_tile_is_refused":
			var tile := _make_tile(0, 0)
			tile.till()
			return check_equals(case, String(str(tile.harvest().get("reason", ""))), "empty")
		&"harvesting_a_one_shot_crop_clears_the_tile":
			var tile := _ripe_tile(&"parsnip")
			var result := tile.harvest()
			return check_true(
				case, bool(result["ok"]) and tile.crop_id.is_empty(),
				"ok=%s crop=%s" % [result["ok"], tile.crop_id]
			)
		&"a_regrowing_crop_stays_and_resets_its_clock":
			var data := CropRegistry.get_crop(&"tomato")
			if data == null or not data.regrows:
				return skip(case, "no regrowing crop in content")
			var tile := _ripe_tile(&"tomato")
			var result := tile.harvest()
			return check_true(
				case,
				bool(result["ok"])
					and tile.crop_id == &"tomato"
					and not tile.is_ripe()
					and tile.growth_days == data.days_to_grow - data.regrow_days,
				"crop=%s ripe=%s days=%d" % [tile.crop_id, tile.is_ripe(), tile.growth_days]
			)
		&"a_regrowing_crop_needs_exactly_its_regrow_window":
			var data := CropRegistry.get_crop(&"tomato")
			if data == null or not data.regrows:
				return skip(case, "no regrowing crop in content")
			var tile := _ripe_tile(&"tomato")
			tile.harvest()
			# Advance one short of the window, water, and it must still refuse.
			for i: int in range(maxi(data.regrow_days - 1, 0)):
				tile.water()
				tile.on_new_day()
			var early: bool = tile.is_ripe()
			tile.water()
			tile.on_new_day()
			return check_true(
				case, not early and tile.is_ripe(),
				"ripe early=%s, ripe now=%s" % [early, tile.is_ripe()]
			)
		&"an_unknown_crop_on_a_tile_is_cleared_not_left_stuck":
			var tile := _ripe_tile(&"parsnip")
			# Forge an id no registry can answer, as a save from a newer build would.
			tile.crop_id = &"crop_from_the_future"
			var result := tile.harvest()
			return check_true(
				case,
				not bool(result["ok"])
					and String(str(result["reason"])) == "unknown_crop"
					and tile.crop_id.is_empty(),
				"ok=%s reason=%s crop=%s" % [
					result["ok"], result["reason"], tile.crop_id,
				]
			)
		&"a_tile_save_round_trips":
			var tile := _make_tile(2, 3)
			tile.till()
			tile.plant(&"potato")
			tile.water()
			tile.growth_days = 2
			var clone := SoilTile.from_dict(tile.to_dict())
			return check_equals(
				case, clone.to_dict(), tile.to_dict()
			)
		&"a_grid_save_round_trips":
			var grid := _make_grid(3, 2)
			for i: int in range(3):
				grid.get_tile(Vector2i(i, 0)).till()
				grid.get_tile(Vector2i(i, 0)).plant(&"parsnip")
			grid.get_tile(Vector2i(1, 1)).water()
			var payload := grid.to_dict()
			var other := _make_grid(3, 2)
			other.from_dict(payload)
			return check_equals(case, other.to_dict(), payload)
		&"a_new_bag_is_empty":
			return check_true(case, Inventory.new(8).is_empty())
		&"adding_merges_into_a_matching_stack":
			var bag := Inventory.new(8)
			bag.add(&"wood", 5)
			bag.add(&"wood", 4)
			return check_equals(case, bag.count(&"wood"), 9)
		&"adding_splits_across_free_slots":
			# 250 stone cannot fit in three 99-max stacks' worth of *room* if the
			# slots already hold other things, but from empty it needs 99 + 99 + 52,
			# i.e. all three slots and the bag legitimately full afterwards.
			var bag := Inventory.new(3)
			var added := bag.add(&"stone", 250)
			return check_true(
				case,
				added == 250 and bag.count(&"stone") == 250 and bag.is_full(),
				"added=%d count=%d full=%s" % [added, bag.count(&"stone"), bag.is_full()]
			)
		&"adding_is_all_or_nothing":
			var bag := Inventory.new(1)
			var added := bag.add(&"stone", 500)
			return check_equals(case, added, 0)
		&"removing_spends_lowest_quality_first":
			# The rule from `docs/SALVAGED_DESIGN.md`: spending a silver parsnip
			# while a normal one is in the bag destroys value.
			var bag := Inventory.new(8)
			bag.add(&"parsnip", 1, Inventory.Quality.SILVER)
			bag.add(&"parsnip", 2, Inventory.Quality.NORMAL)
			bag.remove(&"parsnip", 2)
			return check_equals(
				case, bag.count_quality(&"parsnip", Inventory.Quality.NORMAL), 0
			)
		&"removal_nulls_the_slot_it_empties":
			var bag := Inventory.new(4)
			bag.add(&"wood", 3)
			bag.remove(&"wood", 3)
			return check_true(
				case, bag.get_slot(0) == null and bag.is_empty(),
				"slot0=%s empty=%s" % [bag.get_slot(0), bag.is_empty()]
			)
		&"different_qualities_never_merge":
			var bag := Inventory.new(8)
			bag.add(&"parsnip", 1, Inventory.Quality.NORMAL)
			bag.add(&"parsnip", 1, Inventory.Quality.GOLD)
			return check_equals(
				case, bag.count_quality(&"parsnip", Inventory.Quality.GOLD), 1
			)
		&"moving_between_slots_swaps_or_merges":
			var bag := Inventory.new(4)
			bag.add(&"wood", 2)
			bag.add(&"stone", 1)
			var swapped := bag.move_slots(0, 1)
			var back := bag.move_slots(1, 0)
			var merged := bag.move_slots(0, 1)
			return check_true(
				case, swapped and back and merged and bag.count(&"stone") == 1 and bag.count(&"wood") == 2,
				"swapped=%s back=%s merged=%s" % [swapped, back, merged]
			)
		&"shrinking_refuses_when_items_would_be_lost":
			# The refusal is about the *discarded* slots specifically. An item
			# parked in slot 5 is destroyed by a shrink to 1, so it must fail; an
			# empty tail is free to go.
			var bag := Inventory.new(6)
			bag.add(&"wood", 1)
			bag.move_slots(0, 5)
			var refused := bag.resize(1)
			var kept := bag.slot_count() == 6 and bag.count(&"wood") == 1
			# And the empty tail really can go, or the refusal above proves nothing.
			bag.move_slots(5, 0)
			var allowed := bag.resize(2)
			return check_true(
				case,
				not refused and kept and allowed and bag.count(&"wood") == 1,
				"refused=%s kept=%s allowed=%s count=%d" % [
					refused, kept, allowed, bag.count(&"wood"),
				]
			)
		&"the_hotbar_wraps_in_both_directions":
			var bar := Hotbar.new(Inventory.new(12))
			bar.select(0)
			bar.cycle(-1)
			var backwards := bar.get_selected()
			bar.cycle(1)
			bar.cycle(1)
			return check_true(
				case,
				backwards == Hotbar.SLOT_COUNT - 1 and bar.get_selected() == 1,
				"backwards=%d forwards=%d" % [backwards, bar.get_selected()]
			)
		&"the_hotbar_shows_nine_slots":
			return check_equals(case, Hotbar.SLOT_COUNT, 9)
		&"the_held_tool_comes_from_the_held_item":
			var bag := Inventory.new(12)
			bag.add(&"hoe", 1)
			var bar := Hotbar.new(bag)
			bar.select(0)
			var wrong: StringName = bar.get_selected_tool_action()
			bar.select(1)
			return check_true(
				case,
				wrong == &"till" and bar.get_selected_tool_action().is_empty(),
				"held=%s empty=%s" % [wrong, bar.get_selected_tool_action()]
			)
		&"the_held_seed_comes_from_the_held_item":
			var bag := Inventory.new(12)
			bag.add(&"parsnip_seeds", 5)
			bag.add(&"hoe", 1)
			var bar := Hotbar.new(bag)
			bar.select(0)
			var seed: StringName = bar.get_selected_seed()
			bar.select(1)
			return check_true(
				case,
				seed == &"parsnip" and bar.get_selected_seed().is_empty(),
				"seed=%s tool_slot_seed=%s" % [seed, bar.get_selected_seed()]
			)
		&"the_generated_world_contains_a_farm_grid":
			var built := await _build_world()
			if built.is_empty():
				return fail(case, "could not build scene")
			var grid: FarmGrid = built["grid"]
			return check_true(
				case, grid != null and grid.tile_count() == 35,
				"grid=%s tiles=%d" % [grid, grid.tile_count() if grid != null else -1]
			)
		&"every_farm_tile_is_aimable_on_foot":
			return await _t_every_tile_aimable()
		&"tilling_through_the_real_interact_key_works":
			return await _t_till_through_input()
		&"planting_and_harvesting_through_the_real_interact_key_works":
			return await _t_full_loop_through_input()
	return fail(case, "unhandled case")


# --- Fixtures -----------------------------------------------------------------

func _make_grid(columns: int, rows: int) -> FarmGrid:
	var grid := FarmGrid.new()
	grid.columns = columns
	grid.rows = rows
	_ensure_rig()
	_rig.add_child(grid)
	# Grid positions are set before `_ready` runs the build, and the build reads
	# them, so nothing else needs doing here.
	return grid


func _make_tile(x: int, y: int) -> SoilTile:
	var tile := SoilTile.new()
	tile.tile_index = Vector2i(x, y)
	_ensure_rig()
	_rig.add_child(tile)
	tile.build_visuals(2.0)
	return tile


## A tilled, watered tile with a ripe crop in it.
func _ripe_tile(crop_id: StringName) -> SoilTile:
	var tile := _make_tile(1, 1)
	tile.till()
	tile.plant(crop_id)
	tile.growth_days = CropRegistry.get_crop(crop_id).days_to_grow
	return tile


func _ensure_rig() -> void:
	if _rig == null or not is_instance_valid(_rig):
		_rig = Node3D.new()
		_rig.name = "FarmTestRig"
		root().add_child(_rig)


func teardown() -> void:
	Input.action_release(&"interact")
	_reset_rig()


# --- Real-scene cases ---------------------------------------------------------

## Builds the real world, the real player and a real [FarmService].
##
## Everything goes under a per-call rig that this function owns, and the rig is
## freed on the next call. Adding the world straight to `root()` instead — which
## is what this did at first — leaks one world and one player per case, and since
## each carries a `Camera3D` that is made current, the probe's
## `get_viewport().get_camera_3d()` starts returning a *previous* case's camera.
## Every aim then misses, and suites that run after this one break too, which is
## a spectacularly confusing failure to debug from the symptom.
func _build_world() -> Dictionary:
	_reset_rig()
	var packed := load("res://scenes/world/world.tscn") as PackedScene
	var player_packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null or player_packed == null:
		return {}

	_ensure_rig()
	var world: WorldRoot = packed.instantiate()
	var player: PlayerController = player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)
	player.global_position = world.get_spawn_point()
	await _step(4)

	var grid := _find_first(world, "FarmGrid") as FarmGrid
	var probe := _find_first(player, "InteractionProbe") as InteractionProbe
	# Loaded by path and instantiated as a bare `Node` rather than named
	# directly: naming `FarmService` here would drag the whole farming stack into
	# this file's compile, which is the documented `class_name` cycle trap.
	var service_script: GDScript = load("res://scripts/farming/farm_service.gd")
	var service: Node = service_script.new()
	service.name = "FarmService"
	_rig.add_child(service)
	if service.has_method("attach_grid"):
		service.call("attach_grid", grid)
	if service.has_method("grant_starter_loadout"):
		service.call("grant_starter_loadout")
	await _step(2)
	return {"world": world, "player": player, "grid": grid, "probe": probe, "service": service}


## Frees the rig, which takes every world, player and service with it.
func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _t_every_tile_aimable() -> Dictionary:
	var c := &"every_farm_tile_is_aimable_on_foot"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var grid: FarmGrid = built["grid"]
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	if grid == null or probe == null:
		return fail(c, "grid=%s probe=%s" % [grid, probe])

	var unreachable: Array[String] = []
	for tile: SoilTile in grid.get_tiles():
		var detail := await _focus(player, probe, tile)
		if not bool(detail["focused"]):
			unreachable.append("%s(%s)" % [str(tile.tile_index), str(detail["why"])])
	if not unreachable.is_empty():
		return fail(c, "%d tiles unaimable: %s" % [unreachable.size(), ", ".join(unreachable)])
	return succeeded(c, "all %d tiles focusable" % grid.tile_count())


func _t_till_through_input() -> Dictionary:
	var c := &"tilling_through_the_real_interact_key_works"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var grid: FarmGrid = built["grid"]
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var service: Node = built["service"]

	# Slot 0 is the hoe the starter loadout grants.
	var tile: SoilTile = grid.get_tile(grid.world_to_tile(grid.global_position))
	var detail := await _focus(player, probe, tile)
	if not bool(detail["focused"]):
		return fail(c, "could not focus centre tile: %s" % str(detail["why"]))
	if probe.get_focus().get_current_verb() != &"till":
		return fail(c, "prompt said %s" % probe.get_focus().get_current_verb())

	var before: int = grid.tilled_count()
	if service.has_method("use_tool"):
		service.call("use_tool", probe.get_focus().get_tile())
	else:
		return fail(c, "FarmService has no use_tool")
	var after: int = grid.tilled_count()
	# A hoe sweeps a 3x3, so more than one tile may change. What matters is that
	# the count went up and the aimed tile specifically is now tilled.
	return check_true(
		c,
		after > before and tile.is_tilled,
		"tilled %d -> %d, aimed tile=%s" % [before, after, tile.is_tilled]
	)


func _t_full_loop_through_input() -> Dictionary:
	var c := &"planting_and_harvesting_through_the_real_interact_key_works"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var grid: FarmGrid = built["grid"]
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var service: Node = built["service"]

	var tile: SoilTile = grid.get_tile(grid.world_to_tile(grid.global_position))
	# Get the tile into tilled, watered, empty state through the tile itself;
	# the *actions under test* below go through the service.
	tile.till()
	tile.water()
	var bag: Inventory = service.get("inventory")
	var bar: Hotbar = service.get("hotbar")
	var seeds_before := 0
	if bag != null:
		seeds_before = bag.count(&"parsnip_seeds")
	# Select the seed packet.
	bar.select(2)
	if bar.get_selected_seed() != &"parsnip":
		return fail(c, "slot 2 held %s" % bar.describe_selected())

	var detail := await _focus(player, probe, tile)
	if not bool(detail["focused"]):
		return fail(c, "could not focus planted tile: %s" % str(detail["why"]))
	var planted: bool = service.call("plant", tile, player)
	if not planted:
		return fail(c, "service refused to plant a tilled, watered, empty tile")
	if bag != null:
		var after_plant: int = bag.count(&"parsnip_seeds")
		if after_plant != seeds_before - 1:
			return fail(c, "seed spent %d -> %d" % [seeds_before, after_plant])

	# Ripen it by advancing the crop clock, then harvest through the service.
	tile.growth_days = CropRegistry.get_crop(&"parsnip").days_to_grow
	if not tile.is_ripe():
		return fail(c, "crop not ripe at %d days" % tile.growth_days)
	var carried_before := 0
	if bag != null:
		carried_before = bag.count(&"parsnip")
	var harvested: bool = service.call("harvest", tile, player)
	if not harvested:
		return fail(c, "service refused to harvest a ripe crop")
	var carried_after := 0
	if bag != null:
		carried_after = bag.count(&"parsnip")
	return check_true(
		c,
		carried_after > carried_before,
		"bag went %d -> %d parsnip" % [carried_before, carried_after]
	)


## Walks the player next to `target`, aims the real camera at it, and presses the
## real interact key. Returns the focus plus a diagnosis, because a bare `false`
## here tells you nothing about which of the four possible causes it was.
func _focus(player: PlayerController, probe: InteractionProbe, target: SoilTile) -> Dictionary:
	var component: SoilTileInteractable = target.get_node_or_null(^"AimVolume/Interactable") as SoilTileInteractable
	if component == null:
		return {"focused": false, "why": "no component"}
	var aim := component.get_aim_point()
	player.global_position = Vector3(aim.x, 0.2, aim.z + 1.8)
	await _step(5)
	var camera := probe.get_camera()
	if camera == null:
		return {"focused": false, "why": "no camera"}
	var dir := (aim - camera.global_position).normalized()
	player.set_yaw(atan2(-dir.x, -dir.z))
	player.camera_rig.set_pitch(atan2(-dir.y, Vector2(dir.x, dir.z).length()))
	await _step(3)
	probe.update_focus()
	var focused := probe.get_focus()
	if focused != null:
		return {"focused": true, "why": ""}
	# Diagnose: where did the ray go, and what did it stop at?
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + (-camera.global_transform.basis.z) * probe.ray_length,
		PhysicsLayers.INTERACTION_MASK
	)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var space := camera.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {"focused": false, "why": "ray hit nothing"}
	var collider: Node = hit["collider"]
	var resolved := Interactable.resolve(collider)
	return {
		"focused": false,
		"why": "ray stopped at %s (resolved=%s) at %.2fm" % [
			collider.name, resolved, origin.distance_to(hit["position"]),
		],
	}


func _find_first(from: Node, want: String) -> Node:
	if from.name == want:
		return from
	for child: Node in from.get_children():
		var found := _find_first(child, want)
		if found != null:
			return found
	return null


func _step(frames: int) -> void:
	for i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame