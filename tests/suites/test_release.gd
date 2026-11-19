extends TestSuite
## M20: the things a release can actually be checked for here — a working
## front door, documented assets, no stubs and no reachable cheats. Export
## templates are unavailable on this machine; that limitation is documented in
## README.md rather than hidden behind a ticked box.

const LICENSES := "res://docs/ASSET_LICENSES.md"
const README := "res://README.md"
const LAUNCHER := "res://Hollowbrook.exe"
const LAUNCHER_SOURCE := "res://launcher/Program.cs"
const CHEAT_ACTIONS: Array[StringName] = [
	&"cheat", &"cheats", &"godmode", &"god_mode", &"noclip", &"give_item",
	&"add_gold", &"teleport", &"debug_menu",
]


func get_cases() -> Array[StringName]:
	return [
		&"the_clickable_launcher_is_present",
		&"every_asset_pack_is_licensed",
		&"no_todos_or_fixmes_remain_in_shipped_scripts",
		&"no_debug_cheat_action_is_bound",
		&"the_readme_documents_how_to_run_and_validate",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"the_clickable_launcher_is_present":
			return _t_launcher(case)
		&"every_asset_pack_is_licensed":
			return _t_licenses(case)
		&"no_todos_or_fixmes_remain_in_shipped_scripts":
			return _t_stubs(case)
		&"no_debug_cheat_action_is_bound":
			return _t_cheats(case)
		&"the_readme_documents_how_to_run_and_validate":
			return _t_readme(case)
	return fail(case, "no case implementation for %s" % case)


func _t_launcher(c: StringName) -> Dictionary:
	if not FileAccess.file_exists(LAUNCHER):
		return fail(c, "no clickable Hollowbrook.exe")
	if not FileAccess.file_exists(LAUNCHER_SOURCE):
		return fail(c, "the launcher has no source to rebuild it from")
	var source := _read(LAUNCHER_SOURCE)
	if not source.contains("Godot_v4.5-stable_win64_console.exe"):
		return fail(c, "the launcher no longer starts the bundled engine")
	if not source.contains("--rendering-driver"):
		return fail(c, "the launcher dropped the OpenGL driver argument")
	return succeeded(c, "EXE and its source both present")


func _t_licenses(c: StringName) -> Dictionary:
	var text := _read(LICENSES)
	if text.is_empty():
		return fail(c, "no asset licence document")
	for needle: String in ["KayKit", "Quaternius", "CC0", "itch.io"]:
		if not text.contains(needle):
			return fail(c, "licence document is missing %s" % needle)
	for path: String in [
		"assets/models/kaykit/Characters/",
		"assets/models/kaykit/Addons/",
		"assets/models/quaternius/FarmBuildings/",
		"assets/models/quaternius/NaturePack/",
	]:
		if not text.contains(path):
			return fail(c, "licence document does not trace %s" % path)
	return succeeded(c, "all four shipped packs traced with source and licence")


func _t_stubs(c: StringName) -> Dictionary:
	var files: Array[String] = []
	_collect_scripts("res://scripts", files)
	if files.is_empty():
		return fail(c, "no shipped scripts found")
	for path: String in files:
		var text := _read(path)
		if text.contains("TODO") or text.contains("FIXME"):
			return fail(c, "%s still has a TODO/FIXME" % path)
	return succeeded(c, "%d shipped scripts clean" % files.size())


func _t_cheats(c: StringName) -> Dictionary:
	for action: StringName in CHEAT_ACTIONS:
		if InputMap.has_action(action):
			return fail(c, "cheat action %s is bound" % action)
	if not InputMap.has_action(&"save_game") or not InputMap.has_action(&"load_game"):
		return fail(c, "ordinary save/load actions went missing")
	return succeeded(c, "no cheat actions; F5/F9 and F2 remain ordinary tools")


func _t_readme(c: StringName) -> Dictionary:
	var text := _read(README)
	if text.is_empty():
		return fail(c, "no README")
	for needle: String in [
		"Hollowbrook.exe", "check.ps1", "tests passing", "F2", "ASSET_LICENSES.md",
	]:
		if not text.contains(needle):
			return fail(c, "README is missing %s" % needle)
	return succeeded(c, "README covers launch, validation and controls")


func _collect_scripts(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_scripts(path, out)
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
