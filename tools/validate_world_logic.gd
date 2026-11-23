extends SceneTree
## Headless content-graph check. Run:
##   Godot --headless --path . --script res://tools/validate_world_logic.gd

func _initialize() -> void:
	var report := WorldLogicValidator.validate()
	print("[logic] nodes=%d edges=%d" % [
		int(report.get("nodes", 0)), int(report.get("edges", 0)),
	])
	var errors: Array = report.get("errors", [])
	if errors.is_empty():
		print("[logic] OK — no dangling ids")
	else:
		for error: String in errors:
			printerr("[logic] %s" % error)
	quit(0 if bool(report.get("ok", false)) else 1)
