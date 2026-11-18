extends TestSuite
## Cutscenes: the data loads, playback locks and restores the game, and a skip
## still applies the story flags the guide says must survive it.

const DIRECTOR_SCRIPT := "res://scripts/cutscenes/cutscene_director.gd"

var _rig: Node3D = null
var _seen: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"cutscenes_are_authored_and_valid",
		&"playback_locks_then_restores",
		&"skipping_applies_story_flags",
		&"required_beats_cannot_be_skipped",
	]


func setup() -> void:
	_rig = null
	_seen = {}


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"cutscenes_are_authored_and_valid":
			return _t_content()
		&"playback_locks_then_restores":
			return await _t_playback()
		&"skipping_applies_story_flags":
			return await _t_skip()
		&"required_beats_cannot_be_skipped":
			return await _t_required()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"cutscenes_are_authored_and_valid"
	var all := CutsceneRegistry.all()
	if all.size() < 2:
		return fail(c, "only %d cutscenes were authored" % all.size())
	if not CutsceneRegistry.duplicate_ids().is_empty():
		return fail(c, "duplicate cutscene ids")
	var bad: Array[String] = []
	for cutscene: CutscenePlayer in all:
		if not cutscene.is_valid():
			bad.append(String(cutscene.id))
		var has_flag := false
		for event: CutsceneEvent in cutscene.events:
			if event.kind == &"flag":
				has_flag = true
		if cutscene.id != &"test_short" and not has_flag:
			bad.append("%s sets no story flag" % cutscene.id)
	return check_equals(c, bad, [] as Array[String])


func _t_playback() -> Dictionary:
	var c := &"playback_locks_then_restores"
	await _build()
	var director: Node = _rig.get_node(^"Director")
	_watch()
	if not bool(director.call("play", &"test_short")):
		return fail(c, "the cutscene refused to play")
	await _frames(2)
	var state := autoload(&"GameState")
	if state == null or not bool(state.get("paused")):
		return fail(c, "the player was not locked while the cutscene ran")
	await _frames(30)
	if int(_seen.get(&"cutscene_finished", 0)) != 1:
		return fail(c, "%d finish events" % int(_seen.get(&"cutscene_finished", 0)))
	if bool(state.get("paused")):
		return fail(c, "the game stayed paused after the cutscene")
	var flags: Dictionary = director.get("applied_flags")
	if not bool(flags.get(&"test_flag", false)):
		return fail(c, "the story flag was not applied")
	_stop_watch()
	return succeeded(c, "locked, applied the flag and restored the game")


func _t_skip() -> Dictionary:
	var c := &"skipping_applies_story_flags"
	await _build()
	var director: Node = _rig.get_node(^"Director")
	_watch()
	director.call("play", &"test_short")
	await _frames(2)
	director.call("skip")
	await _frames(20)
	if int(_seen.get(&"cutscene_skipped", 0)) != 1:
		return fail(c, "skip did not fire")
	var flags: Dictionary = director.get("applied_flags")
	if not bool(flags.get(&"test_flag", false)):
		return fail(c, "the skipped cutscene forgot its story flag")
	var state := autoload(&"GameState")
	if bool(state.get("paused")):
		return fail(c, "skipping left the game paused")
	_stop_watch()
	return succeeded(c, "skip restored the game and kept the story flag")


func _t_required() -> Dictionary:
	var c := &"required_beats_cannot_be_skipped"
	await _build()
	var director: Node = _rig.get_node(^"Director")
	_watch()
	director.call("play", &"test_required")
	await _frames(1)
	director.call("skip")
	await _frames(60)
	if int(_seen.get(&"cutscene_skipped", 0)) != 0:
		return fail(c, "a required beat was skipped")
	if int(_seen.get(&"cutscene_finished", 0)) != 1:
		return fail(c, "the required cutscene did not finish: %s" % str(_seen))
	var flags: Dictionary = director.get("applied_flags")
	if not bool(flags.get(&"required_flag", false)):
		return fail(c, "the required beat did not apply its flag")
	_stop_watch()
	return succeeded(c, "the required beat ran and the cutscene finished")


# --- Fixtures -----------------------------------------------------------------


func _build() -> void:
	_reset_rig()
	var script := load(DIRECTOR_SCRIPT) as GDScript
	_ensure_rig()
	var director: Node = script.new()
	director.name = "Director"
	_rig.add_child(director)


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_seen = {&"cutscene_started": 0, &"cutscene_finished": 0, &"cutscene_skipped": 0}
	bus.connect(&"cutscene_started", _on_started)
	bus.connect(&"cutscene_finished", _on_finished)
	bus.connect(&"cutscene_skipped", _on_skipped)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	if bus.is_connected(&"cutscene_started", _on_started):
		bus.disconnect(&"cutscene_started", _on_started)
	if bus.is_connected(&"cutscene_finished", _on_finished):
		bus.disconnect(&"cutscene_finished", _on_finished)
	if bus.is_connected(&"cutscene_skipped", _on_skipped):
		bus.disconnect(&"cutscene_skipped", _on_skipped)


func _on_started(_id: StringName) -> void:
	_seen[&"cutscene_started"] = int(_seen.get(&"cutscene_started", 0)) + 1


func _on_finished(_id: StringName) -> void:
	_seen[&"cutscene_finished"] = int(_seen.get(&"cutscene_finished", 0)) + 1


func _on_skipped(_id: StringName) -> void:
	_seen[&"cutscene_skipped"] = int(_seen.get(&"cutscene_skipped", 0)) + 1


func _frames(count: int) -> void:
	# Only process frames: a cutscene pauses the tree, so physics frames stop.
	for _i: int in range(count):
		await tree.process_frame


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "CutsceneTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	_stop_watch()
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null
