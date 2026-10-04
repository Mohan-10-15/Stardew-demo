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

	# Directional sun. Weather (M9) will drive the rest of its look; the
	# day/night cycle writes energy, colour and elevation every tick.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(4, -38, 0)
	sun.light_energy = 0.55
	sun.light_color = Color(1.0, 0.82, 0.66)
	sun.shadow_enabled = true
	root.add_child(sun)

	# Sky and ambient. The day/night cycle lerps the sky colours and the ambient
	# energy as the clock moves; weather (M9) will layer on top.
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

	# --- Graphics quality --------------------------------------------------
	# After the environment and the sun, so its `_ready` finds both. It re-applies on
	# `settings_applied`, which is what makes the tier a *setting* rather than a value
	# frozen into this file at generation time.
	var graphics := Node.new()
	graphics.name = "Graphics"
	graphics.set_script(load("res://scripts/world/graphics_quality.gd"))
	root.add_child(graphics)

	# --- Day/night cycle ---------------------------------------------------
	# A child node rather than a script on the world root, so it subscribes and
	# unsubscribes with the world's own lifetime and can be removed in an editor
	# preview without touching anything else.
	var cycle := Node.new()
	cycle.name = "DayNightCycle"
	cycle.set_script(load("res://scripts/world/day_night_cycle.gd"))
	root.add_child(cycle)

	# --- Clock ------------------------------------------------------------
	# Added *after* the cycle on purpose. Godot calls `_ready` children-first in
	# tree order, so the cycle subscribes first and therefore sees the clock's
	# initial `time_minute_changed` rather than having to re-apply on its own.
	# The reverse order would leave the valley lit to the scene's saved sun
	# values until the first tick, one frame of wrong light on every boot.
	var clock := Node.new()
	clock.name = "TimeService"
	clock.set_script(load("res://scripts/time/time_service.gd"))
	root.add_child(clock)

	# --- Farm plot --------------------------------------------------------
	# 7 x 5 tiles at 2m, centred on the farm soil plane the builder lays down.
	# The builder draws the dirt; this is the tillable grid on top of it, so the
	# plot reads as part of the farm rather than a separate object dropped on it.
	var grid := Node3D.new()
	grid.name = "FarmGrid"
	grid.set_script(load("res://scripts/farming/farm_grid.gd"))
	grid.position = _farm_centre()
	root.add_child(grid)

	for child: Node in [sun, sky, graphics, cycle, clock, grid]:
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


## Where the tillable plot goes: the middle of the farm region, on the ground.
##
## Read off [WorldBuilder] dynamically rather than written as
## `WorldBuilder.REGION_FARM`. Naming the class here pulls `world_builder.gd`
## into this tool's compile, which pulls in `interactable.gd`, which references
## the `Log` autoload — and an autoload is not a global identifier in a
## `--script` run. The result is a compile error about logging in a file that has
## nothing to do with logging. See `AGENTS.md`, "Two Godot-specific traps".
##
## Dynamic access means a missing constant surfaces as a clear `null` here rather
## than as a compile failure three files away, so the constants are asserted
## rather than assumed.
func _farm_centre() -> Vector3:
	var builder: GDScript = load("res://scripts/world/world_builder.gd")
	var region: Variant = builder.get("REGION_FARM") if builder != null else null
	var ground: Variant = builder.get("GROUND_LEVEL") if builder != null else null
	if not region is Vector2 or not ground is float:
		printerr("[generate_world_scene] WorldBuilder constants missing; plot at origin")
		return Vector3.ZERO
	return Vector3((region as Vector2).x, ground, (region as Vector2).y)