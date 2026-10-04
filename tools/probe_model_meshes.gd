extends SceneTree
## Headless tool: lists every mesh inside each imported model, with its measured size.
##
## Run:
##     godot --headless --path . --script res://tools/probe_model_meshes.gd [res://path.fbx ...]
##
## Written because a model file is not what its name says it is. `Rogue.fbx` is one
## character and *five weapons* — a 1H crossbow, a 2H crossbow, two knives and a
## throwable, all parented to the same imported root. Instancing it whole gives every
## villager a crossbow, gives the merged bounding box a 4.1m width, and quietly ruins
## the ground offset computed from it. Nothing warns; the scene loads and the character
## renders.
##
## With no arguments it walks the two asset roots this project draws from.

## With no arguments it walks the whole `assets/models` tree.


func _initialize() -> void:
	var paths: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		paths.append(argument)
	if paths.is_empty():
		paths = _discover("res://assets/models")
	if paths.is_empty():
		printerr("[probe_model_meshes] no models found")
		quit(1)
		return
	for path: String in paths:
		_report(path)
	quit(0)


func _discover(from: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(from)
	if dir == null:
		print("   (cannot list %s)" % from)
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			# Skipping "." and "..": recursing into them is harmless but noisy.
			if entry != "." and entry != "..":
				out.append_array(_discover("%s/%s" % [from, entry]))
		elif entry.ends_with(".fbx"):
			out.append("%s/%s" % [from, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _report(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("%s: DOES NOT LOAD" % path)
		return
	var node := packed.instantiate()
	if node == null:
		print("%s: not instantiable" % path)
		return
	var stem := path.get_file().get_basename()
	var named := 0
	var unnamed: Array[String] = []
	var rows: Array[String] = []
	for mesh: MeshInstance3D in _meshes(node):
		var own := String(mesh.name)
		if own.begins_with("%s_" % stem):
			named += 1
		else:
			unnamed.append(own)
		rows.append("      %-26s size=%-30s skin=%-5s skinned_by=%s" % [
			own, str(mesh.get_aabb().size), str(mesh.skin != null), _skin_path(mesh),
		])
	print("%s  (%d meshes, %d prefixed '%s_')" % [path.get_file(), named + unnamed.size(), named, stem])
	for row: String in rows:
		print(row)
	if not unnamed.is_empty():
		print("      NOT part of '%s': %s" % [stem, ", ".join(unnamed)])
	print("      measured height=%.3f" % ModelArt.natural_height(path))
	node.free()


## The [Skeleton3D] a mesh is skinned to, by name, or "-" when it is not skinned.
##
## The question this exists to answer: in this pack a character and its weapons are both
## parented under one imported root, and the weapons are loose meshes while the character
## is skinned to a skeleton. If that holds it is a better rule than any name convention —
## `RogueHooded.fbx` reuses `Rogue_*` for every one of its parts, so a prefix rule empties
## it out entirely.
static func _skin_path(mesh: MeshInstance3D) -> String:
	if mesh.skin == null:
		return "-"
	var owner: Node = mesh.skin.get_parent()
	return "-" if owner == null else String(owner.name)


static func _meshes(from: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if from == null:
		return out
	if from is MeshInstance3D:
		out.append(from as MeshInstance3D)
	for child: Node in from.get_children():
		out.append_array(_meshes(child))
	return out