extends SceneTree
## Headless test harness.
##
## Discovers every `TestSuite` subclass in `tests/suites/` and runs it.
##
## Run:
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Exits with code 0 when every case passes, 1 otherwise.

const SUITE_DIR := "res://tests/suites"


func _initialize() -> void:
	# Autoloads are added to the root *after* _initialize(), so their _ready()
	# has not run yet. Wait one frame before touching anything the autoloads own.
	await process_frame
	await process_frame
	_run_all()


func _run_all() -> void:
	var passed := 0
	var failed := 0
	var skipped_suites: Array[String] = []
	var failures: Array[String] = []

	var suites := _discover_suites(SUITE_DIR, skipped_suites)
	if suites.is_empty():
		printerr("[tests] no suites found in %s" % SUITE_DIR)
		quit(1)
		return

	for suite_script: GDScript in suites:
		var suite = suite_script.new()
		suite.suite_name = suite_script.resource_path.get_file().get_basename()
		suite.tree = self
		print("\n=== %s ===" % suite.suite_name)

		# A broken suite must fail loudly instead of aborting the loop and
		# leaving the process hanging with quit() never reached.
		var cases: Array[Dictionary] = await suite.run_all()

		for entry: Dictionary in cases:
			if bool(entry["passed"]):
				passed += 1
				print("  [PASS] %s%s" % [
					entry["name"],
					"" if String(entry.get("message", "")) == "" else "  (%s)" % entry["message"],
				])
			else:
				failed += 1
				failures.append("%s :: %s -- %s" % [
					suite.suite_name, entry["name"], entry.get("message", ""),
				])
				printerr("  [FAIL] %s -- %s" % [entry["name"], entry.get("message", "")])

	print("\n----------------------------------------")
	if skipped_suites.size() > 0:
		# Surface broken suites before the totals so they cannot be overlooked.
		failed += skipped_suites.size()
		print("Suites that failed to compile: %s" % ", ".join(skipped_suites))
	print("passed: %d   failed: %d" % [passed, failed])
	if failed > 0:
		print("\nFailures:")
		for s: String in skipped_suites:
			print("  - %s (failed to compile)" % s)
		for f: String in failures:
			print("  - %s" % f)
		quit(1)
	else:
		print("All tests passed.")
		quit(0)


func _discover_suites(dir_path: String, skipped: Array[String]) -> Array[GDScript]:
	var out: Array[GDScript] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".gd") and not entry_name.begins_with("_"):
			var res := load(dir_path + "/" + entry_name)
			# can_instantiate() is false when the script failed to compile,
			# which would otherwise produce a null script and a confusing error.
			if res is GDScript and (res as GDScript).can_instantiate():
				out.append(res)
			elif res is GDScript:
				# A suite that cannot compile is a hard failure, never a skip.
				# Reporting it as "skipped" let 21 integration cases vanish while
				# the run still claimed every test passed.
				printerr("[tests] BROKEN (failed to compile): %s" % entry_name)
				skipped.append(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: GDScript, b: GDScript) -> bool:
		return a.resource_path < b.resource_path
	)
	return out