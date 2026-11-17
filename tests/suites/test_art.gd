extends TestSuite
## The art pass: signature gear that makes six shared bodies read as six people,
## and CC0 buildings standing where the old primitive boxes used to be.
##
## ## Why this is tested at all
##
## A missing model is a silent empty hand, and a collider that disagrees with the
## art is a wall the player walks into three metres before the building they can
## see. Both pass every existing content check: the first is invisible, the second
## only shows up when a player walks at a barn. These cases ask the questions the
## renderer cannot answer for itself.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const BUILDING_DIR := "res://assets/models/quaternius/FarmBuildings/"

var _rig: Node3D = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"every_villager_has_a_signature_prop",
		&"the_signature_props_are_all_different",
		&"gear_attaches_to_the_right_hand",
		&"the_cottages_are_cc0_buildings",
		&"building_colliders_match_their_art",
		&"the_landmarks_are_present_and_reserved",
		&"the_valley_keeps_its_colours",
	]


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"every_villager_has_a_signature_prop":
			return _t_props_exist()
		&"the_signature_props_are_all_different":
			return _t_props_distinct()
		&"gear_attaches_to_the_right_hand":
			return await _t_gear_attachment()
		&"the_cottages_are_cc0_buildings":
			return await _t_cottage_models()
		&"building_colliders_match_their_art":
			return await _t_colliders()
		&"the_landmarks_are_present_and_reserved":
			return await _t_landmarks()
		&"the_valley_keeps_its_colours":
			return await _t_colours()
	return fail(case, "no case implementation for %s" % case)


func _t_props_exist() -> Dictionary:
	var c := &"every_villager_has_a_signature_prop"
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if data.signature_prop.is_empty():
			bad.append("%s has no prop" % data.id)
		elif not ModelArt.can_load(data.signature_prop):
			bad.append("%s cannot load %s" % [data.id, data.signature_prop.get_file()])
	return check_equals(c, bad, [] as Array[String])


func _t_props_distinct() -> Dictionary:
	var c := &"the_signature_props_are_all_different"
	var seen: Dictionary = {}
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		var name := data.signature_prop.get_file()
		if seen.has(name):
			bad.append("%s and %s both carry %s" % [str(seen[name]), data.id, name])
		seen[name] = data.id
	return check_equals(c, bad, [] as Array[String])


func _t_gear_attachment() -> Dictionary:
	var c := &"gear_attaches_to_the_right_hand"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var bad: Array[String] = []
	for npc: Npc in built["manager"].call("npcs"):
		var model := npc.get_node_or_null(^"Model")
		if model == null:
			bad.append("%s has no model" % npc.data.id)
			continue
		var hand := _find_named(model, "SignatureProp") as BoneAttachment3D
		if hand == null:
			bad.append("%s has no hand attachment" % npc.data.id)
			continue
		if hand.bone_name != ModelArt.HAND_BONE:
			bad.append("%s attached to '%s'" % [npc.data.id, str(hand.bone_name)])
			continue
		if hand.get_node_or_null(^"Prop") == null:
			bad.append("%s has an empty hand" % npc.data.id)
	_stop_recorders()
	return check_equals(c, bad, [] as Array[String])


func _t_cottage_models() -> Dictionary:
	var c := &"the_cottages_are_cc0_buildings"
	var world := await _build_world()
	if world == null:
		return fail(c, "no world")
	var houses: Array[Node] = _find_static_named(world, "House_")
	if houses.size() < 5:
		return fail(c, "only %d houses were built" % houses.size())
	var bad: Array[String] = []
	for house: Node in houses:
		var built_model := false
		for child: Node in house.get_children():
			if child is Node3D and child.get_child_count() > 0:
				built_model = true
		if not built_model:
			bad.append("%s has no model instance" % house.name)
	return check_equals(c, bad, [] as Array[String])


func _t_colliders() -> Dictionary:
	var c := &"building_colliders_match_their_art"
	var world := await _build_world()
	if world == null:
		return fail(c, "no world")
	var bad: Array[String] = []
	for house: Node in _find_static_named(world, "House_"):
		var shape := house.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if shape == null or not shape.shape is BoxShape3D:
			bad.append("a house has no box collider")
			continue
		var size: Vector3 = (shape.shape as BoxShape3D).size
		if size.x < 3.0 or size.y < 3.0 or size.z < 3.0:
			bad.append("house collider is %s" % str(size))
	return check_equals(c, bad, [] as Array[String])


func _t_landmarks() -> Dictionary:
	var c := &"the_landmarks_are_present_and_reserved"
	var world := await _build_world()
	if world == null:
		return fail(c, "no world")
	var names: Array[String] = []
	for landmark: Node in _find_static_named(world, "Windmill") \
			+ _find_static_named(world, "WaterTower") \
			+ _find_static_named(world, "ChickenCoop"):
		names.append(landmark.name)
		if landmark.get_node_or_null(^"CollisionShape3D") == null:
			return fail(c, "%s has no collider" % landmark.name)
	if names.size() != 3:
		return fail(c, "%d CC0 landmarks, expected 3: %s" % [names.size(), str(names)])
	for centre: Vector2 in WorldBuilder.LANDMARK_CENTRES:
		if not WorldBuilder.is_reserved(centre):
			return fail(c, "landmark at %s is not reserved" % str(centre))
	return succeeded(c, "windmill, water tower and coop stand on reserved ground")


## Fog used to wash every albedo pale blue: a noon ground pixel read R144 G166
## B175 with it on and R61 G89 B52 with it off. The quality tiers now keep it
## disabled, so the authored greens, reds and blues survive to the screen.
func _t_colours() -> Dictionary:
	var c := &"the_valley_keeps_its_colours"
	var world := await _build_world()
	if world == null:
		return fail(c, "no world")
	var we := _find_named(world, "Environment") as WorldEnvironment
	if we == null or we.environment == null:
		return fail(c, "the world has no environment")
	if we.environment.fog_enabled:
		return fail(c, "fog is washing the valley out again")
	var ground := _find_named(world, "GroundMesh") as MeshInstance3D
	if ground == null:
		return fail(c, "the ground mesh is missing")
	var mat := ground.material_override as StandardMaterial3D
	if mat == null:
		return fail(c, "the ground has no material")
	var albedo := mat.albedo_color
	if albedo.g <= albedo.r or albedo.g <= albedo.b:
		return fail(c, "grass albedo is %s, not green" % str(albedo))
	return succeeded(c, "fog is off and grass albedo is %s" % str(albedo))


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


func _build_world() -> Node3D:
	_reset_rig()
	var packed := load(WORLD_SCENE) as PackedScene
	if packed == null:
		return null
	_ensure_rig()
	var world: Node3D = packed.instantiate() as Node3D
	_rig.add_child(world)
	await _step(3)
	return world


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _find_static_named(node: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	if node == null:
		return out
	if node is StaticBody3D and node.name.begins_with(prefix):
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_find_static_named(child, prefix))
	return out


func _stop_recorders() -> void:
	pass  # this suite watches no signals; kept so cases share one teardown shape


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "ArtTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
