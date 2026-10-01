extends TestSuite
## World construction - Group 3 follow-up (procedural world integrity).
##
## Guards the specific failure that visual and collision geometry are generated
## from *different* random sequences, which produces visible-but-not-solid trees.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _world: Node3D = null


func is_async() -> bool:
	return true


func setup() -> void:
	_world = null


func teardown() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null


func get_cases() -> Array[StringName]:
	return [
		&"world_builds_expected_regions",
		&"forest_visual_and_collider_counts_match",
		&"forest_colliders_sit_on_visible_trunks",
		&"ground_supports_the_spawn_point",
	]


func _build() -> Node3D:
	var packed := load(WORLD_SCENE) as PackedScene
	if packed == null:
		return null
	_world = packed.instantiate()
	root().add_child(_world)
	await _step(3)
	return _world


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


## Visible trunk count.
##
## `MultiMesh.get_instance_transform()` returns identity for every instance in a
## headless run because the transform buffer is only populated on the GPU, so
## positions cannot be read back here. Only `instance_count` is reliable, which
## is why the alignment check compares against the generator's own metadata.
func _trunk_count() -> int:
	var mi := _world.get_node_or_null(^"ForestTrunks") as MultiMeshInstance3D
	if mi == null or mi.multimesh == null:
		return 0
	return mi.multimesh.instance_count


## Every StaticBody3D in the tree group, i.e. the tree colliders.
func _tree_colliders() -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect(_world, out)
	return out


func _collect(node: Node, out: Array[Node3D]) -> void:
	for child: Node in node.get_children():
		# Matched by shape type rather than node name so the check cannot be
		# satisfied, or broken, by a rename.
		if child is StaticBody3D:
			for grandchild: Node in child.get_children():
				if grandchild is CollisionShape3D and (grandchild as CollisionShape3D).shape is CapsuleShape3D:
					out.append(child)
					break
		_collect(child, out)


func _t_regions() -> Dictionary:
	var c := &"world_builds_expected_regions"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	for node_name: String in ["Ground", "Pond", "FarmSoil", "VillageWell", "NoticeBoard", "SupplyCrate"]:
		if world.get_node_or_null(NodePath(node_name)) == null:
			return fail(c, "missing region node '%s'" % node_name)
	return succeeded(c, "all regions present")


func _t_counts_match() -> Dictionary:
	var c := &"forest_visual_and_collider_counts_match"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var trunks := _trunk_count()
	var colliders := _tree_colliders()
	if trunks == 0:
		return fail(c, "no trunk instances were generated")
	if trunks != colliders.size():
		return fail(c, "%d visible trunks but %d colliders - they disagree" % [
			trunks, colliders.size(),
		])
	return succeeded(c, "%d trunks and %d colliders match" % [trunks, colliders.size()])


func _t_colliders_aligned() -> Dictionary:
	var c := &"forest_colliders_sit_on_visible_trunks"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var sites: Array[Vector2] = _world.get_meta(&"forest_sites", [])
	if sites.is_empty():
		return fail(c, "world did not record its forest sites")
	var colliders := _tree_colliders()
	if sites.size() != colliders.size():
		return fail(c, "count mismatch (%d sites vs %d colliders)" % [
			sites.size(), colliders.size(),
		])

	# Every collider must sit on the tree the multimesh draws at that site.
	# The old code generated the two from separate rng passes, which put
	# colliders in a different part of the forest entirely.
	var used: Array[int] = []
	used.resize(sites.size())
	used.fill(0)
	var worst := 0.0
	var worst_detail := ""
	for collider: Node3D in colliders:
		var here := collider.position
		var best_index := -1
		var best := INF
		for i: int in range(sites.size()):
			var site: Vector2 = sites[i]
			var d := Vector2(here.x, here.z).distance_to(site)
			if d < best:
				best = d
				best_index = i
		if best > worst:
			worst = best
			worst_detail = "collider at %s vs site %d at %s, %.2fm apart" % [
				here, best_index, sites[best_index], best,
			]
		if best_index >= 0:
			used[best_index] += 1

	if worst > 0.75:
		return fail(c, "worst alignment off by %.2fm; %s" % [worst, worst_detail])

	# Nearest-site matching must be a bijection, otherwise two colliders could
	# sit on one tree while another tree has none.
	var duplicated := 0
	for i: int in range(used.size()):
		if used[i] > 1:
			duplicated += 1
	if duplicated > 0:
		return fail(c, "%d sites have more than one collider" % duplicated)
	return succeeded(c, "all %d colliders sit on their own visible trunk" % sites.size())


func _t_ground_supports_spawn() -> Dictionary:
	var c := &"ground_supports_the_spawn_point"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var world_root := world as WorldRoot
	if world_root == null:
		return fail(c, "world scene root is not a WorldRoot")
	var spawn: Vector3 = world_root.get_spawn_point()

	# Cast down from above the spawn and require it to hit the ground rather
	# than falling through the world.
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return fail(c, "no physics space")
	var query := PhysicsRayQueryParameters3D.create(
		spawn + Vector3.UP * 5.0, spawn + Vector3.DOWN * 50.0, 1
	)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fail(c, "nothing under the spawn point %s - the player would fall" % spawn)
	# The ground top sits at y=0.
	if absf(hit["position"].y) > 0.5:
		return fail(c, "ground under spawn is at y=%.2f, expected ~0" % hit["position"].y)
	return succeeded(c, "spawn %s rests on ground at y=%.2f" % [spawn, hit["position"].y])


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"world_builds_expected_regions":
			return await _t_regions()
		&"forest_visual_and_collider_counts_match":
			return await _t_counts_match()
		&"forest_colliders_sit_on_visible_trunks":
			return await _t_colliders_aligned()
		&"ground_supports_the_spawn_point":
			return await _t_ground_supports_spawn()
	return fail(case, "no case implementation for %s" % case)