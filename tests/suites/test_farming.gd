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
		&"the_prompt_follows_the_tile_through_a_whole_cycle",
		&"preview_harvest_agrees_with_harvest",
		&"a_full_bag_refuses_a_harvest_without_ruining_the_crop",
		&"wearing_out_one_of_two_cans_removes_that_one",
		&"a_player_state_service_owns_its_bag",
		&"a_grid_save_round_trips",
		# --- crop art --------------------------------------------------------
		&"every_crop_names_a_model_that_actually_loads",
		&"every_crop_at_every_stage_draws_real_geometry",
		&"a_crop_draws_its_seedling_then_its_mature_model",
		&"a_planted_tile_parents_a_real_crop_model",
		&"the_crop_model_stands_at_the_crops_art_height",
		&"crop_art_height_follows_the_size_of_the_plot",
		&"growing_past_the_halfway_point_swaps_the_model",
		&"harvesting_takes_the_crop_model_away",
		&"a_crop_with_no_art_falls_back_to_the_procedural_plant",
		&"a_crop_model_that_is_not_a_scene_falls_back_rather_than_drawing_nothing",
		# --- inventory -------------------------------------------------------
		&"a_new_bag_is_empty",
		&"adding_merges_into_a_matching_stack",
		&"adding_splits_across_free_slots",
		&"adding_is_all_or_nothing",
		&"removing_spends_lowest_quality_first",
		&"removal_nulls_the_slot_it_empties",
		&"different_qualities_never_merge",
		&"moving_between_slots_swaps_or_merges",
		&"a_tool_wears_out_instead_of_vanishing_at_once",
		&"a_worn_tool_does_not_merge_into_a_fresh_one",
		&"tool_durability_survives_a_save",
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
		&"planting_through_the_interact_key_reaches_the_farm_service",
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
			var centre: Vector3 = grid.tile_to_world(Vector2i(2, 2))
			var found := grid.tiles_in_radius(centre, 3.0)
			if found.size() < 2:
				return fail(case, "expected several tiles, got %d" % found.size())
			# Ascending, so each distance must be at least the one before it.
			# Comparing against `found[0]` alone would pass on any ordering that
			# happened to start nearest, which is the bug this catches.
			var last := -1.0
			var order: Array[String] = []
			for tile: SoilTile in found:
				var d := tile.global_position.distance_to(centre)
				order.append("%.2f" % d)
				if d < last - 0.001:
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
		&"the_prompt_follows_the_tile_through_a_whole_cycle":
			# The prompt is the only thing telling the player what pressing the key
			# will do, and it is derived rather than stored, so the only way it can
			# be wrong is by not being re-derived. Walks the whole cycle, checking
			# after every step — including harvest and overnight growth, which emit
			# none of the per-field signals the component used to listen to.
			var tile := _make_tile(4, 4)
			var component := SoilTileInteractable.new()
			_rig.add_child(component)
			component.set_tile(tile)

			var seen: Array[String] = []
			# Recorded *before* each mutation, so the first entry is the verb the
			# player is shown for bare ground. Reading it afterwards and expecting
			# "till" was an off-by-one that hid the whole sequence behind one wrong
			# first entry.
			seen.append(_verb_after(component))
			tile.till()
			seen.append(_verb_after(component))
			tile.plant(&"parsnip")
			seen.append(_verb_after(component))
			tile.water()
			seen.append(_verb_after(component))
			tile.on_new_day()
			seen.append(_verb_after(component))
			# Ripen it the way a night of watering would, through the tile's own
			# clock rather than by poking the field and announcing it by hand.
			tile.growth_days = CropRegistry.get_crop(&"parsnip").days_to_grow - 1
			tile.water()
			tile.on_new_day()
			seen.append(_verb_after(component))
			tile.harvest()
			seen.append(_verb_after(component))

			return check_equals(
				case, seen,
				[
					"till", "plant", "water", "water", "water", "harvest", "plant",
				] as Array[String]
			)
		&"preview_harvest_agrees_with_harvest":
			var c := case
			# The whole bag-full fix rests on the preview reporting the *same* number
			# the harvest will produce. A disagreement would mean asking the bag about
			# one yield and handing it another.
			for crop_id: StringName in [&"parsnip", &"tomato", &"pumpkin"]:
				var tile := _ripe_tile(crop_id)
				var preview := tile.preview_harvest()
				if not bool(preview["ok"]):
					return fail(c, "%s would not preview: %s"
						% [crop_id, str(preview["reason"])])
				var before: int = tile.growth_days
				tile.preview_harvest()
				if tile.growth_days != before:
					return fail(c, "previewing %s moved its clock" % crop_id)
				var result := tile.harvest()
				if int(result["amount"]) != int(preview["amount"]):
					return fail(c, "%s previewed %d but yielded %d"
						% [crop_id, int(preview["amount"]), int(result["amount"])])
			return succeeded(c)
		&"a_full_bag_refuses_a_harvest_without_ruining_the_crop":
			var c := case
			# A regrowing tomato, a one-slot bag, and that slot already full. The
			# refusal has to leave the player exactly as they were: crop still in the
			# ground, clock still at full ripeness, and no success event published.
			#
			# The old code harvested first and re-planted on failure. `plant` restarts
			# growth at zero, so the tomato silently lost a day, *and* `crop_harvested`
			# had already gone out before the refusal arrived.
			var service := await _make_service()
			var bag: Inventory = service.get("inventory")
			bag.resize(1)
			bag.add(&"hoe", 1)
			if bag.free_slot_count() != 0:
				return fail(c, "bag still has %d free slots" % bag.free_slot_count())

			var tile := _ripe_tile(&"tomato")
			var ripe_at: int = tile.growth_days
			var announced := [0]
			var on_harvested := func(_i: Vector2i, _id: StringName, n: int) -> void:
				announced[0] = int(announced[0]) + n
			EventBus.crop_harvested.connect(on_harvested)

			var ok: bool = service.call("harvest", tile, null)
			EventBus.crop_harvested.disconnect(on_harvested)

			if ok:
				return fail(c, "harvest succeeded into a full bag")
			if int(announced[0]) != 0:
				return fail(c, "published %d crops for a harvest that never happened"
					% int(announced[0]))
			if tile.crop_id != &"tomato":
				return fail(c, "tile now holds '%s'" % tile.crop_id)
			if not tile.is_ripe():
				return fail(c, "tomato knocked back to %d days" % tile.growth_days)
			if tile.growth_days != ripe_at:
				return fail(c, "growth_days moved %d -> %d" % [ripe_at, tile.growth_days])
			return succeeded(c)
		&"wearing_out_one_of_two_cans_removes_that_one":
			var c := case
			# The bug this pins: `remove` spends lowest-quality-first, and two Normal
			# watering cans are indistinguishable by id and quality. Break can #2 and
			# the player loses can #1 instead, keeping the broken one. Per-stack
			# durability exists so two identical tools *can* differ; removing by id
			# throws that away.
			var bag := Inventory.new(8)
			bag.add(&"watering_can", 1)
			bag.add(&"watering_can", 1)
			if bag.count(&"watering_can") != 2:
				return fail(c, "two cans did not both fit")
			var fresh := bag.get_slot(0)
			var worn := bag.get_slot(1)
			if fresh == null or worn == null or fresh == worn:
				return fail(c, "cans did not land in separate slots")
			var full_uses := bag.get_durability(fresh)
			bag.set_durability(fresh, full_uses)
			bag.set_durability(worn, 1)

			if bag.remove_stack(worn, 1) != 1:
				return fail(c, "remove_stack took nothing")
			var left := bag.get_slot(0)
			if left == null:
				return fail(c, "the fresh can was consumed")
			if bag.get_durability(left) != full_uses:
				return fail(c, "fresh can went from %d to %d uses"
					% [full_uses, bag.get_durability(left)])
			return succeeded(c)
		&"a_player_state_service_owns_its_bag":
			var c := case
			# Rewritten when the bag moved to `PlayerStateService`. It used to assert
			# a standalone `FarmService` owns an inventory and hotbar, which is no
			# longer true and should not be: the shop needs the same bag, and two
			# owners is how the player ends up selling produce they cannot see.
			#
			# What is still worth asserting is the *sharing*: the farm service and the
			# player state service must resolve to one bag and one hotbar, not two.
			var service := await _make_service()
			var bag: Inventory = service.get("inventory")
			var bar: Hotbar = service.get("hotbar")
			if bag == null or bar == null:
				return fail(c, "farm service resolved no inventory/hotbar")
			var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
			var state: Node = state_script.find()
			if state == null:
				return fail(c, "no PlayerStateService in the tree")
			if state.get("inventory") != bag:
				return fail(c, "farm service and player state disagree about the bag")
			if state.get("hotbar") != bar:
				return fail(c, "farm service and player state disagree about the hotbar")
			return succeeded(c)
		&"a_tile_save_round_trips":
			var tile := _make_tile(2, 3)
			tile.till()
			tile.plant(&"potato")
			tile.water()
			tile.growth_days = 2
			var clone := SoilTile.from_dict(tile.to_dict())
			# Copied before the compare, then freed. `from_dict` hands back a bare
			# node, and a node is not refcounted — this suite asserts on ObjectDB
			# leaks at exit, so an un-freed tile here fails the whole run.
			var round_tripped := clone.to_dict()
			clone.free()
			return check_equals(case, round_tripped, tile.to_dict())
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
		&"a_tool_wears_out_instead_of_vanishing_at_once":
			# The watering can, not the hoe: content gives the can 60 uses and the
			# hoe none, because the hoe is the one tool a player cannot do without
			# and losing it would end the run. Asserting on the hoe here tested a
			# premise the content never made.
			var bag := Inventory.new(4)
			bag.add(&"watering_can", 1)
			var uses := bag.get_durability(bag.get_slot(0))
			bag.set_durability(bag.get_slot(0), uses - 1)
			var mid := bag.get_durability(bag.get_slot(0))
			# An item with no durability reads as zero, and zero means "never
			# wears" rather than "already broken".
			bag.add(&"hoe", 1)
			var hoe_uses := bag.get_durability(bag.get_slot(1))
			return check_true(
				case,
				uses > 1 and mid == uses - 1 and hoe_uses == 0 and bag.count(&"watering_can") == 1,
				"can %d -> %d, hoe=%d" % [uses, mid, hoe_uses]
			)
		&"a_worn_tool_does_not_merge_into_a_fresh_one":
			# Same id, same quality, different durability. Merging them would
			# silently repair the worn one and the player would never see their
			# tool break. Tools stack at one per slot, so this only shows up as a
			# failure if the cap is wrong *or* the merge ignores durability — hence
			# checking both in one case.
			var bag := Inventory.new(4)
			bag.add(&"watering_can", 1)
			bag.add(&"watering_can", 1)
			var slots := 0
			for i: int in range(bag.slot_count()):
				if not bag.is_slot_empty(i):
					slots += 1
			bag.set_durability(bag.get_slot(0), 3)
			var separate: int = bag.count(&"watering_can")
			return check_true(
				case, separate == 2 and slots == 2,
				"two cans in %d slot(s), count=%d" % [slots, separate]
			)
		&"tool_durability_survives_a_save":
			var bag := Inventory.new(4)
			bag.add(&"watering_can", 1)
			bag.set_durability(bag.get_slot(0), 7)
			var clone := bag.copy()
			return check_equals(
				case, clone.get_durability(clone.get_slot(0)), 7
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
		&"planting_through_the_interact_key_reaches_the_farm_service":
			var c := &"planting_through_the_interact_key_reaches_the_farm_service"
			# Pressing the key, not calling the service directly. The component
			# delegates plant and harvest by *searching* for the service, and that
			# search once matched any node with `plant` and `harvest` methods —
			# which a soil tile also has. The direct-call tests all passed while
			# the shipped interact key was calling `SoilTile.plant()` with two
			# arguments, because nothing exercised the lookup itself.
			var built := await _build_world()
			if built.is_empty():
				return fail(c, "could not build scene")
			var grid: FarmGrid = built["grid"]
			var player: PlayerController = built["player"]
			var probe: InteractionProbe = built["probe"]
			var service: Node = built["service"]

			var tile: SoilTile = grid.get_tile(grid.world_to_tile(grid.global_position))
			tile.till()
			tile.water()
			var bar: Hotbar = service.get("hotbar")
			bar.select(2)
			if bar.get_selected_seed() != &"parsnip":
				return fail(c, "slot 2 held %s" % bar.describe_selected())

			var detail := await _focus(player, probe, tile)
			if not bool(detail["focused"]):
				return fail(c, "could not focus the tile: %s" % str(detail["why"]))

			Input.action_press(&"interact")
			await _step(3)
			Input.action_release(&"interact")
			await _step(2)

			if tile.crop_id == &"parsnip":
				return succeeded(c)
			# Not built with `%` formatting: the service node is outside the scene
			# tree at this point, and asking an out-of-tree node for its string form
			# logs "Cannot get path of node as it is not in a scene tree" on a run
			# that otherwise passed. The gate counts that as a script error.
			return fail(c, "tile held '%s' after pressing interact" % tile.crop_id)
		&"tilling_through_the_real_interact_key_works":
			return await _t_till_through_input()
		&"planting_and_harvesting_through_the_real_interact_key_works":
			return await _t_full_loop_through_input()
		&"every_crop_names_a_model_that_actually_loads":
			var broken: Array[String] = []
			for crop: CropData in CropRegistry.all_crops():
				if not crop.has_model_art():
					broken.append("%s has no art" % crop.id)
					continue
				for model_path: String in [crop.sprout_model, crop.mature_model]:
					if not CropArt.can_load(model_path):
						broken.append("%s -> %s" % [crop.id, model_path])
			return check_equals(case, broken, [] as Array[String])
		&"every_crop_at_every_stage_draws_real_geometry":
			return await _t_every_crop_every_stage(case)
		&"a_crop_draws_its_seedling_then_its_mature_model":
			var art := CropRegistry.get_crop(&"corn")
			if art == null:
				return fail(case, "no corn")
			if art.has_model_art() and art.sprout_model == art.mature_model:
				return fail(case, "both stages use %s" % art.sprout_model)
			# The crossover is at the halfway mark; both sides of it are asserted
			# because a `stage_model` that ignored its argument would otherwise pass
			# an all-sprout check.
			var early := art.stage_model(0.0)
			var late := art.stage_model(0.99)
			if not early.is_empty() and early == late:
				return fail(case, "0%% and 99%% both drew %s" % early)
			return check_equals(case, art.stage_model(0.5), art.mature_model)
		&"a_planted_tile_parents_a_real_crop_model":
			return await _t_planted_tile_has_model(case)
		&"the_crop_model_stands_at_the_crops_art_height":
			return await _t_model_height_matches_art(case)
		&"crop_art_height_follows_the_size_of_the_plot":
			return await _t_model_height_follows_tile(case)
		&"growing_past_the_halfway_point_swaps_the_model":
			return await _t_stage_swap(case)
		&"harvesting_takes_the_crop_model_away":
			return await _t_harvest_clears_model(case)
		&"a_crop_with_no_art_falls_back_to_the_procedural_plant":
			return await _t_no_art_falls_back(case)
		&"a_crop_model_that_is_not_a_scene_falls_back_rather_than_drawing_nothing":
			return await _t_unloadable_model_falls_back(case)
	return fail(case, "unhandled case")


# --- Crop art ------------------------------------------------------------------

## Plants `crop_id` on a real tile at [param days] growth and returns it, or an
## empty dictionary explaining why not.
func _planted_tile(crop_id: StringName, days: int, size: float = 2.0) -> Dictionary:
	var tile := SoilTile.new()
	tile.tile_index = Vector2i(3, 2)
	_ensure_rig()
	_rig.add_child(tile)
	tile.build_visuals(size)
	if not tile.till():
		return {"ok": false, "why": "till refused"}
	if not tile.plant(crop_id):
		return {"ok": false, "why": "plant refused %s" % crop_id}
	tile.growth_days = days
	tile.refresh_visual()
	await _step(2)
	return {"ok": true, "tile": tile}


## The model node a tile is currently drawing, if any.
func _model_of(tile: SoilTile) -> Node3D:
	return tile.get_node_or_null(^"CropModel") as Node3D


## Drawn height in metres of a model instance, measured the way the renderer sees
## it.
##
## Composed through the node hierarchy rather than read off `Mesh.get_aabb()`,
## which reports pre-scale bounds and would make every model look a hundred times
## too small — the exact trap that makes a naive swap silently wrong.
func _drawn_height(node: Node3D) -> float:
	return _drawn_aabb(node).size.y


## World-space bounds of a model instance, composed through the node hierarchy.
##
## Seeded with the node's own transform, because the scale that sizes a crop for
## its tile lives on that node and not on its children.
##
## Reported as a span rather than a height-from-origin, because a model sitting on
## a 0.06 m soil plate has its top 0.06 m above the origin and measuring from zero
## would report every crop as taller than its art height.
func _drawn_aabb(node: Node3D) -> AABB:
	return _merge_aabb(node, node.transform)


func _merge_aabb(node: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var have := false
	for child: Node in node.get_children():
		var local := xform
		if child is Node3D:
			local = xform * (child as Node3D).transform
		var boxes: Array[AABB] = []
		if child is VisualInstance3D:
			boxes.append(local * (child as VisualInstance3D).get_aabb())
		var nested := _merge_aabb(child, local)
		if nested.size.length() > 0.0:
			boxes.append(nested)
		for box: AABB in boxes:
			if have:
				out = out.merge(box)
			else:
				out = box
				have = true
	return out


## The exhaustive visual sweep, for every crop at five points in its season.
##
## This is the case that stands in for looking at the game. A screenshot proves
## one frame on one machine; this proves that *every* crop draws authored geometry
## at *every* stage, that the size matches the art height the content asked for,
## and that the plant genuinely grows — because a swap that kept the seedling
## silhouette all season would pass a "does it draw anything" test and fail this.
func _t_every_crop_every_stage(c: StringName) -> Dictionary:
	var crops := CropRegistry.all_crops()
	if crops.is_empty():
		return fail(c, "no crops")
	var fractions := [0.0, 0.25, 0.5, 0.75, 1.0]
	var problems: Array[String] = []
	var checked := 0

	for crop: CropData in crops:
		var first_height := 0.0
		var last_height := 0.0
		var saw_seedling := false
		var saw_mature := false
		for fraction: float in fractions:
			var built := await _planted_tile(crop.id, int(round(float(crop.days_to_grow) * fraction)))
			if not bool(built["ok"]):
				problems.append("%s @%.2f: %s" % [crop.id, fraction, str(built["why"])])
				continue
			var tile: SoilTile = built["tile"]
			var model := _model_of(tile)
			if model == null:
				problems.append("%s @%.2f: no model parented" % [crop.id, fraction])
				continue
			if not model.visible:
				problems.append("%s @%.2f: model hidden" % [crop.id, fraction])
				continue
			var box := _drawn_aabb(model)
			if box.size.length() <= 0.0:
				problems.append("%s @%.2f: model has no geometry" % [crop.id, fraction])
				continue
			# Triangles are what distinguish authored art from an empty node that
			# happens to report a non-zero AABB.
			if _face_count(model) <= 0:
				problems.append("%s @%.2f: model has no faces" % [crop.id, fraction])
				continue

			var expected := crop.model_height * lerpf(0.35, 1.0, fraction)
			if fraction >= 1.0:
				expected *= 1.12
			if absf(box.size.y - expected) > 0.06:
				problems.append("%s @%.2f: %.2fm drawn, %.2fm asked" % [
					crop.id, fraction, box.size.y, expected,
				])
			if fraction <= 0.0:
				first_height = box.size.y
				saw_seedling = tile.current_model_path() == crop.sprout_model
			if fraction >= 1.0:
				last_height = box.size.y
				saw_mature = tile.current_model_path() == crop.mature_model
			checked += 1

		if not saw_seedling:
			problems.append("%s: day 0 did not draw the seedling" % crop.id)
		if not saw_mature:
			problems.append("%s: ripe did not draw the mature model" % crop.id)
		if last_height <= first_height:
			problems.append("%s: ripe %.2fm is not taller than planted %.2fm" % [
				crop.id, last_height, first_height,
			])

	if not problems.is_empty():
		return fail(c, "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 8))])
	return succeeded(c, "%d crop-stage pairs checked" % checked)


## Total triangles under a node, for the "is there real art in here" assertion.
func _face_count(node: Node) -> int:
	var total := 0
	for child: Node in node.get_children():
		if child is VisualInstance3D and (child as VisualInstance3D).mesh != null:
			total += (child as VisualInstance3D).mesh.get_faces().size() / 3
		total += _face_count(child)
	return total


func _t_planted_tile_has_model(c: StringName) -> Dictionary:
	var built := await _planted_tile(&"corn", 0)
	if not bool(built["ok"]):
		return fail(c, str(built["why"]))
	var tile: SoilTile = built["tile"]
	var model := _model_of(tile)
	if model == null:
		return fail(c, "no CropModel parented")
	if not model.visible:
		return fail(c, "CropModel is hidden")
	# A model with no geometry in it would satisfy every other assertion here.
	if _drawn_height(model) <= 0.0:
		return fail(c, "CropModel has no geometry")
	return succeeded(c, "%s drawn %.2fm" % [model.name, _drawn_height(model)])


## The number that matters: a 1.4 m art height must *draw* at 1.4 m on a 2 m tile,
## not at some figure inherited from the FBX importer's unit conversion.
func _t_model_height_matches_art(c: StringName) -> Dictionary:
	var built := await _planted_tile(&"corn", 99)
	if not bool(built["ok"]):
		return fail(c, str(built["why"]))
	var tile: SoilTile = built["tile"]
	var crop := CropRegistry.get_crop(&"corn")
	var model := _model_of(tile)
	if model == null:
		return fail(c, "no CropModel parented")
	var drawn := _drawn_height(model)
	# Ripe adds a 1.12 lift on top of the art height, matching the placeholder.
	var expected := crop.model_height * 1.12
	return check_in_range(c, drawn, expected - 0.05, expected + 0.05)


func _t_model_height_follows_tile(c: StringName) -> Dictionary:
	var small := await _planted_tile(&"corn", 99, 2.0)
	var large := await _planted_tile(&"corn", 99, 4.0)
	if not bool(small["ok"]) or not bool(large["ok"]):
		return fail(c, "could not plant both")
	var a := _drawn_height(_model_of(small["tile"]))
	var b := _drawn_height(_model_of(large["tile"]))
	if a <= 0.0 or b <= 0.0:
		return fail(c, "2m tile drew %.2fm, 4m tile drew %.2fm" % [a, b])
	# A 4 m plot should carry plants twice as tall, within a hair for rounding.
	return check_in_range(c, b / a, 2.0, 2.1)


func _t_stage_swap(c: StringName) -> Dictionary:
	var built := await _planted_tile(&"corn", 0)
	if not bool(built["ok"]):
		return fail(c, str(built["why"]))
	var tile: SoilTile = built["tile"]
	var crop := CropRegistry.get_crop(&"corn")
	if _model_of(tile) == null:
		return fail(c, "no seedling model parented")

	var seen: Array[String] = []
	# Walk the whole season a day at a time, which is how the game actually gets
	# there. Counting rebuilds as well as the swap: a repaint that reinstantiated
	# the scene on every day is the performance bug this same loop would hide.
	var rebuilds := 0
	for day: int in range(0, crop.days_to_grow + 1):
		tile.growth_days = day
		tile.refresh_visual()
		await _step(1)
		if _model_of(tile) == null:
			return fail(c, "model vanished on day %d" % day)
		var path := tile.current_model_path()
		if seen.is_empty() or seen[-1] != path:
			seen.append(path)
			rebuilds += 1
	if seen.size() != 2:
		return fail(c, "expected 2 distinct models across the season, saw %s" % str(seen))
	if seen[0] != crop.sprout_model or seen[1] != crop.mature_model:
		return fail(c, "stages were %s then %s" % [seen[0], seen[1]])
	# One rebuild per stage, not one per day.
	if rebuilds != 2:
		return fail(c, "%d rebuilds across %d days for 2 stages" % [
			rebuilds, crop.days_to_grow + 1,
		])
	return succeeded(c, "2 stages, 1 swap at day %d" % (crop.days_to_grow / 2))


func _t_harvest_clears_model(c: StringName) -> Dictionary:
	var built := await _planted_tile(&"corn", 99)
	if not bool(built["ok"]):
		return fail(c, str(built["why"]))
	var tile: SoilTile = built["tile"]
	if _model_of(tile) == null:
		return fail(c, "no model before harvest")
	var ripe_height := _drawn_height(_model_of(tile))

	var result := tile.harvest()
	if not bool(result["ok"]):
		return fail(c, "harvest refused: %s" % str(result["reason"]))
	await _step(2)
	if _model_of(tile) == null:
		return fail(c, "no model after harvest")

	# Corn regrows, so the tile is *not* empty — it is a young plant again. Its
	# clock rewinds to `days_to_grow - regrow_days`, which for corn is 10 of 14
	# days: still past the halfway mark, so the mature silhouette is *correct*
	# here. What must change is the size, because that is what tells the player the
	# plant needs more days. Asserting "the model went back to the seedling" would
	# be asserting a bug.
	var crop := CropRegistry.get_crop(&"corn")
	if tile.growth_days != crop.days_to_grow - crop.regrow_days:
		return fail(c, "clock at %d days after harvest" % tile.growth_days)
	var young_height := _drawn_height(_model_of(tile))
	if young_height >= ripe_height:
		return fail(c, "regrown plant %.2fm is not shorter than ripe %.2fm" % [
			young_height, ripe_height,
		])
	# And the size has to agree with the rewound clock, not merely be smaller.
	var fraction := tile.growth_fraction()
	var expected := crop.model_height * lerpf(0.35, 1.0, fraction)
	return check_in_range(c, young_height, expected - 0.05, expected + 0.05)


func _t_no_art_falls_back(c: StringName) -> Dictionary:
	# Mutate a real crop rather than inventing one and registering it: the registry
	# has no public insert, and adding one purely for tests would put a production
	# API on the board for no gameplay reason. Restored before returning, because
	# `CropRegistry` is static and a dirty crop would follow into every later case.
	var crop := CropRegistry.get_crop(&"parsnip")
	if crop == null:
		return fail(c, "no parsnip")
	var saved_sprout := crop.sprout_model
	var saved_mature := crop.mature_model
	crop.sprout_model = ""
	crop.mature_model = ""

	var tile := SoilTile.new()
	tile.tile_index = Vector2i(5, 5)
	_ensure_rig()
	_rig.add_child(tile)
	tile.build_visuals(2.0)
	tile.till()
	var planted := tile.plant(&"parsnip")
	await _step(2)

	var stalk := tile.get_node_or_null(^"CropMesh") as MeshInstance3D
	var grew_model := _model_of(tile) != null
	var stalk_visible := stalk != null and stalk.visible
	var stalk_scale := stalk.scale.y if stalk != null else 0.0

	crop.sprout_model = saved_sprout
	crop.mature_model = saved_mature

	if not planted:
		return fail(c, "plant refused an artless crop")
	if grew_model:
		return fail(c, "artless crop grew a model anyway")
	# The fallback still has to show progress, so it must be visible and scaled.
	if not stalk_visible:
		return fail(c, "procedural stalk not visible")
	return succeeded(c, "stalk at %.2f" % stalk_scale)


func _t_unloadable_model_falls_back(c: StringName) -> Dictionary:
	# Same mutate-and-restore as above.
	#
	# The path points at a file that *exists* but is not a scene, rather than at a
	# missing one. A genuinely absent path is covered by `generate_crop_data.gd`,
	# which validates every art path and fails the build — and deliberately
	# `load()`ing a missing file here would log a resource error, which
	# `tools/check.ps1` treats as a failure. What this case has to prove is the
	# runtime half: content that does not resolve to a model must not produce an
	# empty tile.
	var crop := CropRegistry.get_crop(&"parsnip")
	if crop == null:
		return fail(c, "no parsnip")
	var saved_sprout := crop.sprout_model
	var saved_mature := crop.mature_model
	var not_a_model := "res://resources/farming/crops/parsnip.tres"
	crop.sprout_model = not_a_model
	crop.mature_model = not_a_model

	var tile := SoilTile.new()
	tile.tile_index = Vector2i(6, 6)
	_ensure_rig()
	_rig.add_child(tile)
	tile.build_visuals(2.0)
	tile.till()
	var planted := tile.plant(&"parsnip")
	await _step(2)

	var grew_model := _model_of(tile) != null
	var stalk := tile.get_node_or_null(^"CropMesh") as MeshInstance3D
	var stalk_visible := stalk != null and stalk.visible

	crop.sprout_model = saved_sprout
	crop.mature_model = saved_mature

	if not planted:
		return fail(c, "plant refused")
	if grew_model:
		return fail(c, "parented a model for a path that is not a scene")
	# The point of the case: a bad path in a `.tres` must not produce an empty
	# tile. It has to fall back to the procedural plant the game already had.
	if not stalk_visible:
		return fail(c, "nothing drawn at all for an unusable model path")
	return succeeded(c)


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


## The verb the component would offer right now.
func _verb_after(component: SoilTileInteractable) -> String:
	return String(component.get_current_verb())


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
	var state := await _add_player_state()
	_rig.add_child(state)
	if state.has_method("grant_starter_loadout"):
		state.call("grant_starter_loadout")
	var service_script: GDScript = load("res://scripts/farming/farm_service.gd")
	var service: Node = service_script.new()
	service.name = "FarmService"
	_rig.add_child(service)
	if service.has_method("attach_grid"):
		service.call("attach_grid", grid)
	await _step(2)
	return {"world": world, "player": player, "grid": grid, "probe": probe, "service": service}


## A bare [FarmService] with no world attached, for cases that only need a bag.
##
## Loaded by path for the same reason `_build_world` does it: naming the class
## would pull the whole farming stack into this file's compile.
func _make_service() -> Node:
	_ensure_rig()
	var service_script: GDScript = load("res://scripts/farming/farm_service.gd")
	var service: Node = service_script.new()
	service.name = "FarmService"
	_rig.add_child(service)
	_rig.add_child(await _add_player_state())
	await _step(2)
	return service


## Adds the [PlayerStateService] that now owns the bag, hotbar and stamina.
##
## Added before [FarmService] and loaded by path, mirroring the `FarmService`
## rule above. Ordering matters only for readability — `FarmService` resolves it
## by group on first use, not by construction order — but a service added after
## the farm service reads like a lifecycle bug even though it is not one.
func _add_player_state() -> Node:
	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	return state


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
	# The real key, not `use_tool` directly. The point of this case is the whole
	# chain — probe focus, component verb, selected tool, service lookup — and
	# calling the service short-circuits exactly the links that have broken.
	if not service.has_method("use_tool"):
		return fail(c, "FarmService has no use_tool")
	Input.action_press(&"interact")
	await _step(3)
	Input.action_release(&"interact")
	await _step(2)
	var after: int = grid.tilled_count()
	# What matters is that the aimed tile specifically is now tilled. Whether a
	# hoe also disturbed its neighbours is `tool_reach`'s business, not this
	# case's.
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
	# Arranged by hand, not by playing: there is no "till and water this tile"
	# key, so the starting state has to be set up. Everything *after* this point
	# goes through the interact key.
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

	# Real key for both actions. Harvest in particular is worth driving through
	# the probe: it is the one verb that changes *after* the keypress, so it
	# depends on the prompt refresh firing correctly to be reachable at all.
	Input.action_press(&"interact")
	await _step(3)
	Input.action_release(&"interact")
	await _step(2)

	var planted: bool = tile.crop_id == &"parsnip"
	if not planted:
		return fail(c, "interact key did not plant (crop is '%s')" % tile.crop_id)
	if bag != null:
		var after_plant: int = bag.count(&"parsnip_seeds")
		if after_plant != seeds_before - 1:
			return fail(c, "seed spent %d -> %d" % [seeds_before, after_plant])

	# Ripen it by advancing the crop clock, then harvest with the key again.
	tile.growth_days = CropRegistry.get_crop(&"parsnip").days_to_grow
	if not tile.is_ripe():
		return fail(c, "crop not ripe at %d days" % tile.growth_days)
	var carried_before := 0
	if bag != null:
		carried_before = bag.count(&"parsnip")

	var ready := await _focus(player, probe, tile)
	if not bool(ready["focused"]):
		return fail(c, "ripe tile not re-focusable: %s" % str(ready["why"]))
	if probe.get_focus().get_current_verb() != &"harvest":
		return fail(c, "prompt said %s, expected harvest" % probe.get_focus().get_current_verb())

	Input.action_press(&"interact")
	await _step(3)
	Input.action_release(&"interact")
	await _step(2)

	var carried_after := 0
	if bag != null:
		carried_after = bag.count(&"parsnip")
	if carried_after <= carried_before:
		return fail(c, "bag went %d -> %d parsnip" % [carried_before, carried_after])
	return succeeded(c)


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
	# `atan2(dir.y, horizontal)`, with no negation. Rotating a node by +pitch
	# tilts the camera's forward vector *upward* — a camera looks down -Z, and
	# rotating about +X carries -Z toward +Y. So a positive pitch is looking at
	# the sky, and negating `dir.y` here aimed every tile at empty air. The ray
	# hit nothing at all, not even the ground, which is the tell.
	player.camera_rig.set_pitch(atan2(dir.y, Vector2(dir.x, dir.z).length()))
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