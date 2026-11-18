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
		&"mood_textures_are_drawn_and_distinct",
		&"the_face_reacts_and_blinks",
		&"dialogue_lines_drive_the_face",
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
		&"mood_textures_are_drawn_and_distinct":
			return _t_moods()
		&"the_face_reacts_and_blinks":
			return await _t_reactions()
		&"dialogue_lines_drive_the_face":
			return await _t_dialogue_mood()
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
	var outlines := 0
	var bad: Array[String] = []
	for npc: Npc in built["manager"].call("npcs"):
		var model := npc.get_node_or_null(^"Model")
		if model == null:
			continue
		for mesh: Node in _meshes(model):
			# The face keeps its drawn ink and the outlines are deliberately
			# unshaded black; both are asserted elsewhere.
			if mesh.name == "FacePlane" or mesh.name.begins_with("Outline_") \
					or mesh.name.begins_with("EyeGlint") or mesh.name == "Ahoge":
				if mesh.name.begins_with("Outline_"):
					outlines += 1
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
	if outlines < 6:
		return fail(c, "only %d inverted-hull outlines were added" % outlines)
	return check_equals(c, bad, [] as Array[String])


## Five moods, five drawn faces. A shared texture would mean a sad gift and a
## happy one look identical, which is the exact failure AGENTS.md forbids for
## every other interact-style action.
func _t_moods() -> Dictionary:
	var c := &"mood_textures_are_drawn_and_distinct"
	var seen: Dictionary = {}
	var bad: Array[String] = []
	for mood: StringName in AnimeFace.MOODS:
		var texture := AnimeFace.texture_for(&"mira", mood)
		var image := texture.get_image()
		var painted := 0
		for y: int in range(0, image.get_height(), 4):
			for x: int in range(0, image.get_width(), 4):
				if image.get_pixel(x, y).a > 0.5:
					painted += 1
		if painted < 20:
			bad.append("%s mood is blank" % mood)
		var bytes := image.get_data()
		for other: StringName in seen:
			if seen[other] == bytes:
				bad.append("%s and %s share a texture" % [mood, other])
		seen[mood] = bytes
	return check_equals(c, bad, [] as Array[String])


## A gift reaction changes the drawn face and then wears off; a villager also
## blinks on her own without any event at all.
func _t_reactions() -> Dictionary:
	var c := &"the_face_reacts_and_blinks"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var npc: Npc = built["manager"].call("get_npc", &"mira")
	if npc == null:
		return fail(c, "no Mira in the cast")
	npc.set_expression(&"happy", 0.4)
	if _face_texture(npc) != AnimeFace.texture_for(&"mira", &"happy"):
		return fail(c, "a happy expression did not reach the face plane")
	for _i: int in range(5):
		npc.call("_update_face", 0.1)
	if _face_texture(npc) != AnimeFace.texture_for(&"mira", &"neutral"):
		return fail(c, "the expression never returned to neutral")
	var blinked := false
	for _i: int in range(40):
		npc.call("_update_face", 0.1)
		if _face_texture(npc) == AnimeFace.texture_for(&"mira", &"blink"):
			blinked = true
			break
	if not blinked:
		return fail(c, "the villager never blinked")
	return succeeded(c, "the face smiled, recovered and blinked on its own")


## A written mood reaches the face through the dialogue service, with the
## service knowing nothing about faces — it only forwards the word to the cast.
func _t_dialogue_mood() -> Dictionary:
	var c := &"dialogue_lines_drive_the_face"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var script := load("res://scripts/dialogue/dialogue_service.gd") as GDScript
	if script == null:
		return fail(c, "no dialogue service script")
	var service: Node = script.new()
	service.name = "DialogueService"
	_rig.add_child(service)
	var manager: NpcManager = built["manager"]
	var npc: Npc = manager.call("get_npc", &"mira")
	manager.grant_hearts(&"mira", 2)
	# The unseen introduction outranks everything once; spend it, then the
	# two-heart line is the most specific match.
	for _i: int in range(2):
		service.call("open", &"mira")
		service.call("cancel")
	if not bool(service.call("open", &"mira")):
		return fail(c, "no line opened at two hearts")
	var entry: DialogueEntry = service.call("current_entry")
	if entry == null or entry.mood != &"happy":
		return fail(c, "the selected line has mood '%s'" % (
			str(entry.mood) if entry != null else "<none>"
		))
	if _face_texture(npc) != AnimeFace.texture_for(&"mira", &"happy"):
		return fail(c, "the written mood did not reach the face")
	service.call("cancel")
	return succeeded(c, "'%s' put a smile on Mira's face" % entry.id)


func _face_texture(npc: Npc) -> Texture2D:
	var holder := _find_named(npc, "AnimeFace")
	if holder == null:
		return null
	var quad := holder.get_node_or_null(^"FacePlane") as MeshInstance3D
	if quad == null:
		return null
	var mat := quad.material_override as StandardMaterial3D
	return mat.albedo_texture if mat != null else null


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
