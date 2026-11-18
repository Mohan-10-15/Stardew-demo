extends SceneTree
## Real-window review of the rest of M7: build a machine, run it, cook at the
## stove, and unlock a purchased animal.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_machines.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_machines_"

var _main: Node = null
var _placed := 0
var _cooked := 0
var _bought := 0


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
	bus.connect(&"machine_placed", func(_id: StringName, _slot: int) -> void: _placed += 1)
	bus.connect(&"dish_cooked", func(_id: StringName, _out: StringName) -> void: _cooked += 1)
	bus.connect(&"animal_purchased", func(_id: StringName, _cost: int) -> void: _bought += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var state: Node = _main.get("player_state")
	var machines: Node = _main.get("machine_service")
	var panel: CanvasLayer = _main.get("machine_panel")
	var cooking: Node = _main.get("cooking_service")
	var animals: Node = _main.get("animal_service")
	if state == null or machines == null or panel == null or cooking == null or animals == null:
		printerr("[play] missing homestead services")
		quit(1)
		return
	var wallet: Object = state.get("wallet")
	var bag: Object = state.get("inventory")
	wallet.call("set_gold", 2000)
	await _key(KEY_B)
	await _settle(4)
	if not bool(panel.visible):
		printerr("[play] B did not open the build panel")
		quit(1)
		return
	await _shot(SHOT + "01_build_panel.png")
	await _key(KEY_1)
	await _settle(4)
	if _placed != 1:
		printerr("[play] the furnace was not placed")
		quit(1)
		return
	print("[play] furnace placed on pad 0")
	bag.call("add", &"copper_ore", 1)
	machines.call("load_from_bag", 0)
	bus.emit_signal(&"day_started", 2)
	bus.emit_signal(&"day_started", 3)
	var before: int = int(bag.call("count", &"iron_ore"))
	machines.call("collect", 0)
	if int(bag.call("count", &"iron_ore")) != before + 1:
		printerr("[play] the furnace produced no iron")
		quit(1)
		return
	print("[play] furnace produced iron after two days")
	await _shot(SHOT + "02_machine.png")

	bag.call("add", &"wild_berry", 2)
	if not bool(cooking.call("cook", &"berry_jam")) or _cooked != 1:
		printerr("[play] the stove did not cook")
		quit(1)
		return
	print("[play] cooked berry jam")
	bus.emit_signal(&"item_purchased", &"animal_goat", 1, 700)
	if _bought != 1 or not bool(animals.call("owns", &"goat")):
		printerr("[play] buying the goat did not unlock it")
		quit(1)
		return
	print("[play] goat purchased and unlocked")
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
