class_name CropArt
extends RefCounted
## Instantiates the CC0 plant models and measures them, so a soil tile can draw a
## real crop instead of a coloured cylinder without guessing at scale.
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

## Cached root [member Node3D.scale] as the importer set it, per model path.
##
## A rescale has to *compose* with this rather than replace it, because the
## centimetre-to-metre conversion the importer performs lives here.
static var _root_scales: Dictionary = {}

## Running maximum height while walking one model. Member state rather than a
## returned value because `float` cannot be accumulated out of a recursive walk
## any other way, and [AABB] must not be passed by value for the same reason the
## measurement tool documents.
static var _top_y: float = -INF


## The imported scene for [param path], or `null` if it cannot be loaded.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scenes.has(path):
		return _scenes[path]
	var packed := load(path) as PackedScene
	_scenes[path] = packed
	if packed == null:
		printerr("[CropArt] cannot load crop model %s" % path)
	return packed


## Whether [param path] names a model that will actually load.
##
## Used by the content tests, so a bad path in a crop `.tres` fails the suite
## rather than showing up as an empty field.
static func can_load(path: String) -> bool:
	return scene(path) != null


## How tall the model at [param path] stands, in metres, as imported.
##
## The highest point of the geometry, composed through the node hierarchy, which
## is what makes this agree with what the renderer draws rather than with the raw
## mesh bounds. Returns 0.0 for a path that will not load, and callers treat that
## as "leave the model at native size".
static func natural_height(path: String) -> float:
	if _heights.has(path):
		return _heights[path]
	var packed := scene(path)
	if packed == null:
		_heights[path] = 0.0
		return 0.0

	var node := packed.instantiate()
	if node == null:
		_heights[path] = 0.0
		return 0.0

	_top_y = -INF
	# Seed the walk with the root's own transform. Starting from identity and only
	# composing the *children* misses a scale set on the root, which is precisely
	# where the FBX importer puts the centimetre-to-metre conversion — and misses
	# the scale [SoilTile] applies when it resizes a model for a tile. Either way
	# the measurement comes back at the wrong size.
	var start := Transform3D.IDENTITY
	if node is Node3D:
		start = (node as Node3D).transform
	_walk(node, start)
	# A PackedScene node is not refcounted, so it has to be freed by hand or the
	# suite's ObjectDB leak assertion trips.
	node.free()

	# `-INF` means the model has no geometry at all. Clamped to 0.0 so a caller
	# dividing by it gets a defined answer, and the caller checks for zero.
	var measured := 0.0 if _top_y == -INF else maxf(_top_y, 0.0)
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
		printerr("[CropArt] %s is not a Node3D scene" % path)
		return null
	if target_height > 0.0:
		var natural := natural_height(path)
		if natural > 0.0:
			node.scale = node.scale * (target_height / natural)
	return node


## Records the topmost geometry height reached so far under [param xform].
static func _walk(node: Node, xform: Transform3D) -> void:
	for child: Node in node.get_children():
		var local := xform
		if child is Node3D:
			local = xform * (child as Node3D).transform
		if child is VisualInstance3D:
			var box := local * (child as VisualInstance3D).get_aabb()
			_top_y = maxf(_top_y, box.position.y + box.size.y)
		_walk(child, local)


## Drops the caches. Only for tests that assert on cache behaviour or that need a
## model re-measured after changing an import setting.
static func clear_cache() -> void:
	_scenes.clear()
	_heights.clear()
	_root_scales.clear()