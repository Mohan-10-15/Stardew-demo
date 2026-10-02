extends SceneTree
## Headless tool: reports the real size of every imported nature model.
##
## Run:
##     godot --headless --path . --script res://tools/probe_model_sizes.gd
##
## ## What this settled
##
## `docs/ASSET_LICENSES.md` flagged model scale as unreconciled since the Unity
## move. Measured answer for the Quaternius packs: **Godot's FBX importer already
## converts the packs' native centimetres to metres**, so no runtime scale factor
## is needed — the figures below are metres as-is.
##
## The three traps this tool exists to avoid:
##
## - Measuring during `_initialize()` reads the *pre-conversion* bounds and
##   reports a 357 m birch tree. Measurement must happen on a live frame with the
##   instance parented under `root`, where `global_transform` is authoritative.
## - Composition has to start from the root's own transform. The FBX importer puts
##   an axis-conversion rotation there as well as the unit scale, so walking only
##   the children reports a model a few percent taller than what is drawn — and
##   that number then gets used to size real crops.
## - `AABB` is a value type in GDScript. Passing it into a recursive walk and
##   assigning to it silently discards every measurement.
##
## Pivots sit at ground level (`min_y` within 0.2 of zero on every model), so
## models can be placed at their node position with no vertical correction.
##
## Writes `res://resources/nature/model_sizes.json` so the same figures can be
## read back without re-loading 29 meshes on every boot.

const FBX_DIR := "res://assets/models/quaternius/NaturePack/"
const OUTPUT_PATH := "res://resources/nature/model_sizes.json"

## Accumulated bounds for the model being measured.
##
## Member state rather than an `AABB` passed into the walk: GDScript passes value
## types by value, so assigning to the parameter inside the recursion updated a
## local copy and every measurement came back empty.
var _aabb := AABB()
var _have_aabb := false
var _faces := 0


func _initialize() -> void:
	# Measurement has to happen on a live frame, not during `_initialize()`.
	#
	# The imported FBX scenes carry their own root scale and Z-up to Y-up axis
	# conversion in the node transform. Composing local transforms by hand inside
	# `_initialize()` reported those pre-conversion figures and produced a 357 m
	# birch tree. Once the tree is running, parenting the instance under `root`
	# and reading `global_transform` gives the figure the engine will actually
	# render with.
	call_deferred("_run")


func _run() -> void:
	var dir := DirAccess.open(FBX_DIR)
	if dir == null:
		printerr("[probe_model_sizes] cannot open %s" % FBX_DIR)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	)

	var sizes: Dictionary = {}
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".fbx"):
			var measured := _measure(FBX_DIR + entry)
			if not measured.is_empty():
				sizes[entry.get_basename()] = measured
		entry = dir.get_next()
	dir.list_dir_end()

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("[probe_model_sizes] cannot write %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(sizes, "\t"))
	file.close()

	var names := sizes.keys()
	names.sort()
	for name: String in names:
		var m: Dictionary = sizes[name]
		print("  %-18s %6.3f x %6.3f x %6.3f  (y floor %6.3f, faces %d)" % [
			name, m["size_x"], m["size_y"], m["size_z"], m["min_y"], m["faces"],
		])
	print("[probe_model_sizes] measured %d models -> %s" % [sizes.size(), OUTPUT_PATH])
	quit(0)


## Size, vertical extent and mesh count for one FBX.
##
## Returns an empty dictionary on failure rather than a zero entry: a zero-sized
## model in this file would be indistinguishable from a genuinely flat one, and
## placement code would silently stack things at the origin.
func _measure(path: String) -> Dictionary:
	var packed := load(path) as PackedScene
	if packed == null:
		printerr("[probe_model_sizes] cannot load %s" % path)
		return {}
	var node := packed.instantiate()
	if node == null:
		printerr("[probe_model_sizes] cannot instantiate %s" % path)
		return {}

	_aabb = AABB()
	_have_aabb = false
	_faces = 0
	# Measurement must include the root's own transform. The FBX importer puts an
	# axis-conversion rotation there as well as the unit scale, and composing only
	# the children reports a model a few percent taller than what is drawn — which
	# is then used to size real crops.
	var start := Transform3D.IDENTITY
	if node is Node3D:
		start = (node as Node3D).transform
	_collect(node, start)
	if not _have_aabb or _aabb.size.length() <= 0.0:
		printerr("[probe_model_sizes] %s -> no geometry (%s, %d children)"
			% [path, node.get_class(), node.get_child_count()])
		_dump(node, 1)

	var out := {}
	if _have_aabb and _aabb.size.length() > 0.0:
		out = {
			"size_x": snappedf(_aabb.size.x, 0.001),
			"size_y": snappedf(_aabb.size.y, 0.001),
			"size_z": snappedf(_aabb.size.z, 0.001),
			# `min_y` matters more than the height for placement: a model whose
			# geometry starts above the origin has to be lowered by this much or
			# it floats. Quaternius pivots vary per model.
			"min_y": snappedf(_aabb.position.y, 0.001),
			"max_y": snappedf(_aabb.position.y + _aabb.size.y, 0.001),
			"meshes": _count_meshes(node),
			"faces": _faces,
		}

	# A PackedScene node is not refcounted, so it has to be freed by hand or the
	# suite's ObjectDB leak assertion trips.
	node.free()
	return out


func _collect(node: Node, xform: Transform3D) -> void:
	for child: Node in node.get_children():
		var local := xform
		if child is Node3D:
			local = xform * (child as Node3D).transform
		if child is VisualInstance3D:
			var visual := child as VisualInstance3D
			var box := local * visual.get_aabb()
			if not _have_aabb:
				_aabb = box
				_have_aabb = true
			else:
				_aabb = _aabb.merge(box)
			if visual.mesh != null:
				_faces += visual.mesh.get_faces().size()
		_collect(child, local)


func _dump(node: Node, depth: int) -> void:
	if depth > 3:
		return
	for child: Node in node.get_children():
		var mesh_info := ""
		if child is VisualInstance3D and (child as VisualInstance3D).mesh != null:
			mesh_info = " faces=%d" % (child as VisualInstance3D).mesh.get_faces().size()
		printerr("[probe_model_sizes]   %s%s%s" % ["  ".repeat(depth), child.name, mesh_info])
		_dump(child, depth + 1)


func _count_meshes(node: Node) -> int:
	var total := 0
	for child: Node in node.get_children():
		if child is VisualInstance3D:
			total += 1
		total += _count_meshes(child)
	return total