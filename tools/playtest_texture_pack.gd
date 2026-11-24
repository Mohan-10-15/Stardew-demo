extends SceneTree
## W3.3 evidence: swap the block texture pack live and capture both looks.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_texture_pack.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_pack_"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	var main := packed.instantiate()
	main.set("show_title_on_boot", false)
	main.set("play_intro_cutscene", false)
	root.add_child(main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var service: Node = main.get("voxel_service")
	var player: Node3D = main.get("player")
	if service == null or player == null:
		printerr("[play] no voxel service or player")
		quit(1)
		return
	player.global_position = Vector3(35, 2, 31)
	for _i: int in range(30):
		await process_frame
	print("[play] default pack: %s" % str(service.call("active_texture_pack")))
	await _shot(SHOT + "01_detailed.png")
	if not bool(service.call("set_texture_pack", "pixel16")):
		printerr("[play] swap to pixel16 failed")
		quit(1)
		return
	for _i: int in range(20):
		await process_frame
	print("[play] swapped pack: %s" % str(service.call("active_texture_pack")))
	await _shot(SHOT + "02_pixel16.png")
	print("[play] PASS")
	quit(0)


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
