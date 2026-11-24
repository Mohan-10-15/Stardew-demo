extends SceneTree
## Headless cutscene content validation. Run:
##   Godot --headless --path . --script res://tools/validate_cutscenes.gd

func _initialize() -> void:
	var report := CutsceneValidator.validate()
	print("[cutscenes] %d total, %d authored, %.1f s combined" % [
		int(report.get("total", 0)), int(report.get("real", 0)),
		float(report.get("duration", 0.0)),
	])
	var errors: Array = report.get("errors", [])
	if errors.is_empty():
		print("[cutscenes] OK — no dangling ids, no overlong scene")
	else:
		for error: String in errors:
			printerr("[cutscenes] %s" % error)
	quit(0 if bool(report.get("ok", false)) else 1)
