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
		&"gatherable_visual_and_collider_counts_match",
		&"gatherable_colliders_sit_on_their_own_model",
		&"no_decorative_trees_are_left_in_the_valley",
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


## The valley's gatherables.
func _field() -> ResourceField:
	return _find_field(_world)


static func _find_field(from: Node) -> ResourceField:
	if from == null:
		return null
	if from is ResourceField:
		return from as ResourceField
	for child: Node in from.get_children():
		var found := _find_field(child)
		if found != null:
			return found
	return null


## The children of [param node] sitting on [param layer].
static func _bodies_on(node: Node, layer: int) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child: Node in node.get_children():
		if child is StaticBody3D and (child as StaticBody3D).collision_layer == layer:
			out.append(child as StaticBody3D)
	return out


static func _shape_of(body: StaticBody3D) -> Shape3D:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).shape
	return null


## How many visible meshes [param node] draws while it is standing.
##
## Walked rather than counted on direct children, because an imported FBX is a
## [Node3D] root wrapping a [MeshInstance3D] — `ModelArt` keeps that root intact
## because the unit conversion lives on its scale, so a "direct children only" count
## reads zero on a perfectly good model. The first version of this case did exactly
## that and reported a broken valley for 145 correct nodes before failing on the
## first one it could not match.
##
## Inherited visibility is tracked rather than read off each instance, because
## `Node3D.visible` is local: a mesh under a hidden stump still says `visible == true`.
## That is what keeps a depleted tree counting as zero models instead of two.
static func _visual_count(node: Node, inherited_visible: bool = true) -> int:
	var count := 0
	var shown := inherited_visible
	if node is Node3D:
		shown = inherited_visible and (node as Node3D).visible
	if node is MeshInstance3D and shown:
		count += 1
	for child: Node in node.get_children():
		count += _visual_count(child, shown)
	return count


func _t_regions() -> Dictionary:
	var c := &"world_builds_expected_regions"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	for node_name: String in ["Ground", "Pond", "FarmSoil", "VillageWell", "NoticeBoard", "SupplyCrate"]:
		if world.get_node_or_null(NodePath(node_name)) == null:
			return fail(c, "missing region node '%s'" % node_name)
	return succeeded(c, "all regions present")


## One model, one solid collider, one aim volume, one component — per node.
##
## The old version of this case compared multimesh instance counts with capsule
## counts, because that was what the valley used to be made of. It could not survive
## the move to [ResourceField], and the naive port — "does the node have a collider?"
## — would have passed on a node with two, or on a forest with none. So the invariant
## is stated per node and checked on all four axes.
func _t_counts_match() -> Dictionary:
	var c := &"gatherable_visual_and_collider_counts_match"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var field := _field()
	if field == null:
		return fail(c, "world contains no ResourceField")
	if field.count() == 0:
		return fail(c, "ResourceField is empty; the valley has nothing to gather")

	var trees := 0
	for node: ResourceNode in field.nodes:
		if node.data != null and node.data.category == ResourceNodeData.Category.TREE:
			trees += 1
		if _visual_count(node) != 1:
			return fail(c, "%s draws %d models, expected exactly 1" % [
				node.name, _visual_count(node),
			])
		var solid := _bodies_on(node, PhysicsLayers.WORLD)
		if solid.size() != 1:
			return fail(c, "%s has %d solid bodies, expected 1" % [node.name, solid.size()])
		var aim := _bodies_on(node, PhysicsLayers.INTERACTABLE)
		if aim.size() != 1:
			return fail(c, "%s has %d aim volumes, expected 1" % [node.name, aim.size()])
		var components := 0
		for child: Node in aim[0].get_children():
			if child is Interactable:
				components += 1
		if components != 1:
			return fail(c, "%s has %d interaction components, expected 1" % [
				node.name, components,
			])
		if _shape_of(aim[0]) == null or _shape_of(solid[0]) == null:
			return fail(c, "%s has a body with no collision shape" % node.name)

	if trees == 0:
		return fail(c, "no trees were placed; the valley has no wood")
	return succeeded(c, "%d nodes (%d trees), each with 1 model, 1 solid, 1 aim" % [
		field.count(), trees,
	])


