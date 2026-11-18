extends SceneTree
## Real-window review of story progression from chapter one to the ending.
##
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_story.gd
##
## The outcomes are real EventBus signals; a full playthrough would take hours,
## so this short-circuits to the events each chapter waits for.

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_story_"

var _main: Node = null
var _ending := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	# Isolate story progression: chapter transitions request cutscenes, and a
	# cutscene legitimately pauses the world. This review checks the ending and
	# that free play resumes, so the director is left out on purpose.
	_main.set("load_cutscenes", false)
	var bus := root.get_node_or_null(^"EventBus")
	bus.connect(&"story_ending_reached", func(_id: StringName) -> void: _ending += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var story: Node = _main.get("story_service")
	if story == null:
		printerr("[play] no story service")
		quit(1)
		return
	print("[play] chapter %s: %s" % [str(story.get("current_stage")), _title(story)])
	await _shot(SHOT + "01_chapter_one.png")

	bus.emit_signal(&"cutscene_finished", &"intro")
	bus.emit_signal(&"cutscene_finished", &"first_village")
	bus.emit_signal(&"crop_harvested", Vector2i.ZERO, &"parsnip", 1)
	bus.emit_signal(&"quest_turned_in", &"q_mira_first_harvest", &"mira")
	bus.emit_signal(&"npc_friendship_changed", &"mira", 4, "Friend")
	bus.emit_signal(&"quest_turned_in", &"q_odette_first_frost", &"odette")
	await _settle(4)
	if StringName(story.get("current_stage")) != &"ch05_trust":
		printerr("[play] expected ch05_trust, got %s" % str(story.get("current_stage")))
		quit(1)
		return
	print("[play] chapter %s: %s" % [str(story.get("current_stage")), _title(story)])
	await _shot(SHOT + "02_before_ending.png")

	bus.emit_signal(&"npc_married", &"mira")
	await _settle(4)
	if _ending != 1 or StringName(story.get("current_stage")) != &"ch06_ending":
		printerr("[play] ending did not fire (stage=%s)" % str(story.get("current_stage")))
		quit(1)
		return
	var state := root.get_node_or_null(^"GameState")
	if bool(state.get("paused")):
		printerr("[play] the ending locked the game (phase=%s)" % state.get_phase_name())
		quit(1)
		return
	print("[play] ending: %s — free play continues" % _title(story))
	await _shot(SHOT + "03_ending.png")
	print("[play] PASS")
	quit(0)


func _title(story: Node) -> String:
	var id := StringName(str(story.get("current_stage")))
	var chapter: StoryChapter = StoryRegistry.chapter_for(id)
	return chapter.title if chapter != null else "<none>"


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
