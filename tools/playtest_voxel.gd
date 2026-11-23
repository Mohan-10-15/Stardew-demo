extends SceneTree
## W3 evidence: the generated block atlas renders, and a block can be broken
## and placed through VoxelService with distinct events.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_voxel.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_voxel_"

var _main: Node = null
var _broken: Array[StringName] = []
var _placed: Array[StringName] = []


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
	await _settle(10)

	var service: Node = _main.get("voxel_service")
	if service == null:
		printerr("[play] no voxel service")
		quit(1)
		return
	bus.block_broken.connect(func(id: StringName, _p: Vector3i, _t: StringName) -> void:
		_broken.append(id))
	bus.block_placed.connect(func(id: StringName, _p: Vector3i) -> void:
		_placed.append(id))

	# Typed class references would pull EventBus-dependent scripts into this
	# --script tool's compile (AGENTS.md trap 1), so use plain values here.
	var grid: Variant = service.get("grid")
	var plot_centre := Vector3i(34, 0, 26)
	var cell := Vector3i(0, 1, 0)
	var before: StringName = grid.get_block(cell)
	print("[play] plot cell holds %s" % before)
	var player: Node3D = _main.get("player")
	if player != null:
		player.global_position = Vector3(
			plot_centre.x, 2.0, plot_centre.z + 6)
	await _settle(8)
	await _shot(SHOT + "01_plot.png")

	if before == &"":
		printerr("[play] the generated plot has no grass at the centre")
		quit(1)
		return
	if not bool(service.call("break_at", cell, &"hoe")):
		printerr("[play] break was refused")
		quit(1)
		return
	if _broken.size() != 1 or grid.get_block(cell) != &"":
		printerr("[play] break outcome not published")
		quit(1)
		return
	print("[play] broke %s with the hoe" % before)
	if not bool(service.call("place_at", cell, &"oak_planks")):
		printerr("[play] place was refused")
		quit(1)
		return
	if _placed.size() != 1 or grid.get_block(cell) != &"oak_planks":
		printerr("[play] place outcome not published")
		quit(1)
		return
	print("[play] placed oak planks, both events distinct")
	await _settle(6)
	await _shot(SHOT + "02_edited.png")
	print("[play] PASS")
	quit(0)


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