## Every collider stands on the artwork it belongs to.
##
## What the multimesh version had to *infer* — nearest-site matching, in case the two
## came from different random sequences — is structural now: a node's collider is its
## own child, so they cannot be placed independently. What is left to check is the
## part that can still go wrong silently, and did, when colliders were authored by
## hand: a collider that floats above the ground, one wider than the model it is
## meant to be, and one the aim volume does not cover.
func _t_colliders_aligned() -> Dictionary:
	var c := &"gatherable_colliders_sit_on_their_own_model"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var field := _field()
	if field == null:
		return fail(c, "world contains no ResourceField")

	for node: ResourceNode in field.nodes:
		if node.data == null:
			return fail(c, "%s has no definition" % node.name)
		if node.footprint() <= 0.0:
			return fail(c, "%s has no measurable model" % node.name)
		var solid := _bodies_on(node, PhysicsLayers.WORLD)[0]
		var aim := _bodies_on(node, PhysicsLayers.INTERACTABLE)[0]
		var solid_shape := _shape_of(solid) as CylinderShape3D
		var aim_shape := _shape_of(aim) as CylinderShape3D
		if solid_shape == null or aim_shape == null:
			return fail(c, "%s is not collider-shaped" % node.name)

		# On the ground, not sunk into it and not floating.
		if absf(solid.position.y) > 0.001:
			return fail(c, "%s solid sits at y=%.3f, expected the ground at 0" % [
				node.name, solid.position.y,
			])
		if solid_shape.height > node.height() + 0.001:
			return fail(c, "%s collider is %.2fm tall for a %.2fm model" % [
				node.name, solid_shape.height, node.height(),
			])
		# Inside the model, never wider than it.
		if solid_shape.radius > node.footprint() * 0.5 + 0.001:
			return fail(c, "%s collider is %.2fm wide for a %.2fm model" % [
				node.name, solid_shape.radius * 2.0, node.footprint(),
			])
		# Aimable. A solid the ray cannot reach is a tree the player can walk into
		# and not swing at.
		if aim_shape.radius < solid_shape.radius:
			return fail(c, "%s aim volume is narrower than its own collider" % node.name)
		if aim_shape.height + 0.001 < solid_shape.height:
			return fail(c, "%s aim volume is shorter than its own collider" % node.name)

		# And standing on the terrain, which for everything outside the pond is y=0.
		if node.position.y > 0.001:
			return fail(c, "%s was placed at y=%.3f" % [node.name, node.position.y])
	return succeeded(c, "all %d colliders sit on their own model" % field.count())


## Nothing in the valley is scenery pretending to be a tree.
##
## The specific regression [Group 12] fixed: a grove of cylinder-and-sphere trees the
## player could see and not touch. Cheap to assert, and it is the failure a player
## would report as "some trees don't work".
func _t_no_decorative_trees() -> Dictionary:
	var c := &"no_decorative_trees_are_left_in_the_valley"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	for legacy: String in ["ForestTrunks", "ForestCanopies"]:
		if world.get_node_or_null(NodePath(legacy)) != null:
			return fail(c, "%s still exists; it draws trees that cannot be gathered" % legacy)
	var field := _field()
	if field == null:
		return fail(c, "world contains no ResourceField")
	var trees := 0
	for node: ResourceNode in field.nodes:
		if node.data != null and node.data.category == ResourceNodeData.Category.TREE:
			trees += 1
	if trees == 0:
		return fail(c, "the valley has no trees at all")
	return succeeded(c, "%d gatherable trees, no decorative ones" % trees)


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
		&"gatherable_visual_and_collider_counts_match":
			return await _t_counts_match()
		&"gatherable_colliders_sit_on_their_own_model":
			return await _t_colliders_aligned()
		&"no_decorative_trees_are_left_in_the_valley":
			return await _t_no_decorative_trees()
		&"ground_supports_the_spawn_point":
			return await _t_ground_supports_spawn()
	return fail(case, "no case implementation for %s" % case)