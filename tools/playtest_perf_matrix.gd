extends SceneTree
## W7.6: a measured performance matrix in a real window. Reports min/avg FPS
## and p95 frame time for representative scenes. No thresholds are invented —
## the numbers are the evidence and the owner judges the target hardware.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_perf_matrix.gd

const MAIN := "res://scenes/core/main.tscn"

var _main: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[perf] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
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
	var monitor: PerformanceMonitor = PerformanceMonitor.find(root)
	var player: Node3D = _main.get("player")
	if monitor == null or player == null:
		printerr("[perf] missing monitor or player")
		quit(1)
		return

	await _measure("farm day", 180)
	player.global_position = Vector3(38, 1.2, 8)
	await _measure("village with cast", 180)
	bus.festival_started.emit(&"bloom_day")
	await _measure("festival", 180)
	bus.mine_entered.emit()
	await _measure("deep mines", 180)
	bus.festival_ended.emit(&"bloom_day")

	# The Mending: all twelve villagers gathered at the plinth with the
	# cutscene actually playing. This is the heaviest cutscene case in the
	# brief, so it gets measured rather than assumed from the festival number.
	# Fetch via the group and a dynamic call: naming the Npc class here would
	# pull npc.gd into this --script compile and hit the autoload/Log trap.
	var managers := get_nodes_in_group(&"npc_service")
	if managers.is_empty():
		printerr("[perf] no npc_service group")
		quit(1)
		return
	var npcs: Array = managers[0].call("npcs")
	if npcs.size() != 12:
		printerr("[perf] expected 12 villagers, found %d" % npcs.size())
		quit(1)
		return
	for i: int in range(npcs.size()):
		var angle := TAU * float(i) / float(npcs.size())
		npcs[i].global_position = Vector3(
			35.0 + cos(angle) * 4.0, 1.2, 5.0 + sin(angle) * 4.0)
	var director: Node = _main.get("cutscene_director")
	if director == null or not bool(director.call("play", &"the_mending")):
		printerr("[perf] the_mending did not start")
		quit(1)
		return
	await _measure("the mending x12", 180)
	director.call("skip")
	print("[perf] PASS")
	quit(0)




func _measure(label: String, frames: int) -> void:
	var monitor: PerformanceMonitor = PerformanceMonitor.find(root)
	monitor.reset()
	var times: Array[float] = []
	for _i: int in range(frames):
		await process_frame
		times.append(PerformanceMonitor.SPIKE_MS if false else 0.0)
	var report: Dictionary = monitor.report()
	var samples: PackedFloat32Array = monitor.samples
	var sorted: Array[float] = []
	for ms: float in samples:
		sorted.append(ms)
	sorted.sort()
	var p95: float = sorted[clampi(int(float(sorted.size()) * 0.95), 0,
		maxi(sorted.size() - 1, 0))] if not sorted.is_empty() else 0.0
	print("[perf] %-20s avg=%6.1f FPS  p05=%6.1f FPS  p95 frame=%5.1f ms  worst=%6.1f ms" % [
		label, float(report.get("fps", 0.0)), float(report.get("fps_p05", 0.0)),
		p95, float(report.get("worst_ms", 0.0)),
	])
