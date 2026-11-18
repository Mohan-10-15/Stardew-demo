extends SceneTree
## Real-window check of the F5/F9 save and load bindings.
##
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_save.gd
##
## The real `main.tscn` boots with the aggregate SaveService wired to every
## system. Gold is changed through the real wallet between the two key presses.

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_save_"

var _main: Node = null
var _saved := 0
var _loaded := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	if packed == null:
		printerr("[play] no main scene")
		quit(1)
		return
	var bus := root.get_node_or_null(^"EventBus")
	bus.connect(&"game_saved", func(_p: String) -> void: _saved += 1)
	bus.connect(&"game_loaded", func(_p: String) -> void: _loaded += 1)
	bus.connect(&"game_save_failed", func(_r: StringName) -> void: _failed += 1)
	bus.connect(&"game_load_failed", func(_r: StringName) -> void: _failed += 1)
	_main = packed.instantiate()
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var state: Node = _main.get("player_state")
	var save: Node = _main.get("save_service")
	if state == null or save == null:
		printerr("[play] no PlayerState or SaveService")
		quit(1)
		return
	var wallet: Object = state.get("wallet")
	wallet.call("set_gold", 875)
	await _key(KEY_F5)
	deadline = Time.get_ticks_msec() + 5000
	while _saved == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if _saved != 1 or _failed != 0:
		printerr("[play] F5 did not write a save")
		quit(1)
		return
	print("[play] F5 wrote the aggregate save with gold=%d" % int(wallet.get("gold")))
	wallet.call("set_gold", 12)
	await _key(KEY_F9)
	deadline = Time.get_ticks_msec() + 5000
	while _loaded == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if _loaded != 1 or int(wallet.get("gold")) != 875:
		printerr("[play] F9 did not restore gold (got %d)" % int(wallet.get("gold")))
		quit(1)
		return
	print("[play] F9 restored gold=%d" % int(wallet.get("gold")))
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(SHOT + "01_loaded.png")
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
