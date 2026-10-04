class_name DecorationField
extends Node3D
## Scatters the valley's scenery: the bushes, tufts, flowers, logs and stumps that are
## not gameplay.
##
## ## Why the valley looked empty
##
## 150 gatherables over 220m is a wood, a field and a pond with nothing between them.
## The eye reads the gap as unfinished rather than as open ground, because open ground
## in a real place is *not uniform*: it has tufts, bare patches, a fallen log nobody
## will ever reach, a weed by the fence. None of that is interactive, and all of it is
## the difference between a map with objects on it and a place.
##
## ## Why these are not [ResourceNode]s
##
## Because scenery that accidentally becomes harvestable reaches a player's inventory.
## See [DecorationData].
##
## ## Determinism
##
## One seeded generator, consumed in [DecorationRegistry.scatterable_decorations]
## order, which is sorted by id. Every rotation and scale comes out of the same stream,
## so two worlds built from the same seed are identical, and the placement can be
## asserted on in a test at all.
##
## ## Batching
##
## Anything flagged [member DecorationData.batched] goes into a single
## [MultiMeshInstance3D] instead of one node per instance. Grass and flowers are
## numerous, small and walk-through-able, which is exactly the case where a few hundred
## individual nodes cost frames and nothing else.

@export var seed_value: int = 20251004
## Gatherables already placed, so scenery does not grow through a tree. Read from the
## sibling [ResourceField] when present.
@export var resource_field_path: NodePath = ^"../ResourceField"

## One batch per decoration, keyed by id, so a test can find a kind by name.
var _batches: Dictionary = {}
var _placed: int = 0
var _skipped_reserved: int = 0
var _skipped_spacing: int = 0


func _ready() -> void:
	build()


## Builds every scatterable decoration. Safe to call twice: the second call clears the
## previous result first, so a test that builds two fields does not accumulate.
func build() -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var occupied := _occupied_points()
	for data: DecorationData in DecorationRegistry.scatterable_decorations():
		_scatter(data, rng, occupied)
	Log.info("DecorationField", "scattered %d decorations (%d reserved, %d too close)" % [
		_placed, _skipped_reserved, _skipped_spacing,
	])


func _clear() -> void:
	# Taken out of the tree before being freed, not merely queue-freed. A deferred free
	# leaves the old props parented and still holding their names, so a rebuild in the
	# same frame has its new props collide with them and come out as "@StaticBody3D@9".
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_batches.clear()
	_placed = 0
	_skipped_reserved = 0
	_skipped_spacing = 0


func _scatter(data: DecorationData, rng: RandomNumberGenerator, occupied: Array[Vector2]) -> void:
	var model := ModelArt.scene(data.model)
	if model == null:
		Log.warn("DecorationField", "%s: cannot load %s" % [data.id, data.model])
		return
	var placed := 0
	# Bounded, like the gatherable scatter: a keep-out that covers a whole region would
	# otherwise hang the boot.
	var attempts: int = data.spawn_count * 12
	var transforms: Array[Transform3D] = []
	for _i: int in range(attempts):
		if placed >= data.spawn_count:
			break
		var angle := rng.randf() * TAU
		# Sqrt, not a uniform radius: a uniform draw clusters everything in the middle
		# and leaves the edge bare, which reads as a ring rather than as a meadow.
		var radius := sqrt(rng.randf()) * data.spawn_radius
		if data.spawn_inner_radius > 0.0:
			# Area-uniform in the annulus, so a ring of reeds is evenly spaced along the
			# shore rather than bunched on the outside of it.
			radius = lerpf(data.spawn_inner_radius, data.spawn_radius, sqrt(rng.randf()))
		var candidate := data.spawn_region + Vector2(cos(angle), sin(angle)) * radius
		if WorldBuilder.is_reserved(candidate):
			_skipped_reserved += 1
			continue
		if _too_close(candidate, occupied, data.spawn_spacing):
			_skipped_spacing += 1
			continue
		var xform := _transform_for(data, candidate, rng, data.batched)
		if data.batched:
			transforms.append(xform)
		else:
			var node := _instance(data, model, xform)
			# Numbered up front, because Godot does not salvage a colliding name: add a
			# second "thicket_body" and the tree grows a sibling called
			# "@StaticBody3D@7", so the readable name is lost on every prop after the
			# first. Two consequences: the remote scene tree is useless for telling
			# thickets from brambles, and nothing can count them. Naming them
			# "thicket_007" keeps both.
			node.name = "%s_%03d" % [data.id, placed]
			_finish(node, self)
		# Only a definition that *reserves* space goes on the list. Ground cover
		# scattered with a spacing of zero is lying on the grass and cannot obstruct a
		# willow — but registering it anyway meant 260 grass tufts were standing in the
		# occupancy list when the willows were placed, and every willow placement was
		# rejected as "too close to a blade of grass". That is how "willow: placed 0
		# of 6" happened.
		if data.spawn_spacing > 0.0:
			occupied.append(candidate)
		placed += 1
	if data.batched and not transforms.is_empty():
		var batch := _build_batch(data, model, transforms)
		_finish(batch, self)
		_batches[data.id] = batch
	if placed < data.spawn_count:
		Log.info("DecorationField", "%s: placed %d of %d" % [data.id, placed, data.spawn_count])
	_placed += placed


