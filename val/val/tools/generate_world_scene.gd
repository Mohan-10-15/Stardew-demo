extends SceneTree
## Headless tool: generates `scenes/world/world.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_world_scene.gd

const OUTPUT_PATH := "res://scenes/world/world.tscn"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "World"
	root.set_script(load("res://scripts/world/world_root.gd"))

	# Directional sun. Time of day / weather (Groups 6 and 23) will drive this.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	root.add_child(sun)

	# Sky and ambient. Group 6 replaces these with a day/night gradient.
	var sky := WorldEnvironment.new()
	sky.name = "Environment"
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.30, 0.53, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.82, 0.88)
	sky_material.ground_bottom_color = Color(0.24, 0.30, 0.22)
	sky_material.ground_horizon_color = Color(0.60, 0.68, 0.55)
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	sky.environment = env
	root.add_child(sky)

	for child: Node in [sun, sky]:
		child.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		printerr("[generate_world_scene] pack failed")
		quit(1)
		return
	var err := ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		printerr("[generate_world_scene] save failed: %d" % err)
		quit(1)
		return
	print("[generate_world_scene] wrote %s" % OUTPUT_PATH)
	quit(0)