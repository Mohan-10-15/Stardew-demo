extends SceneTree
## Where the face sits on each KayKit rig, in head-bone local space. The anime
## overlay has to cover the existing painted face without floating in front of
## it, so these numbers are measured from the imported scene, not guessed.

const CHARACTER_DIR := "res://assets/models/kaykit/Characters/"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for name: String in ["Rogue.fbx", "Knight.fbx", "Mage.fbx", "Barbarian.fbx", "RogueHooded.fbx"]:
		var packed := load(CHARACTER_DIR + name) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		var skeleton := _find_skeleton(node)
		if skeleton == null:
			continue
		var head := skeleton.find_bone(&"head")
		var pose := skeleton.get_bone_global_pose(head)
		print("--- %s head pose origin=%s basis.x=%s basis.y=%s basis.z=%s" % [
			name, _v(pose.origin), _v(pose.basis.x), _v(pose.basis.y), _v(pose.basis.z),
		])
		_walk(node, name)
		node.free()
	quit(0)


func _walk(node: Node, label: String) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			var n := String(mesh.name)
			if n.ends_with("_Head") or n.ends_with("_Hat") or n.ends_with("_Helmet"):
				var box := mesh.get_aabb()
				print("    %s %s pos=%s size=%s" % [
					label, n, _v(box.position), _v(box.size),
				])
		_walk(child, label)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
