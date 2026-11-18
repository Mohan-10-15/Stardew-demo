extends SceneTree
## Real-window review of seasons: the grass turns and winter ends the crop.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_seasons.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_season_"

var _main: Node = null
var _withered := 0


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
	bus.connect(&"crop_withered", func(_t: Vector2i, _id: StringName) -> void: _withered += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var clock: Node = _find_clock(_main)
	var farm: Node = _main.get("farm_service")
	var player: Node3D = _main.get("player")
	if clock == null or farm == null or player == null:
		printerr("[play] missing clock, farm or player")
		quit(1)
		return
	clock.set("running", false)
	player.global_position = Vector3(0, 0.4, -8)
	await _settle(8)
	await _shot(SHOT + "01_spring.png")
	clock.time.season = WorldTime.Season.WINTER
	bus.emit_signal(&"season_changed", WorldTime.Season.WINTER)
	bus.emit_signal(&"day_started", 60)
	await _settle(8)
	await _shot(SHOT + "02_winter.png")
	print("[play] winter arrived; %d crop(s) withered" % _withered)
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
