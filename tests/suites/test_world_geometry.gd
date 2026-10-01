extends TestSuite
## Group 4 world-generation geometry checks.
##
## These assert *relationships between* generated pieces rather than exact
## numbers, so re-tuning the valley does not invalidate them.
##
## Terrain height is read back by raycasting the real ground collider, not by
## inspecting node positions. That is deliberate: the ground is a displaced
## trimesh whose surface varies across the pond, so any assertion phrased as
## "the ground is at y=X" is measuring the wrong thing. A raycast measures what
## the player would actually stand on.

const POND := Vector2(-14.0, 44.0)
const FLAT_PROBE_A := Vector2(80.0, -60.0)
const FLAT_PROBE_B := Vector2(-90.0, 80.0)
## Tolerance for "the valley floor is flat". The grid is exact here, so this is
## only guarding against floating-point drift in the collider, not re-tuning.
const FLAT_EPSILON := 0.02

func get_cases() -> Array[StringName]:
	return [
		&"ground_has_collision",
		&"ground_matches_its_visual_mesh",
		&"the_valley_floor_is_flat_outside_the_pond",
		&"the_pond_is_a_depression_below_the_valley_floor",
		&"pond_water_is_visible_above_the_basin",
		&"pond_floor_is_below_the_water_surface",
		&"farm_fence_perimeter_is_closed",
	]


func is_async() -> bool:
	# WorldRoot builds its children on the frame it enters the tree, and physics
	# shapes are not queryable until a physics frame has run, so every case has
	# to await frames before it can measure anything.
	return true


func _run_async(case: StringName) -> Dictionary:
	var world := await _build_world()
	if world == null:
		return fail(case, "world scene failed to load")
	var space := _space_of(world)
	if space == null:
		return fail(case, "world has no physics space")
	match case:
		&"ground_has_collision":
			return _check_ground_collision(case, world, space)
		&"ground_matches_its_visual_mesh":
			return _check_ground_is_trimesh(case, world)
		&"the_valley_floor_is_flat_outside_the_pond":
			return _check_flat_floor(case, space)
		&"the_pond_is_a_depression_below_the_valley_floor":
			return _check_basin_depth(case, space)
		&"pond_water_is_visible_above_the_basin":
			return _check_water_visible(case, world, space)
		&"pond_floor_is_below_the_water_surface":
			return _check_pond_floor(case, world, space)
		&"farm_fence_perimeter_is_closed":
			return _check_fence(case, world)
	return fail(case, "unhandled case")


## Builds the real world scene. No `class_name` reference: those are not
## resolvable from the harness's perspective and would couple the suite to a
## specific script layout.
func _build_world() -> Node3D:
	var packed := load("res://scenes/world/world.tscn")
	if packed == null:
		return null
	var world: Node3D = packed.instantiate()
	root().add_child(world)
	await tree.process_frame
	await tree.physics_frame
	return world


func _space_of(world: Node3D) -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


## Height of the walkable ground under an XZ position, or NAN if nothing is
## there.
func _surface_height(space: PhysicsDirectSpaceState3D, xz: Vector2) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, 60.0, xz.y), Vector3(xz.x, -60.0, xz.y), 1
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return hit["position"].y


func _water_y(world: Node3D) -> float:
	var pond := world.get_node_or_null(^"Pond") as MeshInstance3D
	return NAN if pond == null else pond.position.y


