extends SceneTree
## Measures real frame times and memory while crossing every region boundary.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_performance.gd
##
## This reports the actual numbers rather than asserting a hardware-dependent
## 60 FPS. The assertions are on the things the game controls: no huge spike at
## a crossing, and no runaway memory growth over the session.

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_perf_"

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

	var monitor: Node = _main.get("performance_monitor")
	var player: Node3D = _main.get("player")
	var world: Node = _main.get("world")
	if monitor == null or player == null or world == null:
		printerr("[play] missing monitor, player or world")
		quit(1)
		return
	monitor.call("reset")
	await _settle(40)

	var regions: Array[StringName] = [&"farm", &"village", &"forest", &"pond", &"farm"]
	for region: StringName in regions:
		var centre: Vector3 = world.call("get_region_centre", region)
		monitor.call("mark_boundary", region)
		# Walk rather than teleport: the frames in between are what a spike would
		# show up in, and a teleport would measure nothing but one bad frame.
		var from := player.global_position
		for step: int in range(20):
			var t := float(step + 1) / 20.0
			player.global_position = from.lerp(centre + Vector3(0, 1.2, 0), t)
			await process_frame
		await _settle(6)
	print("[play] crossed %d region boundaries" % regions.size())

	# A long idle session: 400 more frames of NPCs, weather and the clock.
	for _i: int in range(400):
		await process_frame
	var r: Dictionary = monitor.call("report")
	var fps := float(r.get("fps", 0.0))
	var worst := float(r.get("worst_ms", 0.0))
	var crossing := float(r.get("boundary_worst_ms", 0.0))
	var growth := float(r.get("mem_growth_mb", 0.0))
	print("[play] frames=%d avg=%.1f FPS p05=%.1f FPS worst=%.1f ms" % [
		int(r.get("frames", 0)), fps, float(r.get("fps_p05", 0.0)), worst,
	])
	print("[play] worst frame around a boundary=%.1f ms" % crossing)
	print("[play] static memory %+.1f MB over the session" % growth)

	if crossing > 250.0:
		printerr("[play] a region crossing caused a %.0f ms spike" % crossing)
		quit(1)
		return
	# Screenshots are synchronous and would pollute the frame-time window.
	await _shot(SHOT + "01_after_walk.png")
	if growth > 96.0:
		printerr("[play] memory grew %.0f MB" % growth)
		quit(1)
		return
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
