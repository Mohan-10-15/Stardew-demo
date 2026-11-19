extends TestSuite
## M18: the profiler measures real frame times and bounded memory, and a long
## session with repeated day rollovers does not accumulate nodes or memory.

const MONITOR_SCRIPT := "res://scripts/core/performance_monitor.gd"
const MAIN := "res://scenes/core/main.tscn"

var _rig: Node3D = null
var _main: Node = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"the_monitor_samples_real_frames_and_memory",
		&"the_sample_window_stays_bounded",
		&"boundary_marks_are_measured",
		&"a_long_session_does_not_accumulate",
	]


func setup() -> void:
	_rig = null
	_main = null


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"the_monitor_samples_real_frames_and_memory":
			return await _t_sample()
		&"the_sample_window_stays_bounded":
			return await _t_bounded()
		&"boundary_marks_are_measured":
			return await _t_boundary()
		&"a_long_session_does_not_accumulate":
			return await _t_long()
	return fail(case, "no case implementation for %s" % case)


func _t_sample() -> Dictionary:
	var c := &"the_monitor_samples_real_frames_and_memory"
	var monitor := await _make_monitor()
	await _step(40)
	var data: Dictionary = monitor.call("report")
	if int(data.get("frames", 0)) < 30:
		return fail(c, "only %d frames sampled" % int(data.get("frames", 0)))
	if float(data.get("fps", 0.0)) <= 0.0:
		return fail(c, "FPS was not measured")
	if float(data.get("mem_now_mb", 0.0)) <= 0.0:
		return fail(c, "static memory was not measured")
	return succeeded(c, "%d frames, %.1f FPS, %.1f MB" % [
		int(data["frames"]), float(data["fps"]), float(data["mem_now_mb"]),
	])


func _t_bounded() -> Dictionary:
	var c := &"the_sample_window_stays_bounded"
	var monitor := await _make_monitor()
	var script := load(MONITOR_SCRIPT) as GDScript
	for _i: int in range(700):
		monitor.call("_process", 0.016)
	var samples: Array = monitor.get("samples")
	if samples.size() > int(script.get_script_constant_map().get("WINDOW", 600)):
		return fail(c, "the sample ring grew to %d entries" % samples.size())
	return succeeded(c, "%d samples after 700 frames — bounded" % samples.size())


func _t_boundary() -> Dictionary:
	var c := &"boundary_marks_are_measured"
	var monitor := await _make_monitor()
	monitor.call("mark_boundary", &"village")
	for _i: int in range(40):
		monitor.call("_process", 0.02)
	var data: Dictionary = monitor.call("report")
	if float(data.get("boundary_worst_ms", 0.0)) <= 0.0:
		return fail(c, "a marked crossing was not measured")
	return succeeded(c, "crossing worst frame %.1f ms" % float(data["boundary_worst_ms"]))


func _t_long() -> Dictionary:
	var c := &"a_long_session_does_not_accumulate"
	_reset_rig()
	var packed := load(MAIN) as PackedScene
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	root().add_child(_main)
	await _step(8)
	var monitor: Node = _main.get("performance_monitor")
	if monitor == null:
		return fail(c, "no performance monitor on main")
	var before := _main.get_child_count()
	var start_mem: float = float((monitor.call("report") as Dictionary).get("mem_now_mb", 0.0))
	var bus := autoload(&"EventBus")
	for day: int in range(120):
		bus.emit_signal(&"day_started", day + 1)
		if day % 20 == 0:
			await _step(2)
	await _step(10)
	var after := _main.get_child_count()
	if after > before + 2:
		return fail(c, "main grew from %d to %d children over 120 days" % [before, after])
	var data: Dictionary = monitor.call("report")
	var growth := float(data.get("mem_now_mb", 0.0)) - start_mem
	if growth > 64.0:
		return fail(c, "static memory grew %.1f MB" % growth)
	return succeeded(c, "120 days, children %d->%d, memory %+.1f MB" % [
		before, after, growth,
	])


func _make_monitor() -> Node:
	_ensure_rig()
	var monitor: Node = (load(MONITOR_SCRIPT) as GDScript).new()
	_rig.add_child(monitor)
	return monitor


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "PerformanceTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
