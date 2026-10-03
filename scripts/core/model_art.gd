class_name ModelArt
extends RefCounted
## Instantiates the CC0 nature models and measures them, so a soil tile can draw a
## real crop and a rock can carry a collider sized to its own art, without either
## guessing at scale.
##
## Used to be `CropArt`, and was named for the only caller it had. A gatherable
## tree needs the same two things a crop does — a correctly scaled instance and a
## measurement — and re-implementing that in the gathering lane is how two
## definitions of "how big is this model" end up disagreeing. It lives in `core`
## because both [SoilTile] and the gathering nodes speak it, and `core` is what
## every other layer shares.
##
## ## Why this is not just `load(path).instantiate()` in [SoilTile]
##
## Two problems, both of which produce a silently wrong picture rather than an
## error:
##
## 1. **The importer's scale lives in the node transform.** Quaternius authors in
##    centimetres and Godot's FBX importer converts to metres by scaling nodes in
##    the imported scene. `Mesh.get_aabb()` on such a mesh reports the *pre-scale*
##    bounds — a `BirchTree_1` measures 0.017 units that way and 1.70 metres the
##    way the engine draws it. Pulling the bare mesh out of the imported scene and
##    dropping it into a tile therefore produces a model 100x too big. So the
##    whole imported scene is instanced and kept intact, and only a uniform scale
##    is applied on top.
## 2. **Every tile needs its own copy.** A `Node3D` cannot be shared between
##    tiles, so the cached thing is the [PackedScene] (a refcounted resource) and
##    each tile gets a fresh instance of it.
##
## Measurements are cached per path, so a field of 200 tiles loads and walks each
## distinct model exactly once.

## Cached [PackedScene] per model path. A failed load is cached as `null` too, so
## a typo in a `.tres` does not re-attempt the load on every repaint.
static var _scenes: Dictionary = {}

## Cached measured top height in metres per model path.
static var _heights: Dictionary = {}

## Cached measured bounds in metres per model path.
static var _aabbs: Dictionary = {}

## Cached root [member Node3D.scale] as the importer set it, per model path.
##
## A rescale has to *compose* with this rather than replace it, because the
## centimetre-to-metre conversion the importer performs lives here.
static var _root_scales: Dictionary = {}

## Running bounds accumulator while walking one model.
##
## Member state rather than a returned value because [AABB] is a value type in
## GDScript: passing one into a recursive walk and assigning to it discards the
## result silently, which is documented at length in `tools/probe_model_sizes.gd`.
static var _bounds: AABB = AABB()


## The imported scene for [param path], or `null` if it cannot be loaded.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scenes.has(path):
		return _scenes[path]
	var packed := load(path) as PackedScene
	_scenes[path] = packed
	if packed == null:
		printerr("[ModelArt] cannot load model %s" % path)
	return packed


## Whether [param path] names a model that will actually load.
##
## Used by the content tests, so a bad path in a crop `.tres` fails the suite
## rather than showing up as an empty field.
static func can_load(path: String) -> bool:
	return scene(path) != null


## The model's bounds in metres, as imported: an [AABB] whose `position` is the
## lowest corner and whose `size` is the drawn extent.
##
## One walk serves every measurement here, so asking for the bounds and the height
## costs the same single pass. A path that will not load, or a model with no
## geometry, reports an empty box at the origin rather than something arbitrary, and
## callers treat a zero size as "leave the model at native size".
##
## The gatherable nodes size their colliders from this, which is what keeps a rock's
## hitbox inside its own artwork instead of near the authored size somebody typed
## into a `.tres` and never revisited.
static func natural_aabb(path: String) -> AABB:
	if _aabbs.has(path):
		return _aabbs[path]
	_bounds = AABB()
	var packed := scene(path)
	if packed != null:
		var node := packed.instantiate()
		if node != null:
			# Seed the walk with the root's own transform. Starting from identity
			# and only composing the *children* misses a scale set on the root, which
			# is precisely where the FBX importer puts the centimetre-to-metre
			# conversion.
			var start := Transform3D.IDENTITY
			if node is Node3D:
				start = (node as Node3D).transform
			_walk(node, start)
			# A PackedScene node is not refcounted, so it has to be freed by hand.
			node.free()
	_aabbs[path] = _bounds
	return _bounds


