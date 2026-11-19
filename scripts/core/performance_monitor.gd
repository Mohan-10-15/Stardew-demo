class_name PerformanceMonitor
extends Node
## Samples real frame times and static memory so M18 is a measurement, not a
## promise. Always on but deliberately cheap: one float per frame, one monitor
## read every 30 frames, and a bounded ring buffer so a long session cannot
## make the profiler itself the leak it is looking for.
##
## Boundaries are *marked* by whoever crosses one (a region transition, a scene
## swap). The report then says how bad the worst frame around a marked crossing
## was, which is the only honest way to claim "no spike when crossing".

const WINDOW := 600
const MEMORY_EVERY := 30
## A frame longer than this is a spike. 100 ms is six missed 60 Hz frames —
## generous enough not to fire on a garbage collection, short enough to catch
## a synchronous resource load.
const SPIKE_MS := 100.0

var samples: Array[float] = []
var _memory: Array[float] = []
var _frame := 0
var _spikes := 0
var _worst_ms := 0.0
var _boundary_worst_ms := 0.0
var _boundary_until: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


func _process(delta: float) -> void:
	var ms := maxf(delta * 1000.0, 0.0)
	samples.append(ms)
	if samples.size() > WINDOW:
		samples.remove_at(0)
	_worst_ms = maxf(_worst_ms, ms)
	if ms > SPIKE_MS:
		_spikes += 1
	# A boundary mark applies to the next second of frames: that is long enough
	# to include a deferred load without letting an unrelated spike count.
	if _frame <= _boundary_until:
		_boundary_worst_ms = maxf(_boundary_worst_ms, ms)
	_frame += 1
	if _frame % MEMORY_EVERY == 0:
		_memory.append(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0)
		if _memory.size() > WINDOW / MEMORY_EVERY:
			_memory.remove_at(0)


## Call at the moment a transition starts. A new mark restarts the 60-frame
## observation window, so the report always describes the most recent crossing.
func mark_boundary(_label: StringName) -> void:
	_boundary_until = _frame + 60
	_boundary_worst_ms = 0.0


func reset() -> void:
	samples.clear()
	_memory.clear()
	_boundary_until = -1
	_frame = 0
	_spikes = 0
	_worst_ms = 0.0
	_boundary_worst_ms = 0.0


func report() -> Dictionary:
	var count := samples.size()
	if count == 0:
		return {"frames": 0, "fps": 0.0, "fps_p05": 0.0, "worst_ms": 0.0,
			"spikes": 0, "mem_start_mb": 0.0, "mem_now_mb": 0.0,
			"mem_growth_mb": 0.0, "boundary_worst_ms": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for ms: float in samples:
		total += ms
	var average := total / float(count)
	# 5th percentile of FPS is the slowest 5% of frames turned into a rate.
	var p05_index: int = clampi(int(float(count) * 0.05), 0, count - 1)
	var slow_ms: float = sorted[count - 1 - p05_index]
	var start := _memory[0] if not _memory.is_empty() else 0.0
	var now := _memory[_memory.size() - 1] if not _memory.is_empty() else 0.0
	return {
		"frames": count,
		"fps": 1000.0 / average if average > 0.0 else 0.0,
		"fps_p05": 1000.0 / slow_ms if slow_ms > 0.0 else 0.0,
		"worst_ms": _worst_ms,
		"spikes": _spikes,
		"mem_start_mb": start,
		"mem_now_mb": now,
		"mem_growth_mb": now - start,
		"boundary_worst_ms": _boundary_worst_ms,
	}


static func find(start: Node) -> PerformanceMonitor:
	if start == null:
		return null
	if start is PerformanceMonitor:
		return start as PerformanceMonitor
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null