## A prop's transform: on the terrain, facing a random way, at a slightly varied size.
##
## [param fold_root_scale] exists because the two paths get the importer's root scale by
## different means. A non-batched prop gets it for free: [method ModelArt.instantiate]
## returns the imported node with that scale still on it, so folding it in *again* here
## squares it and every unbatched tree comes out 100x too big. A [MultiMesh] has one mesh
## and no hierarchy to carry it, so the batch has to fold it in — which is the whole
## reason the model cannot simply be pulled out of the imported scene and dropped in.
func _transform_for(data: DecorationData, at: Vector2, rng: RandomNumberGenerator, fold_root_scale: bool) -> Transform3D:
	var height := WorldBuilder.terrain_height(at.x, at.y)
	var yaw := rng.randf() * TAU
	var scale_factor := 1.0
	if not is_equal_approx(data.scale_jitter, 1.0):
		scale_factor = 1.0 + rng.randf_range(-1.0, 1.0) * (data.scale_jitter - 1.0)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
	var draw_height := data.draw_height()
	if draw_height > 0.0 and data.target_height > 0.0:
		basis = basis.scaled(Vector3.ONE * (data.target_height / maxf(ModelArt.natural_height(data.model), 0.001)))
	if fold_root_scale:
		basis = basis.scaled(ModelArt.root_scale(data.model))
	return Transform3D(basis, Vector3(at.x, height, at.y))


## One node for one prop, with a collider only if the definition asks for one.
func _instance(data: DecorationData, model: PackedScene, xform: Transform3D) -> Node3D:
	var holder: Node3D
	if data.collides:
		holder = StaticBody3D.new()
		holder.name = "%s_body" % data.id
		(holder as StaticBody3D).collision_layer = 1
		(holder as StaticBody3D).collision_mask = 0
	else:
		holder = Node3D.new()
		holder.name = "%s_prop" % data.id
	holder.transform = xform

	var visual := ModelArt.instantiate(data.model, data.target_height)
	if visual != null:
		visual.name = "Visual"
		holder.add_child(visual)
		if not ModelArt.is_white(data.model_tint):
			ModelArt.apply_tint(visual, data.model_tint)
		for geometry: Node in _geometries(visual):
			var instance := geometry as GeometryInstance3D
			instance.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if data.casts_shadow
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)

	if data.collides:
		_add_collider(holder as StaticBody3D, data)
	return holder


## A capsule sized from the model's own measured footprint, not from a number typed
## into a `.tres` and never revisited.
func _add_collider(body: StaticBody3D, data: DecorationData) -> void:
	var box := ModelArt.natural_aabb(data.model)
	var radius := maxf(box.size.x, box.size.z) * 0.5 * data.collider_radius_scale
	var height := maxf(box.size.y, 0.2)
	if radius <= 0.01:
		return
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	# A capsule's cylinder is its height minus both caps, so the total must be built
	# from the radius or the prop is shorter than its artwork by two radii.
	shape.height = maxf(height, radius * 2.0)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position = Vector3(0, height * 0.5, 0)
	body.add_child(collision)


## One [MultiMeshInstance3D] for every instance of one decoration.
func _build_batch(data: DecorationData, model: PackedScene, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = "%s_batch" % data.id
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh_from(model, data.id)
	multimesh.instance_count = transforms.size()
	# `use_colors` would let one batch carry several tints; there is one tint per
	# definition, so the material carries it instead and the buffer stays smaller.
	for i: int in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	node.multimesh = multimesh
	if not ModelArt.is_white(data.model_tint):
		ModelArt.apply_tint(node, data.model_tint)
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if data.casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return node


## The mesh inside an imported model, with the importer's own scale baked into the
## transforms.
##
## A [MultiMesh] has one mesh and cannot carry the importer's node hierarchy, so the
## root scale the FBX importer applied for centimetre-to-metre conversion has to be
## folded into each instance transform here or the batch draws at 1/100th size.
func _mesh_from(model: PackedScene, id: StringName) -> Mesh:
	var node := model.instantiate()
	if node == null:
		return null
	var mesh: Mesh = null
	var found := 0
	for child: Node in _geometries(node):
		if child is MeshInstance3D:
			found += 1
			if mesh == null:
				mesh = (child as MeshInstance3D).mesh
	if found > 1:
		# A batch can only hold one mesh, and every model in this library happens to
		# have exactly one. That is an accident of the asset pack, not a guarantee, and
		# silently dropping the rest would produce scenery that is missing limbs.
		Log.warn("DecorationField", "%s has %d meshes; the batch draws only the first" % [id, found])
	node.free()
	return mesh


## Where the gatherables already are, so scenery does not grow through a tree.
func _occupied_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var field := get_node_or_null(resource_field_path)
	if field == null or not (field is ResourceField):
		return out
	for node: ResourceNode in (field as ResourceField).nodes:
		out.append(Vector2(node.position.x, node.position.z))
	return out


## Whether anything already placed is within [param spacing] of [param pos].
##
## Against everything, not only same-kind ones: a bush inside a tree is the same visual
## bug as two bushes inside each other.
func _too_close(pos: Vector2, occupied: Array[Vector2], spacing: float) -> bool:
	if spacing <= 0.0:
		return false
	for other: Vector2 in occupied:
		if pos.distance_to(other) < spacing:
			return true
	return false


## Every [GeometryInstance3D] under a node, at any depth.
static func _geometries(from: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if from == null:
		return out
	if from is GeometryInstance3D:
		out.append(from as GeometryInstance3D)
	for child: Node in from.get_children():
		out.append_array(_geometries(child))
	return out


## Parents a node and marks it for serialisation. [method Node.add_child] has to happen
## first, because `owner` must already be an ancestor.
static func _finish(node: Node, root: Node) -> void:
	root.add_child(node)
	node.owner = root


## How many props were placed, for the playtest and for a test that counts them.
func placed_count() -> int:
	return _placed


## The batch node for one decoration, or null if that decoration is not batched.
func batch(id: StringName) -> MultiMeshInstance3D:
	return _batches.get(id) as MultiMeshInstance3D