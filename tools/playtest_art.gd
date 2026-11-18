extends SceneTree
## Art review: photographs the whole cast and the valley in the real renderer.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_art.gd
##
## This is a *review* tool, not a gameplay assertion. It freezes the clock, parks
## the six villagers in a line in the square with their signature gear, and points
## the real game camera at them from a distance a player could actually stand at.
## The point is to see whether six people sharing five CC0 bodies read as six
## characters — a question no unit test can answer.
##
## Output: `res://art_review_cast_*.png` and `art_review_world_*.png`, gitignored.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const SHOT_PREFIX := "res://art_review_cast_"
const WORLD_PREFIX := "res://art_review_world_"

var _main: Node = null
var _ready := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[art] no rendering driver: run it without --headless")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		printerr("[art] cannot load main scene")
		quit(1)
		return
	var bus: Node = root.get_node_or_null(^"EventBus")
	if bus == null:
		printerr("[art] no EventBus")
		quit(1)
		return
	bus.game_ready.connect(func() -> void: _ready = true)
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	root.add_child(_main)
	var deadline := Time.get_ticks_msec() + 30000
	while not _ready and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _ready:
		printerr("[art] game never became ready")
		quit(1)
		return

	var clock := _find_method(_main, "sleep_until_morning")
	if clock != null:
		clock.set("running", false)
	var manager: Node = _main.get("npc_manager")
	var player: Node3D = _main.get("player")
	if manager == null or player == null:
		printerr("[art] main is missing the cast or the player")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# --- Wide shots from places a player can stand -------------------------------
	await _look_from(player, Vector3(0, 0.2, 14), Vector3(0, 1.0, -20))
	await _shot(WORLD_PREFIX + "01_farm_wide.png")
	# The road east of the farm, clear of the five house colliders.
	await _look_from(player, Vector3(20, 0.2, 2), Vector3(38, 2.0, 8))
	await _shot(WORLD_PREFIX + "02_village_wide.png")
	# The pond from its southern shore, close enough to see the moving ripples.
	await _look_from(player, Vector3(-14, 0.4, 66), Vector3(-14, -0.6, 44))
	await _shot(WORLD_PREFIX + "03_pond.png")

	# --- The character sheet ------------------------------------------------------
	# Park the cast in a line. Their own AI is frozen for this photograph only;
	# nothing about their models or gear is changed.
	var cast: Array[Node3D] = []
	for npc: Node3D in manager.call("npcs"):
		cast.append(npc)
	# The open farm approach, clear of the five house colliders, so all twelve
	# fit in one frame with the barns and windmill as a backdrop.
	var start_x := -11.0
	var step_x := 2.0
	var line_z := -8.0
	for i: int in cast.size():
		var npc: Node3D = cast[i]
		npc.set("wandering", false)
		npc.call("clear_scheduled_walk")
		npc.global_position = Vector3(start_x + i * step_x, 0.0, line_z)
		# Attending keeps `_advance` from turning them back down their wander
		# heading on the next physics tick; this is a photograph, not a patrol.
		npc.set("attending", true)
		npc.call("face_towards", Vector3(start_x + i * step_x, 0.0, line_z - 10.0), 10.0)
		await process_frame
	await _settle(6)

	var middle := start_x + (cast.size() - 1) * step_x * 0.5
	await _look_from(player, Vector3(middle, 0.2, line_z + 15.0), Vector3(middle, 1.2, line_z))
	await _settle(4)
	await _shot(SHOT_PREFIX + "01_lineup.png")

	# One close portrait per villager, far enough back to see the whole figure and
	# the item in their hand.
	for i: int in cast.size():
		var npc: Node3D = cast[i]
		var at := npc.global_position
		await _look_from(player, at + Vector3(0, 0.2, 3.2), at + Vector3(0, 1.1, 0))
		await _settle(3)
		await _shot("%s%02d_%s.png" % [
			SHOT_PREFIX, i + 1, String(npc.get("data").get("id")),
		])
		print("[art] portrait %s" % String(npc.get("data").get("id")))

	print("[art] PASS")
	quit(0)


func _look_from(player: Node3D, from: Vector3, at: Vector3) -> void:
	player.global_position = from
	var to := at - from
	player.call("set_yaw", atan2(-to.x, -to.z))
	player.call("set_pitch", atan2(to.y, Vector2(to.x, to.z).length()))
	await _settle(3)
	var probe := _find_method(player, "update_focus")
	if probe != null:
		probe.call("update_focus")


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("[art] no image for %s" % path)
		return
	var err := image.save_png(path)
	print("[art] %s %s (%dx%d)" % [
		"wrote" if err == OK else "FAILED to write", path,
		image.get_width(), image.get_height(),
	])


func _find_method(from: Node, method: String) -> Node:
	if from == null:
		return null
	if from.has_method(method):
		return from
	for child: Node in from.get_children():
		var found := _find_method(child, method)
		if found != null:
			return found
	return null
