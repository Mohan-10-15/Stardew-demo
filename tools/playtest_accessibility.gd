extends SceneTree
## Real-window review of M15: open settings with F2, scale text, toggle high
## contrast, rebind interact to R, confirm the HUD label follows, and escape.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_accessibility.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_accessibility_"

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
	_main.set("show_title_on_boot", false)
	root.add_child(_main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame

	var panel: CanvasLayer = _main.get("settings_panel")
	var rebind: Node = _main.get("rebind_service")
	var config := root.get_node_or_null(^"Config")
	if panel == null or rebind == null or config == null:
		printerr("[play] missing settings panel, rebind service or config")
		quit(1)
		return
	config.call("reset_to_defaults")
	rebind.call("reset_all")
	var initial_scale: float = float(config.settings.ui_scale)

	await _tap(KEY_F2)
	await _settle(5)
	if not bool(panel.visible):
		printerr("[play] F2 did not open the settings panel")
		quit(1)
		return
	print("[play] settings opened with F2")
	await _shot(SHOT + "01_panel.png")

	await _tap(KEY_RIGHT)
	await _settle(5)
	var new_scale: float = float(config.settings.ui_scale)
	if not is_equal_approx(new_scale, initial_scale + 0.05):
		printerr("[play] text scale stayed at %f" % new_scale)
		quit(1)
		return
	var heading := panel.get_node_or_null(^"Panel/Column/Rows/Row0") as Label
	if heading == null or int(heading.get_theme_font_size(&"font_size")) < 12:
		printerr("[play] the row font did not follow the scale")
		quit(1)
		return
	print("[play] text scale %f -> %f and rows resized" % [initial_scale, new_scale])
	await _shot(SHOT + "02_scaled.png")

	# Down to high contrast, Enter to toggle.
	await _tap(KEY_DOWN)
	await _settle(3)
	await _tap(KEY_ENTER)
	await _settle(4)
	if not bool(config.settings.colour_assist):
		printerr("[play] high contrast did not turn on")
		quit(1)
		return
	# Rows are rebuilt on every settings change, so re-read the live label.
	heading = panel.get_node_or_null(^"Panel/Column/Rows/Row0") as Label
	if heading == null or int(heading.get_theme_constant(&"font_outline_size")) != 2:
		printerr("[play] the high-contrast outline was not applied")
		quit(1)
		return
	print("[play] high contrast added text outlines")

	# Down to "Rebind Interact", Enter to listen, then press R.
	await _tap(KEY_DOWN)
	await _settle(3)
	await _tap(KEY_ENTER)
	await _settle(3)
	await _tap(KEY_R)
	await _settle(5)
	if String(rebind.call("label_for", InputActions.INTERACT)) != "R":
		printerr("[play] interact did not rebind to R")
		quit(1)
		return
	print("[play] interact rebound to R; HUD label reads '%s'" % str(
		rebind.call("label_for", InputActions.INTERACT)
	))
	await _shot(SHOT + "03_rebound.png")

	await _tap(KEY_ESCAPE)
	await _settle(4)
	if bool(panel.visible):
		printerr("[play] Escape did not close the settings panel")
		quit(1)
		return
	print("[play] Escape closed the panel")

	config.call("reset_to_defaults")
	rebind.call("reset_all")
	print("[play] PASS")
	quit(0)


func _tap(code: int) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(3)
	var release := InputEventKey.new()
	release.keycode = code
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
