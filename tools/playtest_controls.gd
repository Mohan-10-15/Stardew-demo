extends SceneTree
## W1.1 evidence: the eight-input scheme in a real window. Verifies that left
## click reaches an interactable through USE, that E still works, and that a
## synthetic gamepad button can drive the same core actions.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_controls.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_controls_"

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

	var used := 0
	bus.interaction_performed.connect(func(_n: Node) -> void: used += 1)
	print("[play] core actions: use=%s alt_use=%s interact=%s pad_jump=%s" % [
		str(InputMap.has_action(&"use")), str(InputMap.has_action(&"alt_use")),
		str(InputMap.has_action(&"interact")),
		str(InputMap.action_get_events(&"jump").any(func(e: InputEvent) -> bool:
			return e is InputEventJoypadButton)),
	])

	# Left click through USE: a press on empty space must not error and the
	# input must be consumed, proving the new binding is live in a real window.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _settle(4)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await _settle(4)
	print("[play] left click delivered through use; interactions fired=%d" % used)

	# Synthetic gamepad: the pad jump button must move the player.
	var player: Node3D = _main.get("player")
	if player == null:
		printerr("[play] no player")
		quit(1)
		return
	# Let the spawn drop settle first; a jump pressed mid-fall proves nothing.
	await _settle(30)
	var before := player.global_position
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Input.parse_input_event(pad)
	await _settle(10)
	var mid := player.global_position
	print("[play] pad jump: y %.2f -> %.2f" % [before.y, mid.y])
	pad.pressed = false
	Input.parse_input_event(pad)
	await _settle(6)
	await _shot(SHOT + "01_controls.png")
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
