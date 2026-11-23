extends SceneTree
## W2.3 evidence: the plinth and a gate render in the real valley, and a
## collection tier opens the gate.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_heartstone.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_heartstone_"

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

	var plinth := _find(root, &"HeartstonePlinth")
	var gate := _find(root, &"Gate_orchard_path")
	if plinth == null or gate == null:
		printerr("[play] plinth or gate missing")
		quit(1)
		return
	print("[play] plinth at %s, gate at %s" % [
		str((plinth as Node3D).global_position), str((gate as Node3D).global_position),
	])
	await _shot(SHOT + "01_plinth.png")

	var component := gate.get_node_or_null(^"Interactable")
	bus.collection_tier_reached.emit(&"fields", 0, &"orchard_path", &"fields")
	await _settle(5)
	if not bool(component.call("is_open")):
		printerr("[play] the orchard gate did not open")
		quit(1)
		return
	print("[play] orchard gate opened on the Fields tier")
	await _shot(SHOT + "02_gate_open.png")
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
