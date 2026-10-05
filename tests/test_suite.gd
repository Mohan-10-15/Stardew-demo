class_name TestSuite
extends RefCounted
## Base class for automated test suites.
##
## A suite is a plain `.gd` file in `tests/suites/` extending this class. The
## harness (`tests/run_tests.gd`) discovers suites automatically, so adding
## tests means dropping in a new file — there is no registry to update.
##
##     extends TestSuite
##
##     func get_cases() -> Array[StringName]:
##         return [&"addition_works"]
##
##     func _run(case: StringName) -> Dictionary:
##         return check_equals(case, 1 + 1, 2)
##
## `_run` must return the result of exactly one `check_*` call, which becomes
## `{name, passed, message}`.

var suite_name: StringName = &"unnamed"

## Injected by the harness before `run_all()` so suites can reach the tree root.
var tree: SceneTree = null


func root() -> Node:
	if tree != null:
		return tree.root
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


func autoload(name: StringName) -> Node:
	var r := root()
	return null if r == null else r.get_node_or_null(NodePath(String(name)))


## Override: names of the cases this suite covers.
func get_cases() -> Array[StringName]:
	return []


## Override: execute a single synchronous case. Must return one `check_*`
## result. Suites that need to step physics should implement `_run_async`
## instead — a coroutine cannot be returned from a synchronous function.
func _run(_case: StringName) -> Dictionary:
	return fail(_case, "suite did not implement _run() or _run_async()")


## Override: execute a case that needs to await frames. Has priority over
## `_run` when [method is_async] returns true.
func _run_async(_case: StringName) -> Dictionary:
	return fail(_case, "suite did not implement _run_async()")


## Override: return true when cases must be dispatched through `_run_async`.
## Explicit rather than reflection-based so a typo cannot silently skip a case.
func is_async() -> bool:
	return false


## Called once before any case runs.
func setup() -> void:
	pass


## Called once after all cases have run.
func teardown() -> void:
	pass


## Runs every case and returns the collected results. Coroutine: awaits
## `_run_async` when the suite defines it.
func run_all() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var uses_async := is_async()
	setup()
	for case: StringName in get_cases():
		var entry: Dictionary = {}
		if uses_async:
			entry = await _run_async(case)
		else:
			entry = _run(case)
		if entry.is_empty() or not entry.has("passed"):
			entry = fail(case, "case produced no result")
		elif not entry.has("name"):
			entry["name"] = String(case)
		results.append(entry)
	teardown()
	return results


func succeeded(case: StringName, message: String = "") -> Dictionary:
	return {"name": String(case), "passed": true, "message": message}


func fail(case: StringName, message: String = "") -> Dictionary:
	return {"name": String(case), "passed": false, "message": message}


## Marks a case as intentionally not runnable here (for example, an autoload it
## depends on is absent). Reported distinctly from a pass so it can never
## quietly satisfy a requirement.
func skip(case: StringName, message: String = "") -> Dictionary:
	return {"name": String(case), "passed": true, "skipped": true, "message": message}


## [param message] replaces the generated text when a failure is more informative in the
## author's words than in "expected X but got Y" — "the purse is wrong" says which of four
## gold assertions in one test failed, while four identical generated strings do not.
func check_equals(case: StringName, actual: Variant, expected: Variant,
		message: String = "") -> Dictionary:
	if _deep_equals(actual, expected):
		return succeeded(case)
	return fail(case, message if message != "" else "expected %s but got %s" % [
		str(expected), str(actual),
	])


func check_not_equals(case: StringName, actual: Variant, unexpected: Variant,
		message: String = "") -> Dictionary:
	if not _deep_equals(actual, unexpected):
		return succeeded(case)
	return fail(case, message if message != "" else "expected value different from %s"
		% str(unexpected))


func check_not_null(case: StringName, value: Variant, message: String = "") -> Dictionary:
	if value != null:
		return succeeded(case)
	return fail(case, message if message != "" else "expected non-null value")


func check_null(case: StringName, value: Variant, message: String = "") -> Dictionary:
	if value == null:
		return succeeded(case)
	return fail(case, message if message != "" else "expected null but got %s" % str(value))


func check_true(case: StringName, value: bool, message: String = "") -> Dictionary:
	if value:
		return succeeded(case)
	return fail(case, message if message != "" else "expected true but got false")


func check_false(case: StringName, value: bool, message: String = "") -> Dictionary:
	if not value:
		return succeeded(case)
	return fail(case, message if message != "" else "expected false but got true")


func check_greater(case: StringName, actual: float, threshold: float) -> Dictionary:
	if actual > threshold:
		return succeeded(case)
	return fail(case, "expected > %s but got %s" % [str(threshold), str(actual)])


func check_less(case: StringName, actual: float, threshold: float) -> Dictionary:
	if actual < threshold:
		return succeeded(case)
	return fail(case, "expected < %s but got %s" % [str(threshold), str(actual)])


func check_in_range(case: StringName, actual: float, lo: float, hi: float) -> Dictionary:
	if actual >= lo and actual <= hi:
		return succeeded(case)
	return fail(case, "expected %s in [%s, %s]" % [str(actual), str(lo), str(hi)])


func check_approx(case: StringName, actual: float, expected: float, tolerance: float = 0.001) -> Dictionary:
	if absf(actual - expected) <= tolerance:
		return succeeded(case)
	return fail(case, "expected %s +/- %s but got %s" % [str(expected), str(tolerance), str(actual)])


func check_has_method(case: StringName, obj: Object, method: StringName) -> Dictionary:
	if obj != null and obj.has_method(method):
		return succeeded(case)
	return fail(case, "object %s has no method '%s'" % [str(obj), method])


func check_signal_exists(case: StringName, obj: Object, signal_name: StringName) -> Dictionary:
	if obj != null and obj.has_signal(signal_name):
		return succeeded(case)
	return fail(case, "object %s has no signal '%s'" % [str(obj), signal_name])


func _deep_equals(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Array or a is Dictionary:
		return JSON.stringify(a) == JSON.stringify(b)
	return a == b