## The ground must have *a* collider the player can stand on.
##
## Originally asserted the collider top was exactly y=0, which was correct while
## the ground was a flat box and is meaningless now it is a displaced trimesh.
## What has to stay true is that a downward ray finds ground everywhere in the
## valley the player is expected to walk.
func _check_ground_collision(case: StringName, world: Node3D, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var ground := world.get_node_or_null(^"Ground") as StaticBody3D
	if ground == null:
		return fail(case, "no Ground node")
	if _trimesh_of(ground) == null:
		return fail(case, "Ground has no ConcavePolygonShape3D collider")
	for probe: Vector2 in [FLAT_PROBE_A, FLAT_PROBE_B, POND]:
		var y := _surface_height(space, probe)
		if is_nan(y):
			return fail(case, "no ground under %s - the player would fall through" % probe)
	return succeeded(case, "ground collider answers raycasts across the valley")


## The visual mesh and the collider have to be the same shape.
##
## These were two independently authored pieces, which is how the pond ended up
## with walkable dry land over the water: the visual ground was flat and the
## collider was flat, so nothing anywhere said "there is a basin here". Now both
## come from one vertex buffer, so this asserts they are still the same object.
func _check_ground_is_trimesh(case: StringName, world: Node3D) -> Dictionary:
	var ground := world.get_node_or_null(^"Ground") as StaticBody3D
	if ground == null:
		return fail(case, "no Ground node")
	var tri := _trimesh_of(ground)
	if tri == null:
		return fail(case, "Ground collider is not a trimesh")
	if tri.get_faces().size() < 3:
		return fail(case, "Ground trimesh has no faces")
	var mesh := ground.get_node_or_null(^"GroundMesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return fail(case, "Ground has no visual mesh")
	var verts := mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.is_empty():
		return fail(case, "Ground visual mesh has no vertices")
	return succeeded(case, "collider and mesh both built from a %d-face trimesh" % (tri.get_faces().size() / 3))


## Away from the pond the valley floor must still be flat, or every prop, path
## and fence post authored against y=0 would float or sink.
func _check_flat_floor(case: StringName, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var a := _surface_height(space, FLAT_PROBE_A)
	var b := _surface_height(space, FLAT_PROBE_B)
	if is_nan(a) or is_nan(b):
		return fail(case, "could not raycast the valley floor")
	if absf(a) > FLAT_EPSILON or absf(b) > FLAT_EPSILON:
		return fail(case, "valley floor is not flat: %s is at y=%.3f, %s is at y=%.3f" % [FLAT_PROBE_A, a, FLAT_PROBE_B, b])
	return succeeded(case, "valley floor flat at y=0 across the valley")


## The pond must be an actual hole in the ground.
##
## This is the regression the whole change exists for. The old ground was a
## single flat face, so a ray over the pond centre hit solid ground at exactly
## the valley height and the player walked on dry land above the water. A
## depression is the only thing that makes the pond read as water.
func _check_basin_depth(case: StringName, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var centre := _surface_height(space, POND)
	if is_nan(centre):
		return fail(case, "no ground under the pond centre")
	if centre >= 0.0:
		return fail(case, "pond centre ground is at y=%.3f, not below the valley floor - the pond is walkable dry land" % centre)
	# The rim has to be above the basin floor, otherwise there is no shoreline.
	var rim := _surface_height(space, POND + Vector2(24.0, 0.0))
	if is_nan(rim):
		return fail(case, "no ground beside the pond")
	if rim <= centre:
		return fail(case, "pond rim y=%.3f is not above the basin floor y=%.3f" % [rim, centre])
	return succeeded(case, "basin floor y=%.3f, rim y=%.3f" % [centre, rim])


## The water plane has to sit above the basin floor it fills and below the
## surrounding grass.
##
## This regressed once already: the water was authored at y=-0.8 while the ground
## mesh was a flat plane at y=0, so the entire pond rendered underneath opaque
## grass. Nothing caught it because every functional test passed and a headless
## run cannot see it.
##
## Checking `grass.position.y` no longer proves anything - the grass node sits
## at the origin while its *surface* dips into the basin. What has to hold is
## that the water plane is between the two surfaces it is meant to fill.
func _check_water_visible(case: StringName, world: Node3D, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var water := _water_y(world)
	if is_nan(water):
		return fail(case, "no Pond water node")
	var floor_y := _surface_height(space, POND)
	var rim_y := _surface_height(space, POND + Vector2(24.0, 0.0))
	if is_nan(floor_y) or is_nan(rim_y):
		return fail(case, "could not raycast the pond")
	if water <= floor_y:
		return fail(case, "water at y=%.3f is not above the basin floor at y=%.3f - the water is buried in the ground" % [water, floor_y])
	if water >= rim_y:
		return fail(case, "water at y=%.3f is not below the valley floor at y=%.3f - the water floods the grass" % [water, rim_y])
	return succeeded(case, "water y=%.3f between basin floor y=%.3f and valley floor y=%.3f" % [water, floor_y, rim_y])


## The authored pond floor must also clear the water, so the deepest point does
## not show through the surface.
func _check_pond_floor(case: StringName, world: Node3D, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var floor_node := world.get_node_or_null(^"PondFloor")
	if floor_node == null:
		return fail(case, "no PondFloor node")
	var water := _water_y(world)
	if is_nan(water):
		return fail(case, "no Pond water node")
	var floor_top := _top_of(floor_node)
	if is_nan(floor_top):
		return fail(case, "PondFloor has no box collider")
	if floor_top >= water:
		return fail(case, "pond floor top %s is at or above the water surface y=%s" % [floor_top, water])
	var centre := _surface_height(space, POND)
	if is_nan(centre):
		return fail(case, "could not raycast the pond centre")
	if floor_top > centre + 0.01:
		return fail(case, "pond floor collider %s sits above the terrain it backs up (%s)" % [floor_top, centre])
	return succeeded(case, "floor %s below water %s and below terrain %s" % [floor_top, water, centre])


## A closed perimeter needs all four posts and all four rails. A missing rail
## means the player can walk straight off the farm.
func _check_fence(case: StringName, world: Node3D) -> Dictionary:
	var posts := 0
	var rails := 0
	for child in world.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		for shape in body.get_children():
			if shape is CollisionShape3D and (shape as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((shape as CollisionShape3D).shape as BoxShape3D).size
				# Posts are tall and thin; rails are long and flat.
				if size.y > 0.6 and size.x < 0.4:
					posts += 1
				elif size.x < 0.3 and size.z > 5.0:
					rails += 1
	if posts < 4:
		return fail(case, "expected 4 farm fence posts, found %d" % posts)
	if rails < 4:
		return fail(case, "expected 4 farm fence rails, found %d" % rails)
	return succeeded(case, "%d posts, %d rails - perimeter closed" % [posts, rails])


## The Ground body's trimesh collider, or null when it has none.
func _trimesh_of(node: Node) -> ConcavePolygonShape3D:
	if node == null:
		return null
	for child in node.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is ConcavePolygonShape3D:
			return shape.shape
	return null


## Highest `y` covered by any box collider on a node, or NAN when it has none.
func _top_of(node: Node) -> float:
	if node == null:
		return NAN
	var top := -INF
	for child in node.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			top = maxf(top, shape.position.y + (shape.shape as BoxShape3D).size.y * 0.5)
	return top if top > -INF else NAN