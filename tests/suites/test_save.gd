extends TestSuite
## The aggregate save: one versioned file carrying every service's own state,
## with migrations, corruption handling and distinct success/failure events.

const SAVE_SCRIPT := "res://scripts/save/save_service.gd"
const TEST_PATH := "user://test_hollowbrook.save"
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const QUEST_SERVICE_SCRIPT := "res://scripts/quest/quest_service.gd"
const DIALOGUE_SERVICE_SCRIPT := "res://scripts/dialogue/dialogue_service.gd"
const TIME_SERVICE_SCRIPT := "res://scripts/time/time_service.gd"
const DIRECTOR_SCRIPT := "res://scripts/cutscenes/cutscene_director.gd"

var _rig: Node3D = null
var _events: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"the_save_carries_every_system",
		&"a_full_game_round_trips",
		&"older_versions_migrate_forward",
		&"a_corrupt_save_fails_loudly_and_safely",
	]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_reset_rig()
	_forget(TEST_PATH)


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"the_save_carries_every_system":
			return await _t_sections()
		&"a_full_game_round_trips":
			return await _t_roundtrip()
		&"older_versions_migrate_forward":
			return await _t_migration()
		&"a_corrupt_save_fails_loudly_and_safely":
			return await _t_corrupt()
	return fail(case, "no case implementation for %s" % case)


func _t_sections() -> Dictionary:
	var c := &"the_save_carries_every_system"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the services")
	var save: Node = built["save"]
	var script := load(SAVE_SCRIPT) as GDScript
	if int(script.get_script_constant_map().get("SAVE_VERSION", 0)) < 2:
		return fail(c, "the save format is not versioned")
	var data: Dictionary = save.call("to_dict")
	for key: String in ["version", "time", "player", "farm", "npcs", "quests", "dialogue", "cutscene_flags"]:
		if not data.has(key):
			return fail(c, "the save has no '%s' section (farm grid=%s)" % [
				key, str(built["save"].get("farm_service").get("grid"))
			])
	return succeeded(c, "%d sections at version %d" % [data.size(), data["version"]])


func _t_roundtrip() -> Dictionary:
	var c := &"a_full_game_round_trips"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the services")
	var save: Node = built["save"]
	var state: Node = built["state"]
	var manager: Node = built["manager"]
	var quests: Node = built["quests"]
	var dialogue: Node = built["dialogue"]
	var wallet: Object = state.get("wallet")
	wallet.call("set_gold", 1234)
	manager.call("grant_hearts", &"mira", 3)
	quests.call("accept", &"q_mira_first_harvest", state)
	dialogue.call("set_flag", &"roundtrip_flag", true)
	_watch()
	if not bool(save.call("save_game", TEST_PATH)):
		return fail(c, "save_game failed: %s" % str(save.get("last_error")))
	if int(_events.get(&"game_saved", 0)) != 1:
		return fail(c, "no success event for the write")
	# Mutate everything away from the saved state before loading.
	wallet.call("set_gold", 5)
	manager.get_npc(&"mira").friendship.points = 0
	dialogue.call("set_flag", &"roundtrip_flag", false)
	if not bool(save.call("load_game", TEST_PATH)):
		var f := FileAccess.open(TEST_PATH, FileAccess.READ)
		var text := f.get_as_text() if f != null else "<no file>"
		return fail(c, "load_game failed: %s — %s" % [
			str(save.get("last_error")), text.substr(0, 260),
		])
	if int(_events.get(&"game_loaded", 0)) != 1:
		return fail(c, "no success event for the load")
	if int(wallet.get("gold")) != 1234:
		return fail(c, "gold came back as %d" % int(wallet.get("gold")))
	if manager.get_npc(&"mira").friendship.hearts() < 3:
		return fail(c, "friendship did not come back")
	if not bool(quests.call("is_active", &"q_mira_first_harvest")):
		return fail(c, "the active quest did not come back")
	if not bool(dialogue.call("has_flag", &"roundtrip_flag")):
		return fail(c, "dialogue flags did not come back")
	_stop_watch()
	return succeeded(c, "gold, hearts, quests and dialogue flags survived" )


func _t_migration() -> Dictionary:
	var c := &"older_versions_migrate_forward"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the services")
	var save: Node = built["save"]
	var script := load(SAVE_SCRIPT) as GDScript
	var current := int(script.get_script_constant_map().get("SAVE_VERSION", 3))
	var old := {"version": 1, "player": {}, "time": {}}
	var migrated: Dictionary = save.call("migrate", old)
	if int(migrated.get("version", 0)) != current:
		return fail(c, "version 1 did not migrate to %d" % current)
	if not migrated.has("dialogue") or not migrated.has("cutscene_flags"):
		return fail(c, "migration did not add the missing sections")
	var future := {"version": current + 5}
	var result: Dictionary = save.call("migrate", future)
	if StringName(save.get("last_error")) != &"future_version":
		return fail(c, "a future save was not refused")
	return succeeded(c, "version 1 migrated; a future version was refused")


