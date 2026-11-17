extends SceneTree
## Headless probe for the CC0 art already in the repo.
##
## Run:
##     godot --headless --path . --script res://tools/probe_art_assets.gd
##
## Reports the real drawn bounds of the Quaternius buildings, the bone names of
## each KayKit character (where signature gear has to attach) and the mesh names
## of every addon. ModelArt composes the importer's root transform, which is the
## only way to get metres rather than pre-conversion centimetres.

const BUILDING_DIR := "res://assets/models/quaternius/FarmBuildings/"
const CHARACTER_DIR := "res://assets/models/kaykit/Characters/"
const ADDON_DIR := "res://assets/models/kaykit/Addons/"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== BUILDINGS ===")
	for path: String in _files(BUILDING_DIR):
		if not ModelArt.can_load(path):
			print("%s: FAILED TO LOAD" % path.get_file())
			continue
		var box := ModelArt.natural_aabb(path)
		print("%-20s size=%s min=%s max=%s" % [
			path.get_file(), _v(box.size), _v(box.position),
			_v(box.position + box.size),
		])

	print("=== CHARACTER BONES ===")
	for path: String in _files(CHARACTER_DIR):
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		var skeleton := _find_skeleton(node)
		var bones: Array[String] = []
		if skeleton != null:
			for i: int in skeleton.get_bone_count():
				bones.append(skeleton.get_bone_name(i))
		var box := ModelArt.body_aabb(path)
		print("%-18s height=%.3f bones=%s" % [
			path.get_file(), box.size.y, str(bones),
		])
		node.free()

	print("=== ADDON MESHES ===")
	for path: String in _files(ADDON_DIR):
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var probe := packed.instantiate()
		var names: Array[String] = []
		_mesh_names(probe, names)
		print("%-30s %s" % [path.get_file(), str(names)])
		probe.free()

	quit(0)


func _files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".fbx"):
			out.append(dir_path + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _mesh_names(node: Node, names: Array[String]) -> void:
	if node is MeshInstance3D:
		names.append((node as MeshInstance3D).name)
	for child: Node in node.get_children():
		_mesh_names(child, names)


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
