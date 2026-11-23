extends SceneTree
## W4.1: dump bones, skins and embedded animations of every KayKit rig.
##   Godot --headless --path . --script res://tools/probe_rig.gd
## Ground truth for the anime-route decision — never guess at a skeleton.

const DIR := "res://assets/models/kaykit/Characters/"


func _initialize() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		printerr("[probe_rig] no character directory")
		quit(1)
		return
	for entry: String in dir.get_files():
		if not entry.ends_with(".fbx") and not entry.ends_with(".glb"):
			continue
		var packed := ResourceLoader.load(DIR + entry) as PackedScene
		if packed == null:
			printerr("[probe_rig] cannot load %s" % entry)
			continue
		var inst: Node = packed.instantiate()
		var counts := {"bones": 0, "skins": 0, "meshes": 0}
		var anims: Array[String] = []
		var root_node: Node3D = inst as Node3D
		if root_node == null:
			printerr("[probe_rig] %s is not Node3D" % entry)
			inst.free()
			continue
		_walk(inst, counts, anims)
		if inst is AnimationPlayer:
			anims.append_array((inst as AnimationPlayer).get_animation_list())
		print("[probe_rig] %s: bones=%d skins=%d meshes=%d embedded_anims=%d scale=%s" % [
			entry, int(counts["bones"]), int(counts["skins"]), int(counts["meshes"]),
			anims.size(), str(root_node.scale),
		])
		if entry == "Knight.fbx" and anims.size() > 0:
			anims.sort()
			print("[probe_rig] all clips: %s" % ", ".join(anims))
		inst.free()
	quit(0)


func _walk(node: Node, counts: Dictionary, anims: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is Skeleton3D:
			counts["bones"] = int(counts["bones"]) + (child as Skeleton3D).get_bone_count()
		if child is MeshInstance3D:
			counts["meshes"] = int(counts["meshes"]) + 1
			if (child as MeshInstance3D).skin != null:
				counts["skins"] = int(counts["skins"]) + 1
		if child is AnimationPlayer:
			for name: StringName in (child as AnimationPlayer).get_animation_list():
				anims.append(String(name))
		_walk(child, counts, anims)
