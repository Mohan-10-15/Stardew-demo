extends SceneTree
## Real-window review of M17: the held tool draws in front of the camera, swings
## on a tool event, hides in third person, and buildings use real CC0 models.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_art.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_art_"

var _main: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	root.add_child(_main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame

	var view := _find_named(_main, "ToolViewModel") as Node3D
	var rig := _find_named(_main, "CameraRig")
	if view == null or rig == null:
		printerr("[play] no tool view model or camera rig")
		quit(1)
		return
	var held := _find_named(_main, "PlayerState")
	if held == null:
		printerr("[play] no player state")
		quit(1)
		return
	var before: Dictionary = held.call("held_item_id")
	var model := view.get_node_or_null(^"HeldTool") as Node3D
	if model == null:
		printerr("[play] the held tool (%s) drew nothing" % str(before.get("id", &"")))
		quit(1)
		return
	print("[play] first-person view model draws %s (%d parts)" % [
		str(before.get("id", &"")), model.get_child_count(),
	])
	await _shot(SHOT + "01_held_tool.png")

	# A swing must visibly rotate the tool away from its rest pose.
	var rest: Vector3 = model.rotation
	bus.tool_swung.emit(StringName(before.get("id", &"")))
	await _settle(4)
	var moved: Vector3 = model.rotation
	if moved.distance_to(rest) < 0.05:
		printerr("[play] the tool did not swing (rest=%s moved=%s)" % [str(rest), str(moved)])
		quit(1)
		return
	print("[play] tool swung from %s to %s" % [str(rest), str(moved)])
	await _shot(SHOT + "02_swing.png")
	await _settle(30)
	if model.rotation.distance_to(rest) > 0.05:
		printerr("[play] the tool did not return to rest")
		quit(1)
		return

	# Third person hides the view model so it does not float in the world.
	rig.call("set_mode", 1, true)
	await _settle(3)
	if bool(view.visible):
		printerr("[play] view model stayed visible in third person")
		quit(1)
		return
	print("[play] view model hides in third person")
	await _shot(SHOT + "03_third_person.png")
	rig.call("set_mode", 0, true)
	await _settle(3)

	# Buildings must use the imported CC0 scene, not the procedural fallback.
	var store: Object = null
	for data: BuildingData in BuildingService.all_buildings():
		if data.id == &"hen_coop":
			store = data
	if store == null or String(store.get("model_path")).is_empty():
		printerr("[play] the coop has no CC0 model path")
		quit(1)
		return
	print("[play] coop art: %s" % String(store.get("model_path")))
	print("[play] PASS")
	quit(0)


func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
