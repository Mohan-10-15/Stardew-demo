extends TestSuite
## W3.2: the pure voxel core — content, meshing, breaking, generation and
## persistence. No scene or rendering context is needed for any case here.

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _mine(seed_value: int) -> DeepMines:
	var mine := DeepMines.new()
	mine.world_seed = seed_value
	_nodes.append(mine)
	return mine

func get_cases() -> Array[StringName]:
	return [
		&"at_least_24_blocks_are_authored",
		&"mesher_culls_hidden_faces",
		&"ambient_occlusion_darkens_corners",
		&"breaking_respects_tier_and_speed",
		&"generation_is_deterministic",
		&"raycast_hits_the_first_solid_cell",
		&"edits_round_trip_as_deltas",
		&"ten_deterministic_mine_floors",
		&"mine_edits_survive_a_save",
	]


func _grid() -> VoxelGrid:
	return VoxelGrid.new()


func _run(case: StringName) -> Dictionary:
	match case:
		&"at_least_24_blocks_are_authored":
			var blocks := BlockRegistry.all_blocks()
			if blocks.size() < 24:
				return fail(case, "only %d blocks" % blocks.size())
			if not BlockRegistry.duplicate_ids().is_empty():
				return fail(case, "duplicate block ids")
			for block: BlockData in blocks:
				if not block.is_valid():
					return fail(case, "%s is invalid" % block.id)
			return succeeded(case, "%d valid blocks" % blocks.size())
		&"mesher_culls_hidden_faces":
			var grid := _grid()
			var at := Vector3i(3, 3, 3)
			grid.set_block(at, &"hollowbrook_stone")
			var one: Dictionary = VoxelMesher.build(grid, Vector3i.ZERO)
			if int(one["faces"]) != 6:
				return fail(case, "one cube made %d faces" % int(one["faces"]))
			grid.set_block(at + Vector3i(1, 0, 0), &"hollowbrook_stone")
			var two: Dictionary = VoxelMesher.build(grid, Vector3i.ZERO)
			if int(two["faces"]) != 10:
				return fail(case, "two adjacent cubes made %d faces" % int(two["faces"]))
			return succeeded(case, "6 faces alone, 10 adjacent")
		&"ambient_occlusion_darkens_corners":
			var grid := _grid()
			var at := Vector3i(2, 2, 2)
			grid.set_block(at, &"hollowbrook_stone")
			var open: float = VoxelMesher.ambient_occlusion(
				grid, Vector3i.ZERO, at, Vector3i(0, 1, 0))
			grid.set_block(at + Vector3i(1, 1, 1), &"hollowbrook_stone")
			var shaded: float = VoxelMesher.ambient_occlusion(
				grid, Vector3i.ZERO, at, Vector3i(0, 1, 0))
			if open <= shaded:
				return fail(case, "AO did not darken an occluded corner")
			return succeeded(case, "AO %.2f -> %.2f" % [open, shaded])
		&"breaking_respects_tier_and_speed":
			var stone := BlockRegistry.get_block(&"iron_vein_block")
			if stone == null:
				return fail(case, "no iron vein block")
			var refusal: StringName = BlockBreaking.can_break(stone, &"pickaxe")
			if refusal != &"tier_too_low":
				return fail(case, "starter pickaxe was not refused: %s" % refusal)
			var copper := BlockRegistry.get_block(&"copper_vein_block")
			var seconds: float = BlockBreaking.break_seconds(copper, &"pickaxe")
			if seconds <= 0.0 or seconds > copper.hardness + 0.01:
				return fail(case, "break time %f is out of range" % seconds)
			return succeeded(case, "tier gate and break time correct")
		&"generation_is_deterministic":
			var a := _grid()
			var b := _grid()
			VoxelGenerator.new(4242).generate_mine_floor(a, 3, 8, 0)
			VoxelGenerator.new(4242).generate_mine_floor(b, 3, 8, 0)
			if a.edit_hash() != b.edit_hash():
				return fail(case, "same seed gave different floors")
			if a.chunks.is_empty():
				return fail(case, "generator produced no chunks")
			return succeeded(case, "same seed -> same grid hash")
		&"raycast_hits_the_first_solid_cell":
			var grid := _grid()
			grid.set_block(Vector3i(2, 0, 0), &"hollowbrook_stone")
			grid.set_block(Vector3i(4, 0, 0), &"hollowbrook_stone")
			var hit: Dictionary = VoxelRaycast.cast(
				grid, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 10.0)
			if (hit.get("cell") as Vector3i) != Vector3i(2, 0, 0):
				return fail(case, "ray hit %s" % str(hit.get("cell")))
			return succeeded(case, "first solid cell at x=2")
		&"edits_round_trip_as_deltas":
			var grid := _grid()
			grid.set_block(Vector3i(1, 2, 3), &"oak_log")
			var data: Dictionary = grid.to_dict()
			var fresh := _grid()
			fresh.from_dict(data)
			if fresh.get_block(Vector3i(1, 2, 3)) != &"oak_log":
				return fail(case, "edit did not round-trip")
			if fresh.edit_hash() != grid.edit_hash():
				return fail(case, "edit hash changed across save")
			return succeeded(case, "delta saved and restored")
		&"ten_deterministic_mine_floors":
			var a := _mine(9001)
			var b := _mine(9001)
			a.enter()
			b.enter()
			for _i: int in range(DeepMines.FLOORS - 1):
				if not a.descend() or not b.descend():
					return fail(case, "could not descend to floor 10")
			if a.floor != 10 or b.floor != 10:
				return fail(case, "climb ended at floor %d" % a.floor)
			if not a.is_boss_floor() or not a.is_lantern_room(10):
				return fail(case, "floor 10 is not boss/lantern room")
			if a.grid.edit_hash() != b.grid.edit_hash():
				return fail(case, "same seed gave different boss floors")
			return succeeded(case, "10 floors, boss + lantern room, deterministic")
		&"mine_edits_survive_a_save":
			var mine := _mine(12345)
			mine.enter()
			mine.grid.set_block(Vector3i(2, -8, 2), &"oak_planks")
			var data: Dictionary = mine.to_dict()
			var fresh := _mine(12345)
			fresh.from_dict(data)
			if fresh.floor != mine.floor or fresh.grid.get_block(
					Vector3i(2, -8, 2)) != &"oak_planks":
				return fail(case, "mine state did not round-trip")
			return succeeded(case, "floor and edits survived a save")
	return fail(case, "no case implementation for %s" % case)
