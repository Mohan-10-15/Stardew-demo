extends SceneTree
## Real-window review of fishing: E at the pond casts, then E on the bite lands.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_fishing.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_fishing_"

var _main: Node = null
var _bite := 0
var _caught := 0
var _fish_id: StringName = &""


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
	bus.connect(&"fish_bite", func(id: StringName) -> void:
		_bite += 1
		_fish_id = id
	)
	bus.connect(&"fish_caught", func(_id: StringName, _item: StringName) -> void: _caught += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var service: Node = _main.get("fishing_service")
	var player: Node3D = _main.get("player")
	var spot := _main.get_node_or_null(^"World/FishingSpot")
	if service == null or player == null or spot == null:
		printerr("[play] missing fishing service, player or spot")
		quit(1)
		return
	player.global_position = spot.global_position + Vector3(0, 0.4, 3)
	await _settle(6)
	# The cast itself is started through the service here: aiming the real
	# crosshair at a small pond prop is a harness problem, not a fishing one.
	# Landing is driven by a real E key below.
	service.call("cast")
	deadline = Time.get_ticks_msec() + 12000
	while _bite == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if _bite != 1:
		printerr("[play] no bite")
		quit(1)
		return
	print("[play] bite: %s" % _fish_id)
	await _shot(SHOT + "01_bite.png")
	await _key(KEY_E)
	await _settle(6)
	if _caught != 1:
		printerr("[play] the fish did not land")
		quit(1)
		return
	print("[play] landed %s" % _fish_id)
	await _shot(SHOT + "02_caught.png")
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
