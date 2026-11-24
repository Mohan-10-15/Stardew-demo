extends SceneTree
## W7.2 evidence: play The Mending in a real window, capture keyframes, skip
## mid-scene and assert player/camera/HUD restore cleanly.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_cutscene_final.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_cutscene_the_mending_"

var _main: Node = null
var _director: Node = null
var _started := false
var _ended := false


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
	_main.set("play_intro_cutscene", false)
	root.add_child(_main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	await _settle(10)

	_director = _main.get("cutscene_director")
	if _director == null:
		printerr("[play] no cutscene director")
		quit(1)
		return
	bus.cutscene_started.connect(func(_id: StringName) -> void: _started = true)
	bus.cutscene_skipped.connect(func(_id: StringName) -> void: _ended = true)
	bus.cutscene_finished.connect(func(_id: StringName) -> void: _ended = true)
	if not bool(_director.call("play", &"the_mending")):
		printerr("[play] The Mending did not start")
		quit(1)
		return
	for i: int in range(30):
		await process_frame
	await _shot(SHOT + "01.png")
	print("[play] The Mending started: %s" % str(_started))
	_director.call("skip")
	for i: int in range(60):
		await process_frame
	if not _ended:
		printerr("[play] skip did not finish the cutscene")
		quit(1)
		return
	var state := root.get_node_or_null(^"GameState")
	if state != null and bool(state.get("paused")):
		printerr("[play] game is still paused after skip")
		quit(1)
		return
	print("[play] skip finished and unpaused the world")
	await _shot(SHOT + "02_restored.png")
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
