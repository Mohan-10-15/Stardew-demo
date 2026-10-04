extends SceneTree
## Graphics playtest: boots the real main scene, reports what the renderer actually
## applied, and saves a screenshot per vantage point.
##
## Separate from `check.ps1` on purpose. Everything it prints is read back off live
## nodes, so a graphics setting that is written into a resource and never reaches the
## environment cannot pass here — which is the failure mode the whole graphics pass is
## exposed to.
##
##   & "tools\Godot_v4.5-stable_win64_console.exe" --path . --script res://tools/playtest_graphics.gd

const SHOTS := [
	{"name": "art_review_gfx_01_farm", "pos": Vector3(0, 2.4, -8), "yaw": 0.0},
	{"name": "art_review_gfx_02_pond", "pos": Vector3(-14, 3.0, 32), "yaw": 0.35},
	{"name": "art_review_gfx_03_village", "pos": Vector3(38, 2.6, -2), "yaw": -1.6},
	{"name": "art_review_gfx_04_forest", "pos": Vector3(-42, 2.6, 18), "yaw": 2.4},
	{"name": "art_review_gfx_05_ground_close", "pos": Vector3(6, 1.1, -14), "yaw": 0.9, "pitch": -0.55},
	{"name": "art_review_gfx_06_shoreline", "pos": Vector3(-14, 1.6, 26), "yaw": 0.0, "pitch": -0.2},
]


func _initialize() -> void:
	await process_frame
	# The main scene is instantiated by hand rather than found in the tree: a
	# `--script` run has no `run/main_scene`, so there is nothing to find.
	var packed := load("res://scenes/core/main.tscn") as PackedScene
	if packed == null:
		print("[playtest_graphics] FAIL no main scene")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	for _i: int in range(120):
		await process_frame
		if main.get_node_or_null(^"World") != null:
			break
	_report(main)
	await _shoot()
	print("[playtest_graphics] done")
	quit(0)


## Prints the live state of everything this pass claims to have changed.
func _report(main: Node) -> void:
	var world := main.get_node_or_null(^"World")
	if world == null:
		print("[playtest_graphics] no World")
		return
	var environment := _environment(world)
	if environment != null:
		print("[playtest_graphics] tonemap=%d exposure=%.2f" % [environment.tonemap_mode, environment.tonemap_exposure])
		print("[playtest_graphics] ssao=%s radius=%.2f intensity=%.2f" % [
			environment.ssao_enabled, environment.ssao_radius, environment.ssao_intensity,
		])
		print("[playtest_graphics] glow=%s bloom=%.3f threshold=%.2f" % [
			environment.glow_enabled, environment.glow_bloom, environment.glow_hdr_threshold,
		])
		print("[playtest_graphics] fog=%s density=%.4f sky_affect=%.2f" % [
			environment.fog_enabled, environment.fog_density, environment.fog_sky_affect,
		])
		print("[playtest_graphics] saturation=%.2f contrast=%.2f" % [
			environment.adjustment_saturation, environment.adjustment_contrast,
		])
	else:
		print("[playtest_graphics] no Environment on the world")
	var sun := world.get_node_or_null(^"Sun") as DirectionalLight3D
	if sun != null:
		print("[playtest_graphics] sun energy=%.2f shadows=%s mode=%d max_distance=%.0f" % [
			sun.light_energy, sun.shadow_enabled, sun.directional_shadow_mode,
			sun.directional_shadow_max_distance,
		])
	print("[playtest_graphics] msaa_3d=%d" % root.msaa_3d)
	var ground := world.get_node_or_null(^"Ground/GroundMesh") as MeshInstance3D
	if ground != null and ground.mesh != null:
		var arrays := ground.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if not arrays.is_empty() else PackedColorArray()
		print("[playtest_graphics] ground vertices=%d tinted=%d" % [
			ground.mesh.surface_get_array_len(0), colors.size(),
		])
	var materials := _distinct_materials(world)
	print("[playtest_graphics] %d meshes, %d distinct materials" % [_count_meshes(world), materials.size()])


func _environment(world: Node) -> Environment:
	var node := world.get_node_or_null(^"Environment") as WorldEnvironment
	return node.environment if node != null else null


func _meshes(from: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if from == null:
		return out
	if from is MeshInstance3D:
		out.append(from as MeshInstance3D)
	for child: Node in from.get_children():
		out.append_array(_meshes(child))
	return out


func _count_meshes(world: Node) -> int:
	return _meshes(world).size()


func _distinct_materials(world: Node) -> Dictionary:
	var out := {}
	for mesh: MeshInstance3D in _meshes(world):
		var material := mesh.material_override
		if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			material = mesh.mesh.surface_get_material(0)
		if material != null:
			out[material.get_instance_id()] = true
	return out


## A free camera rather than the player: the point is to look at the valley from
## places the player cannot stand, and driving the player would also mean a collision
## profile and a farm plot in shot one.
func _shoot() -> void:
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	root.add_child(camera)
	camera.make_current()
	for shot: Dictionary in SHOTS:
		camera.global_position = shot["pos"]
		camera.rotation = Vector3(
			float(shot.get("pitch", 0.0)), float(shot["yaw"]), 0.0
		)
		await process_frame
		await process_frame
		var image := root.get_texture().get_image()
		if image == null:
			print("[playtest_graphics] no image for %s" % shot["name"])
			continue
		var path := "res://%s.png" % shot["name"]
		var err := image.save_png(path)
		print("[playtest_graphics] %s %s %s" % [
			shot["name"], "ok" if err == OK else "FAILED", _describe(image)
		])
	camera.free()


## Objective facts about a frame, because nobody can tell from a pass/fail whether
## the valley rendered.
##
## The spread matters more than the mean: a frame that failed to draw anything is a
## single flat colour, and so is a frame that succeeded and drew one flat green. A
## non-zero luminance spread says there is *something* on screen, and the colour count
## says the material work is reaching the pixels rather than sitting in a resource
## nobody renders.
func _describe(image: Image) -> String:
	var size := image.get_size()
	var step := maxi(1, int(size.x / 160))
	var total := 0.0
	var total_squared := 0.0
	var min_lum := 2.0
	var max_lum := -1.0
	var buckets := {}
	var sampled := 0
	var y := 0
	while y < size.y:
		var x := 0
		while x < size.x:
			var colour := image.get_pixel(x, y)
			var luminance := colour.get_luminance()
			total += luminance
			total_squared += luminance * luminance
			min_lum = minf(min_lum, luminance)
			max_lum = maxf(max_lum, luminance)
			buckets[Vector3i(
				int(colour.r * 255.0), int(colour.g * 255.0), int(colour.b * 255.0)
			)] = true
			sampled += 1
			x += step
		y += step
	var mean := total / float(sampled)
	var variance := total_squared / float(sampled) - mean * mean
	return "luminance mean=%.3f sd=%.4f range=%.3f..%.3f distinct_colours=%d sampled=%d" % [
		mean, sqrt(maxf(variance, 0.0)), min_lum, max_lum, buckets.size(), sampled,
	]