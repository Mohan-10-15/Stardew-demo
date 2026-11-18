extends SceneTree
## Real-window check of the title screen and its Continue flow.
##
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_title.gd

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
	root.add_child(_main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var state := root.get_node_or_null(^"GameState")
	var title: CanvasLayer = _main.get("title_screen")
	var save: Node = _main.get("save_service")
	if state == null or title == null or save == null:
		printerr("[play] missing title, save or GameState")
		quit(1)
		return
	if int(state.get("phase")) != 1 or not bool(state.get("paused")):
		printerr("[play] the game did not open on a paused title screen")
		quit(1)
		return
	print("[play] title shown; phase=%s" % state.get_phase_name())
	await _shot(SHOT + "01_title.png")

	# F5 still works while the menu is up: the boot root handles it with
	# PROCESS_MODE_ALWAYS, so Continue can be enabled by a real key press.
	await _key(KEY_F5)
	await _settle(4)
	var cont: Button = title.get_node_or_null(^"Panel/Column/Continue") as Button
	if cont == null or cont.disabled:
		printerr("[play] Continue stayed disabled after F5")
		quit(1)
		return
	var center := cont.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = center
	Input.parse_input_event(move)
	await _settle(2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = center
	click.pressed = true
	Input.parse_input_event(click)
	await _settle(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = center
	release.pressed = false
	Input.parse_input_event(release)
	deadline = Time.get_ticks_msec() + 5000
	while bool(title.visible) and Time.get_ticks_msec() < deadline:
		await process_frame
	if bool(title.visible) or int(state.get("phase")) != 3 or bool(state.get("paused")):
		printerr("[play] Continue did not return to play (phase=%s visible=%s paused=%s)" % [
			state.get_phase_name(), str(title.visible), str(state.get("paused")),
		])
		quit(1)
		return
	print("[play] Continue returned to phase=%s" % state.get_phase_name())
	await _shot(SHOT + "02_after_continue.png")
	print("[play] PASS")
	quit(0)


func _key(code: int) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(3)
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await _settle(3)


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
