extends SceneTree
## Real-window review of a festival: the square fills, the cast gathers, and
## attendance pays once.
##
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_festival.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_festival_"

var _main: Node = null
var _started := 0
var _attended := 0


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
	bus.connect(&"festival_started", func(_id: StringName) -> void: _started += 1)
	bus.connect(&"festival_attended", func(_id: StringName, _gold: int) -> void: _attended += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var clock: Node = _find_clock(_main)
	var service: Node = _main.get("festival_service")
	var player: Node3D = _main.get("player")
	if clock == null or service == null or player == null:
		printerr("[play] missing clock, festival service or player")
		quit(1)
		return
	clock.set("running", false)
	var festival := FestivalRegistry.festival_for(&"bloom_day")
	clock.time.season = festival.season
	clock.time.day_of_month = festival.day_of_month
	service.call("_check_date")
	await _settle(8)
	if _started != 1 or root.get_node_or_null(^"FestivalDecor") == null:
		printerr("[play] Bloom Day did not start in the world")
		quit(1)
		return
	print("[play] %s started; cast on gathering day" % festival.display_name)
	# Look at the square from the south so the lanterns and cast are visible.
	player.global_position = Vector3(38, 0.4, 20)
	player.call("set_yaw", PI if false else 0.0)
	await _settle(8)
	await _shot(SHOT + "01_square.png")

	player.global_position = Vector3(38, 0.4, 12)
	await _settle(8)
	if _attended != 1:
		printerr("[play] attendance did not fire")
		quit(1)
		return
	print("[play] attendance paid %dg" % festival.reward_gold)
	await _shot(SHOT + "02_attended.png")

	clock.time.day_of_month = festival.day_of_month + 1
	service.call("_check_date")
	await _settle(4)
	if root.get_node_or_null(^"FestivalDecor") != null:
		printerr("[play] the decorations were left behind")
		quit(1)
		return
	print("[play] festival ended; square cleared")
	await _shot(SHOT + "03_ended.png")
	print("[play] PASS")
	quit(0)


func _find_clock(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("sleep_until_morning"):
		return node
	for child: Node in node.get_children():
		var found := _find_clock(child)
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
