extends SceneTree
## Real-window review of the M7 homestead loop: craft at the panel, feed the
## coop, then advance a day and collect what the hen made.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_homestead.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_homestead_"

var _main: Node = null
var _crafted := 0
var _fed := 0
var _collected := 0


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
	bus.connect(&"craft_succeeded", func(_r: StringName, _o: StringName, _c: int) -> void: _crafted += 1)
	bus.connect(&"animal_fed", func(_a: StringName, _i: StringName) -> void: _fed += 1)
	bus.connect(&"animal_product_collected", func(_a: StringName, _i: StringName, _n: int) -> void: _collected += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var state: Node = _main.get("player_state")
	var panel: CanvasLayer = _main.get("crafting_panel")
	var animals: Node = _main.get("animal_service")
	if state == null or panel == null or animals == null:
		printerr("[play] missing homestead services")
		quit(1)
		return
	var bag: Object = state.get("inventory")
	bag.call("add", &"parsnip", 2)
	await _key(KEY_C)
	await _settle(4)
	if not bool(panel.visible):
		printerr("[play] C did not open the crafting panel")
		quit(1)
		return
	await _shot(SHOT + "01_crafting_panel.png")
	await _key(KEY_3)
	await _settle(4)
	if _crafted != 1:
		printerr("[play] the number key did not craft")
		quit(1)
		return
	print("[play] crafted parsnip seeds with key 3")
	bag.call("add", &"spring_onion", 1)
	animals.call("feed", &"hen")
	bus.emit_signal(&"day_started", 2)
	await _settle(4)
	animals.call("collect", &"hen")
	if _fed != 1 or _collected != 1:
		printerr("[play] the coop loop did not complete")
		quit(1)
		return
	print("[play] hen fed and one egg collected")
	var coop := _main.get_node_or_null(^"World/ChickenCoop")
	if coop != null:
		var player: Node3D = _main.get("player")
		player.global_position = coop.global_position + Vector3(0, 0.4, 3)
		await _settle(6)
	await _shot(SHOT + "02_coop.png")
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
