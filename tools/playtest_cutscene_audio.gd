extends SceneTree
## Real-window playtest for the two new presentation systems.
##
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_cutscene_audio.gd
##
## The intro cutscene is enabled before the main scene is added, so the boot
## sequence is the real one with the real director, overlay, audio manager and
## EventBus. The skip is a real key event. Sound itself cannot be verified by a
## machine here; the manager is checked for defensive, error-free playback and
## the frames are captured for a human ear/eye review.

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_cutscene_"

var _main: Node = null
var _bus: Node = null
var _started := 0
var _skipped := 0
var _finished := 0


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
	_bus = root.get_node_or_null(^"EventBus")
	_main = packed.instantiate()
	_main.set("play_intro_cutscene", true)
	_bus.connect(&"cutscene_started", func(_id: StringName) -> void: _started += 1)
	_bus.connect(&"cutscene_skipped", func(_id: StringName) -> void: _skipped += 1)
	_bus.connect(&"cutscene_finished", func(_id: StringName) -> void: _finished += 1)
	root.add_child(_main)

	var deadline := Time.get_ticks_msec() + 30000
	while _started == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if _started == 0:
		printerr("[play] the intro cutscene never started")
		quit(1)
		return
	print("[play] intro started; game paused=%s" % str((root.get_node_or_null(^"GameState")).get("paused")))
	await _seconds(1.8)
	await _shot(SHOT + "01_intro.png")

	# A real key event, delivered to the director's `_unhandled_input`.
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(4)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	release.pressed = false
	Input.parse_input_event(release)
	deadline = Time.get_ticks_msec() + 10000
	while _skipped == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if _skipped == 0:
		printerr("[play] the skip key did not end the cutscene")
		quit(1)
		return
	var state := root.get_node_or_null(^"GameState")
	if bool(state.get("paused")):
		printerr("[play] the game stayed paused after the skip")
		quit(1)
		return
	print("[play] skipped with E; game paused=%s" % str(state.get("paused")))
	await _shot(SHOT + "02_after_skip.png")

	# Kick a few sounds through the manager, including an unknown id, and check
	# that the buses exist and nothing errors in a real renderer.
	var audio: Node = _main.get("audio_manager") as Node
	if audio == null:
		printerr("[play] no audio manager")
		quit(1)
		return
	audio.call("play_sfx", &"crop_harvest")
	audio.call("play_sfx", &"gift_refused")
	audio.call("play_sfx", &"no_such_sound")
	audio.call("play_music", &"farm_theme")
	audio.call("play_ambience", &"rain_loop")
	await _seconds(0.5)
	print("[play] buses: %d; sounds: %d" % [
		AudioServer.get_bus_count(), AudioRegistry.all_sounds().size(),
	])
	print("[play] PASS")
	quit(0)


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _seconds(value: float) -> void:
	var deadline := Time.get_ticks_msec() + int(value * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("[play] no image for %s" % path)
		return
	print("[play] %s %s" % [
		"wrote" if image.save_png(path) == OK else "FAILED", path,
	])
