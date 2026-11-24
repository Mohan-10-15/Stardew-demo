extends TestSuite
## W7.2: every authored scene validates and the key set-pieces exist.

func get_cases() -> Array[StringName]:
	return [&"all_cutscenes_validate", &"the_key_set_pieces_exist"]


func _run(case: StringName) -> Dictionary:
	var report := CutsceneValidator.validate()
	match case:
		&"all_cutscenes_validate":
			var errors: Array = report.get("errors", [])
			if not errors.is_empty():
				return fail(case, "%d errors: %s" % [
					errors.size(), str(errors.slice(0, 3)),
				])
			return succeeded(case, "%d authored, %.1f s combined" % [
				int(report.get("real", 0)), float(report.get("duration", 0.0)),
			])
		&"the_key_set_pieces_exist":
			var script := load("res://scripts/cutscenes/cutscene_registry.gd") as GDScript
			for id: StringName in [&"intro", &"first_village", &"the_mending",
					&"credits_roll", &"daily_collapse", &"frost_arrives"]:
				if script.call("cutscene_for", id) == null:
					return fail(case, "%s is missing" % id)
			return succeeded(case, "intro, first village, Mending, credits, collapse, frost")
	return fail(case, "no case implementation for %s" % case)
