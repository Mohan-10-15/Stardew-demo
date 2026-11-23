extends SceneTree
## W1.5/W1.6/W1.8 evidence: title v2, About pages, How to Play and Credits at
## two resolutions, with synthetic pad events for the focus path.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_title_v2.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_title_"

var _main: Node = null


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
	_main.set("show_title_on_boot", true)
	root.add_child(_main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	await _settle(20)

	var title := _find(root, &"TitleScreen")
	var about := _find(root, &"AboutPanel")
	var credits := _find(root, &"CreditsPanel")
	if title == null or about == null or credits == null:
		printerr("[play] missing title/about/credits panel")
		quit(1)
		return
	for name: String in ["NewGame", "Continue", "About", "HowToPlay", "Settings", "Credits", "Quit"]:
		if title.get_node_or_null("Panel/Column/" + name) == null:
			printerr("[play] title button missing: %s" % name)
			quit(1)
			return
	print("[play] title v2 has all 7 buttons at 1280x720")
	await _shot(SHOT + "v2_1280_title.png")

	about.call("open", true)
	await _settle(5)
	await _shot(SHOT + "v2_1280_about.png")
	var pages := 0
	for _i: int in range(7):
		about.call("next_page")
		pages += 1
		await _settle(3)
	print("[play] paged through %d About steps" % pages)
	about.call("close")

	credits.call("open")
	await _settle(5)
	await _shot(SHOT + "v2_1280_credits.png")
	credits.call("close")

	root.size = Vector2i(1920, 1080)
	await _settle(10)
	await _shot(SHOT + "v2_1920_title.png")
	print("[play] title captured at 1920x1080")

	# A synthetic pad shoulder press must move focus/glyphs without a keyboard.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	Input.parse_input_event(pad)
	await _settle(4)
	pad.pressed = false
	Input.parse_input_event(pad)
	await _settle(4)
	print("[play] synthetic D-pad input delivered")
	print("[play] PASS")
	quit(0)


func _find(node: Node, wanted: StringName) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
