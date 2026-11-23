extends SceneTree
## Reproducible project setting changes for Update 2 W5, the way
## tools/rebuild_input_map.gd is for the input map. Run:
##   Godot --headless --path . --script res://tools/apply_project_settings.gd

const SETTINGS := {
	"physics/3d/physics_engine": "Jolt Physics",
	"physics/common/physics_interpolation": true,
}


func _initialize() -> void:
	for key: String in SETTINGS:
		var before: Variant = ProjectSettings.get_setting(key, null)
		ProjectSettings.set_setting(key, SETTINGS[key])
		print("[settings] %s: %s -> %s" % [
			key, str(before), str(ProjectSettings.get_setting(key)),
		])
	var err := ProjectSettings.save()
	if err != OK:
		printerr("[settings] save failed: %d" % err)
		quit(1)
		return
	print("[settings] saved project.godot")
	quit(0)
