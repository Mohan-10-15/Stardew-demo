extends SceneTree
## Renders every crop at three growth stages and saves a PNG, so the crop art can
## be *looked at* rather than assumed from a passing test.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/capture_crop_stages.gd
##
## ## Why every dependency is loaded by path
##
## A `--script` run compiles before autoloads register, so naming a `class_name`
## that reaches `Log` anywhere in its dependency graph fails to compile — the trap
## `AGENTS.md` warns about. [CropRegistry] logs through `Log`, and [SoilTile]
## publishes on `EventBus`, so neither is referenced by name here; both are
## `load()`ed and their statics called on the [GDScript] handle instead. No
## `CropData`/`CropRegistry`/`SoilTile` type annotations either, because an
## annotation is a compile-time reference and would reintroduce the problem.
##
## The tile's state is also set directly rather than through `till()`/`plant()`,
## which would emit on the missing `EventBus`. `refresh_visual()` — the function
## actually under test — touches no autoload, so the picture is still produced by
## the shipping code path.
##
## Output: `res://art_review_crop_stages.png`, which is `.gitignore`d. A screenshot
## of a review is not a game asset.

const OUTPUT_PATH := "res://art_review_crop_stages.png"
const TILE_SIZE := 2.0
## Day fractions to render: freshly planted, mid-season, ripe.
const STAGE_LABELS := ["planted", "growing", "ripe"]
const STAGE_DAYS := [0.0, 0.5, 1.0]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: GDScript = load("res://scripts/farming/crop_registry.gd")
	registry.ensure_loaded()
	var crops: Array = registry.all_crops()
	if crops.is_empty():
		printerr("[capture] no crops loaded")
		quit(1)
		return

	root.size = Vector2i(1800, 1400)
	_build_environment()

	var tile_script: GDScript = load("res://scripts/farming/soil_tile.gd")
	var stage := Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)

	# One row per crop, one column per growth stage. Tile 0 is left empty so the
	# tilled soil and its plate are in shot for comparison.
	var tile_script_ref := tile_script
	var built := 0
	for row: int in range(crops.size()):
		for column: int in range(STAGE_DAYS.size()):
			var tile: Node3D = tile_script_ref.new()
			tile.name = "%s_%s" % [crops[row].id, STAGE_LABELS[column]]
			tile.tile_index = Vector2i(column, row)
			stage.add_child(tile)
			tile.build_visuals(TILE_SIZE)
			tile.is_tilled = true
			tile.crop_id = crops[row].id
			var crop = crops[row]
			tile.growth_days = int(round(float(crop.days_to_grow) * float(STAGE_DAYS[column])))
			tile.refresh_visual()
			tile.position = Vector3(
				(float(column) - 1.0) * TILE_SIZE,
				0.0,
				float(row) * TILE_SIZE
			)
			built += 1

	var camera := Camera3D.new()
	root.add_child(camera)
	var centre := Vector3(0.0, 0.5, float(crops.size() - 1) * TILE_SIZE * 0.5)
	camera.position = centre + Vector3(0.0, float(crops.size()) * TILE_SIZE * 0.55, TILE_SIZE * 2.2)
	camera.look_at(centre, Vector3.UP)
	camera.fov = 60.0
	camera.current = true

	print("[capture] built %d tiles for %d crops" % [built, crops.size()])

	# Let the camera, materials and imported meshes settle before grabbing.
	for i: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null:
		printerr("[capture] no viewport image")
		quit(1)
		return
	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("[capture] save_png failed: %d" % err)
		quit(1)
		return
	print("[capture] wrote %s (%dx%d)" % [OUTPUT_PATH, image.get_width(), image.get_height()])
	quit(0)


## Enough light and sky for the flat-shaded pack to be readable. Two directional
## lights rather than one so a model's unlit side is not a solid black silhouette.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_material.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_material.ground_bottom_color = Color(0.3, 0.35, 0.3)
	sky_material.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.1
	root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(145.0), 0.0)
	fill.light_energy = 0.4
	root.add_child(fill)