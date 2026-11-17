extends TestSuite
## The bright-shonen character treatment: original anime faces over the CC0
## rigs, and cel-shaded materials on the characters only.
##
## A missing face plane is invisible in a headless test but obvious to a player;
## a face texture shared by all six villagers would make the cast feel cloned;
## and a toon setting applied to the *world* by accident would change every
## barn. These cases pin all three.

const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"

var _rig: Node3D = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"every_villager_has_an_anime_face",
		&"each_face_is_drawn_and_distinct",
		&"characters_are_cel_shaded",
	]


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"every_villager_has_an_anime_face":
			return await _t_faces_present()
		&"each_face_is_drawn_and_distinct":
			return _t_faces_distinct()
		&"characters_are_cel_shaded":
			return await _t_toon()
	return fail(case, "no case implementation for %s" % case)


func _t_faces_present() -> Dictionary:
	var c := &"every_villager_has_an_anime_face"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var bad: Array[String] = []
	for npc: Npc in built["manager"].call("npcs"):
		var holder := _find_named(npc, "AnimeFace")
		if holder == null or not holder is BoneAttachment3D:
			bad.append("%s has no face attachment" % npc.data.id)
			continue
		if (holder as BoneAttachment3D).bone_name != &"head":
			bad.append("%s face is not on the head" % npc.data.id)
		var quad := holder.get_node_or_null(^"FacePlane") as MeshInstance3D
		if quad == null:
			bad.append("%s has no face plane" % npc.data.id)
			continue
		var mat := quad.material_override as StandardMaterial3D
		if mat == null or mat.albedo_texture == null:
			bad.append("%s face has no texture" % npc.data.id)
	return check_equals(c, bad, [] as Array[String])


func _t_faces_distinct() -> Dictionary:
	var c := &"each_face_is_drawn_and_distinct"
	var images: Dictionary = {}
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		var texture := AnimeFace.texture_for(data.id)
		if texture == null:
			bad.append("%s has no face texture" % data.id)
			continue
		var image := texture.get_image()
		var painted := 0
		for y: int in range(0, image.get_height(), 4):
			for x: int in range(0, image.get_width(), 4):
				if image.get_pixel(x, y).a > 0.5:
					painted += 1
		if painted < 20:
			bad.append("%s face is blank (%d painted samples)" % [data.id, painted])
		var bytes := image.get_data()
		for other: StringName in images:
			if images[other] == bytes:
				bad.append("%s and %s share a face" % [data.id, other])
		images[data.id] = bytes
	return check_equals(c, bad, [] as Array[String])


func _t_toon() -> Dictionary:
	var c := &"characters_are_cel_shaded"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var checked := 0
	var bad: Array[String] = []
	for npc: Npc in built["manager"].call("npcs"):
		var model := npc.get_node_or_null(^"Model")
		if model == null:
			continue
		for mesh: Node in _meshes(model):
			# The anime face is deliberately unshaded so the drawn eyes keep
			# their ink; it is asserted in the face cases instead.
			if mesh.name == "FacePlane":
				continue
			var mat := (mesh as MeshInstance3D).material_override as StandardMaterial3D
			if mat == null:
				continue
			checked += 1
			if mat.diffuse_mode != AnimeStyle.TOON_DIFFUSE:
				bad.append("%s/%s is not toon-shaded (%d)" % [
					npc.data.id, mesh.name, mat.diffuse_mode,
				])
			if not mat.rim_enabled:
				bad.append("%s/%s has no inked rim" % [npc.data.id, mesh.name])
	if checked < 6:
		return fail(c, "only %d character materials were checked" % checked)
	return check_equals(c, bad, [] as Array[String])


# --- Fixtures -----------------------------------------------------------------


func _build_cast() -> Dictionary:
	_reset_rig()
	var script := load(NPC_MANAGER_SCRIPT) as GDScript
	if script == null:
		return {}
	_ensure_rig()
	var manager: NpcManager = script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	await _step(3)
	return {"manager": manager}


func _meshes(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_meshes(child))
	return out


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "AnimeTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