## How tall the model at [param path] stands, in metres, as imported.
##
## The top of [method natural_aabb]'s box, which is what makes this agree with what
## the renderer draws rather than with the raw mesh bounds. Returns 0.0 for a path
## that will not load.
static func natural_height(path: String) -> float:
	if _heights.has(path):
		return _heights[path]
	var box := natural_aabb(path)
	var measured := maxf(box.position.y + box.size.y, 0.0)
	_heights[path] = measured
	return measured


## The root scale the FBX importer gave the model at [param path].
##
## Multiply this by a wanted/natural ratio to resize a model without losing the
## importer's unit conversion. Cached, and safe to call every frame.
static func root_scale(path: String) -> Vector3:
	if _root_scales.has(path):
		return _root_scales[path]
	var packed := scene(path)
	if packed == null:
		_root_scales[path] = Vector3.ONE
		return Vector3.ONE
	var probe := packed.instantiate() as Node3D
	if probe == null:
		_root_scales[path] = Vector3.ONE
		return Vector3.ONE
	var s := probe.scale
	probe.free()
	_root_scales[path] = s
	return s


## A fresh instance of the model at [param path] at its natural size.
##
## Pass a non-positive [param target_height] to get the model unscaled and resize
## it yourself with [method root_scale]; that is what [SoilTile] does, so a
## nightly growth repaint re-scales one node instead of rebuilding a scene.
##
## Returns `null` rather than an empty node when the path will not load, so the
## caller can fall back to the procedural plant instead of parenting nothing.
static func instantiate(path: String, target_height: float = 0.0) -> Node3D:
	var packed := scene(path)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		printerr("[ModelArt] %s is not a Node3D scene" % path)
		return null
	if target_height > 0.0:
		var natural := natural_height(path)
		if natural > 0.0:
			node.scale = node.scale * (target_height / natural)
	return node


## Folds the geometry under [param xform] into the running bounds.
static func _walk(node: Node, xform: Transform3D) -> void:
	for child: Node in node.get_children():
		var local := xform
		if child is Node3D:
			local = xform * (child as Node3D).transform
		if child is VisualInstance3D:
			var box := local * (child as VisualInstance3D).get_aabb()
			if _bounds.size == Vector3.ZERO:
				_bounds = box
			else:
				_bounds = _bounds.merge(box)
		_walk(child, local)


## Whether [param tint] would make a model look different.
##
## A content author leaving a tint blank means "no tint", and white is the default of
## every tint field in the project. Calling [method apply_tint] with it would still be
## *correct* — multiplying by one changes nothing — but it duplicates every material on
## the model to achieve that, so callers ask first. Both channels are compared because
## alpha is ignored: a fully transparent tint is a bug, not a request to hide the model.
static func is_white(tint: Color) -> bool:
	return is_equal_approx(tint.r, 1.0) and is_equal_approx(tint.g, 1.0) \
		and is_equal_approx(tint.b, 1.0)


## Multiplies every material's albedo under [param root] by [param tint].
##
## How one model becomes several: an iron vein is the same grey boulder in another
## colour, and a villager is one of five CC0 bodies recoloured.
##
## [member GeometryInstance3D.material_override] rather than editing the shared
## resource, because the same model is instanced many times over — one rock per
## boulder, one Knight per knight — and overwriting the shared material would tint
## every other instance in the valley at once. The per-surface duplicate is what
## makes tinting one instance cheap and local.
##
## A white tint is treated as "no tint" by the caller rather than here, because
## duplicating every material to multiply it by one is pure cost.
static func apply_tint(root: Node, tint: Color) -> void:
	if root == null:
		return
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			var geometry := child as GeometryInstance3D
			# `mesh.surface_get_material`, not something on the instance: the instance
			# holds no surfaces, it draws the ones its Mesh has.
			var source := geometry.material_override
			if source == null and geometry.mesh != null and geometry.mesh.get_surface_count() > 0:
				source = geometry.mesh.surface_get_material(0)
			if source is StandardMaterial3D:
				var copy := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				copy.albedo_color = (source as StandardMaterial3D).albedo_color * tint
				copy.resource_local_to_scene = true
				geometry.material_override = copy
		apply_tint(child, tint)


## Drops the caches. Only for tests that assert on cache behaviour or that need a
## model re-measured after changing an import setting.
static func clear_cache() -> void:
	_scenes.clear()
	_heights.clear()
	_aabbs.clear()
	_root_scales.clear()