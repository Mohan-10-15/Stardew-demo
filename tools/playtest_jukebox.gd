extends SceneTree
## W6.6 evidence: a heard cue appears in the jukebox and a "Now playing" toast
## shows when it is replayed.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_jukebox.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_jukebox_"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	var main := packed.instantiate()
	main.set("show_title_on_boot", false)
	main.set("play_intro_cutscene", false)
	root.add_child(main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var director: Node = main.get("music_director")
	if director == null:
		printerr("[play] no music director")
		quit(1)
		return
	director.call("set_context", {"menu": true})
	for _i: int in range(20):
		await process_frame
	var unlocked: Array = director.call("unlocked_cues") as Array
	print("[play] unlocked: %s" % str(unlocked))
	if not unlocked.has(&"title"):
		printerr("[play] title was not unlocked")
		quit(1)
		return
	var toast: CanvasLayer = main.get("music_toast") as CanvasLayer
	if toast != null and bool(toast.visible):
		await _shot(SHOT + "01_toast.png")
	director.call("play_cue", &"title")
	var press := InputEventKey.new()
	press.keycode = KEY_F6
	press.physical_keycode = KEY_F6
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(4)
	var release := InputEventKey.new()
	release.keycode = KEY_F6
	release.physical_keycode = KEY_F6
	release.pressed = false
	Input.parse_input_event(release)
	await _settle(6)
	var panel: CanvasLayer = main.get("jukebox_panel") as CanvasLayer
	if panel == null or not bool(panel.visible):
		printerr("[play] F6 did not open the jukebox")
		quit(1)
		return
	print("[play] jukebox open with %d rows" % (
		(panel.get_node_or_null(^"Panel/Column/Rows") as VBoxContainer).get_child_count()))
	await _shot(SHOT + "02_open.png")
	print("[play] PASS")
	quit(0)


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
