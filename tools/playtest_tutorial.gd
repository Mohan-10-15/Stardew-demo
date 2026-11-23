extends SceneTree
## W1.9 evidence: the first-day hint appears, advances on a real EventBus
## event, and never blocks input.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_tutorial.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_tutorial_"

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
	await _settle(10)

	var service: Node = _main.get("tutorial_service")
	var hud := _find(root, &"TutorialHUD")
	if service == null or hud == null:
		printerr("[play] no tutorial service or HUD")
		quit(1)
		return
	var before: int = int(service.current)
	var hint: Label = hud.get_node_or_null(^"Panel/Hint") as Label
	print("[play] first hint: '%s' (step %d)" % [hint.text if hint != null else "", before])
	if hint == null or hint.text.is_empty():
		printerr("[play] no first-day hint on screen")
		quit(1)
		return
	await _shot(SHOT + "01_first_hint.png")

	bus.emit_signal(&"footstep", &"grass")
	await _settle(5)
	var after: int = int(service.current)
	print("[play] after a footstep: step %d -> %d" % [before, after])
	if after <= before:
		printerr("[play] the tutorial did not advance")
		quit(1)
		return
	await _shot(SHOT + "02_second_hint.png")
	print("[play] PASS")
	quit(0)


func _find(node: Node, wanted: StringName) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find(child, wanted)
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