func _t_corrupt() -> Dictionary:
	var c := &"a_corrupt_save_fails_loudly_and_safely"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the services")
	var save: Node = built["save"]
	_forget(TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ this is not json ")
	file.close()
	_watch()
	if bool(save.call("load_game", TEST_PATH)):
		return fail(c, "a corrupt save loaded successfully")
	if StringName(save.get("last_error")) != &"corrupt":
		return fail(c, "the wrong reason was published: %s" % str(save.get("last_error")))
	if int(_events.get(&"game_load_failed", 0)) != 1:
		return fail(c, "no distinct failure event")
	_stop_watch()
	# A valid save with missing sections loads field by field.
	var partial := {"version": 1, "player": {}}
	var state: Node = built["state"]
	var wallet: Object = state.get("wallet")
	wallet.call("set_gold", 777)
	save.call("from_dict", partial)
	if int(wallet.get("gold")) != 777:
		return fail(c, "a partial save wiped a field it did not mention")
	return succeeded(c, "corruption failed loudly; partial data is tolerated")


# --- Fixtures -----------------------------------------------------------------


func _build() -> Dictionary:
	_reset_rig()
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	var quest_script := load(QUEST_SERVICE_SCRIPT) as GDScript
	var dialogue_script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	var save_script := load(SAVE_SCRIPT) as GDScript
	var time_script := load(TIME_SERVICE_SCRIPT) as GDScript
	if state_script == null or manager_script == null or quest_script == null \
			or dialogue_script == null or save_script == null or time_script == null:
		return {}
	_ensure_rig()
	var clock: Node = time_script.new()
	clock.name = "TimeService"
	_rig.add_child(clock)
	# A tiny stand-in: the real farm needs the generated world, and this fixture
	# only checks that the save asks it for its grid's own state.
	var stub_script := load("res://tests/helpers/farm_stub.gd") as GDScript
	var grid: Node = stub_script.new()
	grid.name = "Grid"
	# The grid must be in the tree too: a parentless node is never freed with
	# the rig and shows up as a leaked instance at exit.
	_rig.add_child(grid)
	var farm: Node = stub_script.new()
	farm.name = "FarmService"
	farm.set("grid", grid)
	_rig.add_child(farm)
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
	var dialogue: Node = dialogue_script.new()
	dialogue.name = "DialogueService"
	_rig.add_child(dialogue)
	var director_script := load(DIRECTOR_SCRIPT) as GDScript
	var director: Node = director_script.new()
	director.name = "CutsceneDirector"
	_rig.add_child(director)
	var save: Node = save_script.new()
	save.name = "SaveService"
	save.set("time_service", clock)
	save.set("farm_service", farm)
	save.set("player_state", state)
	save.set("npc_manager", manager)
	save.set("quest_service", quests)
	save.set("dialogue_service", dialogue)
	save.set("cutscene_director", director)
	_rig.add_child(save)
	await _step(3)
	return {"save": save, "state": state, "manager": manager, "quests": quests, "dialogue": dialogue}


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"game_saved": 0, &"game_save_failed": 0, &"game_loaded": 0, &"game_load_failed": 0}
	bus.connect(&"game_saved", _on_saved)
	bus.connect(&"game_save_failed", _on_save_failed)
	bus.connect(&"game_loaded", _on_loaded)
	bus.connect(&"game_load_failed", _on_load_failed)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	for pair: Array in [[&"game_saved", _on_saved], [&"game_save_failed", _on_save_failed],
			[&"game_loaded", _on_loaded], [&"game_load_failed", _on_load_failed]]:
		if bus.is_connected(pair[0], pair[1]):
			bus.disconnect(pair[0], pair[1])


func _on_saved(_path: String) -> void: _events[&"game_saved"] = int(_events.get(&"game_saved", 0)) + 1
func _on_save_failed(_reason: StringName) -> void: _events[&"game_save_failed"] = int(_events.get(&"game_save_failed", 0)) + 1
func _on_loaded(_path: String) -> void: _events[&"game_loaded"] = int(_events.get(&"game_loaded", 0)) + 1
func _on_load_failed(_reason: StringName) -> void: _events[&"game_load_failed"] = int(_events.get(&"game_load_failed", 0)) + 1


func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "SaveTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	_stop_watch()
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
