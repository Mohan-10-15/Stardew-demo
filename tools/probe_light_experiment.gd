extends SceneTree
## One-off: render the same frame with two ground-material variants so the
## pale-ground cause can be measured rather than guessed.

const MAIN := "res://scenes/core/main.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var player: Node3D = main.get("player")
	player.global_position = Vector3(20, 0.2, 2)
	player.call("set_yaw", atan2(-(38 - 20), -(8 - 2)))
	var ground := _find(main, "GroundMesh") as MeshInstance3D
	var mat := ground.material_override as StandardMaterial3D
	await _shot("res://art_review_exp_0_baseline.png")
	var we := _find(main, "Environment") as WorldEnvironment
	var env := we.environment
	env.fog_enabled = false
	await _shot("res://art_review_exp_1_nofog.png")
	env.ambient_light_energy = 0.0
	await _shot("res://art_review_exp_2_noambient.png")
	env.ambient_light_energy = 2.0
	await _shot("res://art_review_exp_3_bigambient.png")
	mat.albedo_color = Color(0, 1, 0)
	await _shot("res://art_review_exp_4_green.png")
	print("[exp] done")
	quit(0)


func _find(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	print("[exp] %s" % ("wrote " + path if image.save_png(path) == OK else "failed " + path))
