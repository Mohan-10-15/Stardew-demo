extends SceneTree
## Where KayKit puts held props in the original rigs, and how big the standalone
## addons are. The transforms here are the ground truth for attaching signature
## gear to `handslot.r` in the game.
##
##     godot --headless --path . --script res://tools/probe_character_props.gd

const CHARACTER_DIR := "res://assets/models/kaykit/Characters/"
const ADDON_DIR := "res://assets/models/kaykit/Addons/"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== STANDALONE ADDON SIZES ===")
	var dir := DirAccess.open(ADDON_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.ends_with(".fbx"):
				var path := ADDON_DIR + entry
				var box := ModelArt.natural_aabb(path)
				print("%-30s size=%s min=%s" % [entry, _v(box.size), _v(box.position)])
			entry = dir.get_next()
		dir.list_dir_end()

	print("=== IN-RIG PROP TRANSFORMS ===")
	for name: String in ["Rogue.fbx", "Knight.fbx", "Mage.fbx", "Barbarian.fbx", "RogueHooded.fbx"]:
		var packed := load(CHARACTER_DIR + name) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		print("--- %s" % name)
		_walk(node, 0)
		# Attachment meshes are skinned children of the Skeleton3D, not siblings.
		_find_attachment_meshes(node, "")
		var skeleton := _find_skeleton(node)
		if skeleton != null:
			for bone_name: String in ["spine", "chest", "head", "upperarm.l", "upperarm.r", "upperleg.l", "upperleg.r", "lowerleg.l", "lowerleg.r", "handslot.r"]:
				var idx := skeleton.find_bone(bone_name)
				if idx < 0:
					continue
				var rest := skeleton.get_bone_rest(idx)
				var pose := skeleton.get_bone_global_pose(idx)
				print("    BONE %s rest origin=%s basis.x=%s basis.y=%s pose origin=%s" % [
					bone_name, _v(rest.origin), _v(rest.basis.x), _v(rest.basis.y),
					_v(pose.origin),
				])
		node.free()
	quit(0)


func _walk(node: Node, depth: int) -> void:
	for child: Node in node.get_children():
		var label := ""
		if child is MeshInstance3D:
			label = " MESH=%s" % (child as MeshInstance3D).name
		elif child is Skeleton3D:
			label = " SKELETON(%d bones)" % (child as Skeleton3D).get_bone_count()
		if child is Node3D:
			var n3 := child as Node3D
			label += " pos=%s rot=%s scale=%s" % [
				_v(n3.position), _v(n3.rotation_degrees), _v(n3.scale),
			]
		print("%s%s%s" % ["  ".repeat(depth), child.name, label])
		_walk(child, depth + 1)


func _find_attachment_meshes(node: Node, path: String) -> void:
	for child: Node in node.get_children():
		var here := "%s/%s" % [path, child.name]
		if ModelArt.is_attachment(child.name):
			var extra := ""
			if child is BoneAttachment3D:
				extra = " BONE=%s" % (child as BoneAttachment3D).bone_name
			print("    WRAPPER %s class=%s%s" % [here, child.get_class(), extra])
		if child is MeshInstance3D and ModelArt.is_attachment((child as MeshInstance3D).name):
			var mesh := child as MeshInstance3D
			print("    %s pos=%s rot=%s scale=%s" % [
				here, _v(mesh.position), _v(mesh.rotation_degrees), _v(mesh.scale),
			])
		_find_attachment_meshes(child, here)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
