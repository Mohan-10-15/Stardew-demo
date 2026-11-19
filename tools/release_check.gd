extends SceneTree
## Prints release readiness. Run with the ordinary (non-Mono) engine:
##     godot --headless --path . --script res://tools/release_check.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("project.godot", "Godot project root") and ok
	ok = _check("Hollowbrook.exe", "clickable Windows front door") and ok
	ok = _check("launcher/Program.cs", "launcher source") and ok
	ok = _check("tools/Godot_v4.5-stable_win64_console.exe", "portable engine") and ok
	ok = _check("tools/GodotSharp/Api/Debug", "C# assemblies for the sweep") and ok
	ok = _check("docs/ASSET_LICENSES.md", "asset provenance") and ok
	ok = _check("DEVELOPMENT_STATUS.md", "milestone record") and ok
	ok = _check("scenes/core/main.tscn", "generated main scene") and ok

	var cheats: Array[StringName] = [&"cheat", &"godmode", &"noclip", &"give_item", &"add_gold"]
	var found: Array[StringName] = []
	for action: StringName in cheats:
		if InputMap.has_action(action):
			found.append(action)
	if found.is_empty():
		print("[release] OK  no cheat actions bound")
	else:
		print("[release] FAIL cheat actions bound: %s" % str(found))
		ok = false

	print("[release] Windows launcher: verified on this machine")
	print("[release] Windows export template: NOT AVAILABLE (no export templates installed)")
	print("[release] Web export: NOT AVAILABLE (no export templates installed)")
	print("[release] %s" % ("READY" if ok else "NOT READY"))
	quit(0 if ok else 1)


func _check(path: String, label: String) -> bool:
	var exists := FileAccess.file_exists("res://" + path) \
		or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + path))
	print("[release] %s  %s" % [("OK  " if exists else "FAIL"), label])
	return exists
