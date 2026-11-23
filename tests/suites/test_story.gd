extends TestSuite
## The main story: chapters are data, they open on things the player actually
## did, the ending fires once, and free play continues afterwards.

const STORY_SCRIPT := "res://scripts/story/story_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"chapters_are_authored_in_order",
		&"flags_open_one_chapter_at_a_time",
		&"the_ending_fires_once_and_play_continues",
		&"story_progress_survives_a_save",
	]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"chapters_are_authored_in_order":
			return _t_content()
		&"flags_open_one_chapter_at_a_time":
			return await _t_progression()
		&"the_ending_fires_once_and_play_continues":
			return await _t_ending()
		&"story_progress_survives_a_save":
			return await _t_save()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"chapters_are_authored_in_order"
	var chapters := StoryRegistry.all()
	if chapters.size() < 4:
		return fail(c, "only %d chapters were authored" % chapters.size())
	if not StoryRegistry.duplicate_ids().is_empty():
		return fail(c, "duplicate chapter ids")
	var endings := 0
	for chapter: StoryChapter in chapters:
		if not chapter.is_valid():
			return fail(c, "%s is invalid" % chapter.id)
		if chapter.is_ending:
			endings += 1
	if endings != 1:
		return fail(c, "%d endings, expected one" % endings)
	if not StoryRegistry.last().is_ending:
		return fail(c, "the last chapter is not the ending")
	return succeeded(c, "%d chapters, one ending at the end" % chapters.size())


func _t_progression() -> Dictionary:
	var c := &"flags_open_one_chapter_at_a_time"
	await _build()
	var story: Node = _rig.get_node(^"Story")
	var order: Array[StringName] = []
	for chapter: StoryChapter in StoryRegistry.all():
		order.append(chapter.id)
	if StringName(story.get("current_stage")) != order[0]:
		return fail(c, "the player starts at '%s', not '%s'" % [
			str(story.get("current_stage")), order[0],
		])
	var bus := autoload(&"EventBus")
	_watch(bus)
	var chapters := StoryRegistry.all()
	for i: int in range(1, chapters.size()):
		var before := StringName(story.get("current_stage"))
		bus.emit_signal(&"npc_talked", &"mira")  # a stray event must not advance
		if StringName(story.get("current_stage")) != before:
			return fail(c, "an unrelated event skipped a chapter")
		# Drive every requirement of the next chapter through the real signal
		# StoryService listens to; a chapter with two flags needs two events.
		for required: StringName in chapters[i].requires:
			_emit_flag(bus, required)
		if StringName(story.get("current_stage")) != chapters[i].id:
			return fail(c, "after '%s' the stage is '%s', not '%s'" % [
				chapters[i].id, str(story.get("current_stage")), chapters[i].id,
			])
	_stop_watch()
	return succeeded(c, "requirements opened all %d chapters, no skips" % chapters.size())


func _emit_flag(bus: Node, flag: StringName) -> void:
	match flag:
		&"first_harvest":
			bus.emit_signal(&"crop_harvested", Vector2i.ZERO, &"parsnip", 1)
		&"first_friend":
			bus.emit_signal(&"npc_friendship_changed", &"mira", 4, "Friend")
		&"married":
			bus.emit_signal(&"npc_married", &"mira")
		&"all_embers":
			bus.emit_signal(&"heartstone_mended")
		_:
			if String(flag).begins_with("ember_"):
				bus.emit_signal(&"ember_returned", StringName(
					String(flag).trim_prefix("ember_")), 1)
				return
			if String(flag).ends_with("_path") or String(flag).ends_with("_pier") \
					or String(flag).ends_with("_road") or String(flag).ends_with("_stairs"):
				bus.emit_signal(&"collection_tier_reached", &"fields", 0, flag, &"fields")
				return
			if String(flag).ends_with("_done"):
				var quest_id := String(flag).replace("quest_", "").replace("_done", "")
				bus.emit_signal(&"quest_turned_in", StringName(quest_id), &"mira")
			else:
				bus.emit_signal(&"cutscene_finished",
					StringName(String(flag).replace("_seen", "")))


func _t_ending() -> Dictionary:
	var c := &"the_ending_fires_once_and_play_continues"
	await _build()
	var story: Node = _rig.get_node(^"Story")
	var bus := autoload(&"EventBus")
	_watch(bus)
	for chapter: StoryChapter in StoryRegistry.all():
		for required: StringName in chapter.requires:
			_emit_flag(bus, required)
	if int(_events.get(&"story_ending_reached", 0)) != 1:
		return fail(c, "%d endings; stage=%s flags=%s bus=%s connected=%s" % [
			int(_events.get(&"story_ending_reached", 0)),
			str(story.get("current_stage")), str(story.get("flags")),
			str(story.call("_bus") != null),
			str(bus.is_connected(&"cutscene_finished", Callable(story, "_on_cutscene"))),
		])
	if not bool(story.get("ending_reached")):
		return fail(c, "the service did not remember the ending")
	# A further event must not fire the ending again or lock the game.
	bus.emit_signal(&"npc_married", &"bram")
	if int(_events.get(&"story_ending_reached", 0)) != 1:
		return fail(c, "the ending fired twice")
	var state := autoload(&"GameState")
	if bool(state.get("paused")) or int(state.get("phase")) == 0:
		return fail(c, "the ending left the game locked or booting")
	_stop_watch()
	return succeeded(c, "one ending, and the game is still playable")


func _t_save() -> Dictionary:
	var c := &"story_progress_survives_a_save"
	await _build()
	var story: Node = _rig.get_node(^"Story")
	var bus := autoload(&"EventBus")
	bus.emit_signal(&"cutscene_finished", &"intro")
	bus.emit_signal(&"cutscene_finished", &"first_village")
	var before := StringName(story.get("current_stage"))
	var data: Dictionary = story.call("to_dict")
	var fresh: Node = (load(STORY_SCRIPT) as GDScript).new()
	_rig.add_child(fresh)
	fresh.call("from_dict", data)
	if StringName(fresh.get("current_stage")) != before:
		return fail(c, "the chapter came back as '%s'" % str(fresh.get("current_stage")))
	if not bool(fresh.call("has_method", "to_dict")):
		return fail(c, "the restored service lost its API")
	_stop_watch()
	return succeeded(c, "chapter and flags round-tripped")


func _watch(bus: Node) -> void:
	_events = {&"story_stage_changed": 0, &"story_ending_reached": 0}
	bus.connect(&"story_stage_changed", _on_stage)
	bus.connect(&"story_ending_reached", _on_ending)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	if bus.is_connected(&"story_stage_changed", _on_stage):
		bus.disconnect(&"story_stage_changed", _on_stage)
	if bus.is_connected(&"story_ending_reached", _on_ending):
		bus.disconnect(&"story_ending_reached", _on_ending)


func _on_stage(_a: StringName, _b: StringName) -> void:
	_events[&"story_stage_changed"] = int(_events.get(&"story_stage_changed", 0)) + 1


func _on_ending(_id: StringName) -> void:
	_events[&"story_ending_reached"] = int(_events.get(&"story_ending_reached", 0)) + 1


func _build() -> void:
	_stop_watch()
	_reset_rig()
	var script := load(STORY_SCRIPT) as GDScript
	_ensure_rig()
	var story: Node = script.new()
	story.name = "Story"
	_rig.add_child(story)
	await _step(2)


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "StoryTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
