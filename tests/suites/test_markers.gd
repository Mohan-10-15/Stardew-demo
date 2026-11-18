extends TestSuite
## The ! / ? above a villager's head: the quest system's offer and hand-in state,
## made visible before the player walks over.
##
## A marker that never clears would send the player back to a villager who has
## no work; one that never appears hides the whole quest system behind a chat.
## Both are cheap to assert with the real quest service in the tree.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const QUEST_SERVICE_SCRIPT := "res://scripts/quest/quest_service.gd"

const MIRA := &"mira"
const MIRA_JOB := &"q_mira_first_harvest"
const PARSNIP := &"parsnip"

var _rig: Node3D = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"every_villager_has_a_work_marker",
		&"the_marker_follows_the_quest_state",
	]


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"every_villager_has_a_work_marker":
			return await _t_markers_exist()
		&"the_marker_follows_the_quest_state":
			return await _t_marker_states()
	return fail(case, "no case implementation for %s" % case)


func _t_markers_exist() -> Dictionary:
	var c := &"every_villager_has_a_work_marker"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the world")
	var bad: Array[String] = []
	for npc: Npc in built["manager"].call("npcs"):
		var marker := npc.get_node_or_null(^"QuestMarker") as Sprite3D
		if marker == null:
			bad.append("%s has no marker" % npc.data.id)
		elif marker.position.y <= npc.body_height():
			bad.append("%s marker is not above the head" % npc.data.id)
	return check_equals(c, bad, [] as Array[String])


func _t_marker_states() -> Dictionary:
	var c := &"the_marker_follows_the_quest_state"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the world")
	var npc: Npc = built["manager"].call("get_npc", MIRA)
	var marker := npc.get_node_or_null(^"QuestMarker") as Sprite3D
	var quests: Node = built["quests"]
	var state: Node = built["state"]
	if marker == null or quests == null or state == null:
		return fail(c, "missing marker, quest service or player state")
	var offer_tex: Texture2D = marker.texture
	if not marker.visible or offer_tex == null:
		return fail(c, "Mira's offer is invisible (visible=%s tex=%s offer=%s service=%s)" % [
			str(marker.visible), str(offer_tex != null),
			str(quests.call("next_offer_from", MIRA)), str(built["manager"].get_tree() != null),
		])
	if not bool(quests.call("accept", MIRA_JOB, state)):
		return fail(c, "could not take Mira's job")
	await _step(2)
	if marker.visible:
		return fail(c, "the marker stayed up after the job was accepted")
	var bag: Inventory = state.get("inventory") as Inventory
	var need := QuestRegistry.get_quest(MIRA_JOB).objective.count
	bag.add(PARSNIP, need)
	# Production routes through the bus; the quest service listens there, not
	# directly to the bag. A harvest publishes `item_added`.
	var bus := autoload(&"EventBus")
	bus.emit_signal(&"item_added", PARSNIP, need)
	await _step(2)
	var ready_tex: Texture2D = marker.texture
	if not marker.visible or ready_tex == null:
		return fail(c, "the hand-in marker never appeared after %d parsnips" % need)
	if ready_tex == offer_tex:
		return fail(c, "an offer and a ready job look the same")
	if not bool(quests.call("turn_in", MIRA_JOB, state, MIRA)):
		return fail(c, "could not hand the job in")
	await _step(2)
	if marker.visible:
		return fail(c, "the marker stayed up after the hand-in")
	return succeeded(c, "offer, hidden, hand-in, hidden — two distinct marks")


# --- Fixture ------------------------------------------------------------------


func _build() -> Dictionary:
	_reset_rig()
	var world_packed := load(WORLD_SCENE) as PackedScene
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	var quest_script := load(QUEST_SERVICE_SCRIPT) as GDScript
	if world_packed == null or state_script == null or manager_script == null \
			or quest_script == null:
		return {}
	_ensure_rig()
	var world: Node3D = world_packed.instantiate() as Node3D
	_rig.add_child(world)
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	var quests: Node = quest_script.new()
	quests.name = "QuestService"
	quests.set("player_state", state)
	quests.set("npc_manager", manager)
	_rig.add_child(quests)
	await _step(5)
	return {"world": world, "state": state, "manager": manager, "quests": quests}


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "MarkerTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
