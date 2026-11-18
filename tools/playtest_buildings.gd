extends SceneTree
## Real-window review of M11: open the buildings panel with N, buy a coop with
## key 1, upgrade it with key 7, and watch the effect change the animal output.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_buildings.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_buildings_"

var _main: Node = null
var _placed := 0
var _upgraded := 0


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
	var bus := root.get_node_or_null(^"EventBus")
	bus.connect(&"building_placed", func(_id: StringName, _slot: int) -> void: _placed += 1)
	bus.connect(&"building_upgraded", func(_id: StringName, _slot: int, _level: int) -> void: _upgraded += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var state: Node = _main.get("player_state")
	var buildings: Node = _main.get("building_service")
	var panel: CanvasLayer = _main.get("building_panel")
	if state == null or buildings == null or panel == null:
		printerr("[play] missing buildings service or panel")
		quit(1)
		return
	state.get("wallet").call("set_gold", 5000)
	await _key(KEY_N)
	await _settle(4)
	if not bool(panel.visible):
		printerr("[play] N did not open the buildings panel")
		quit(1)
		return
	await _shot(SHOT + "01_panel.png")
	await _key(KEY_1)
	await _settle(6)
	var base := int(buildings.call("effect", &"product"))
	if _placed != 1 or base <= 0:
		printerr("[play] key 1 did not place a working building")
		quit(1)
		return
	print("[play] building placed; product effect = %d" % base)
	await _shot(SHOT + "02_placed.png")
	await _key(KEY_7)
	await _settle(6)
	var upgraded_effect := int(buildings.call("effect", &"product"))
	if _upgraded != 1 or upgraded_effect != base * 2:
		printerr("[play] key 7 did not upgrade the building (effect %d -> %d)" % [
			base, upgraded_effect,
		])
		quit(1)
		return
	print("[play] building upgraded; product effect = %d" % upgraded_effect)
	await _shot(SHOT + "03_upgraded.png")
	await _key(KEY_N)
	await _settle(4)
	if bool(panel.visible):
		printerr("[play] N did not close the panel")
		quit(1)
		return
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
