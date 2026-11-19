extends SceneTree
## Prints the real two-year economy sweep and a two-year idle check in a window.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_balance.gd

const MAIN := "res://scenes/core/main.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	# Loaded by path: naming the class here would pull its registry dependencies
	# into this --script tool's compile, where the Log autoload is not yet an
	# identifier (see AGENTS.md, "Two Godot-specific traps").
	var report_script := load("res://scripts/sim/balance_report.gd") as Script
	var report: Dictionary = report_script.call("sweep")
	if not bool(report.get("ok", false)):
		printerr("[play] sweep failed: %s" % str(report.get("reason", "?")))
		quit(1)
		return
	print("[play] two-year sweep over %d crops, %d days" % [
		(report.get("crop_ids", []) as Array).size(), 112,
	])
	for entry: Dictionary in report.get("strategies", []):
		print("[play]   %-14s end gold %8.0f  tool gates %s" % [
			String(entry.get("id", "?")), float(entry.get("end_gold", 0.0)),
			str(entry.get("tool_days", [])),
		])

	var packed := load(MAIN) as PackedScene
	var main := packed.instantiate()
	main.set("show_title_on_boot", false)
	root.add_child(main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var state: Node = main.get("player_state")
	var wallet: Object = state.get("wallet")
	var before: int = int(wallet.get("gold"))
	for day: int in range(112):
		bus.emit_signal(&"day_started", day + 1)
		if day % 32 == 0:
			await process_frame
	var after: int = int(wallet.get("gold"))
	print("[play] idle two years: %d -> %d gold" % [before, after])
	if after != before:
		printerr("[play] idling printed money")
		quit(1)
		return
	print("[play] PASS")
	quit(0)
