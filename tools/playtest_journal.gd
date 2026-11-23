extends SceneTree
## W2.4 evidence: the journal opens on J with all four populated tabs.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_journal.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_journal_"

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
	var panel := _main.get("journal_panel") as CanvasLayer
	if panel == null:
		printerr("[play] no journal panel")
		quit(1)
		return
	var press := InputEventKey.new()
	press.keycode = KEY_J
	press.physical_keycode = KEY_J
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(5)
	if not bool(panel.visible):
		printerr("[play] J did not open the journal")
		quit(1)
		return
	var tabs := panel.get_node_or_null(^"Panel/Tabs") as TabContainer
	print("[play] journal opened with %d tabs" % tabs.get_tab_count())
	for i: int in range(tabs.get_tab_count()):
		tabs.current_tab = i
		await _settle(3)
		await _shot(SHOT + "%d_tab.png" % i)
	await _shot(SHOT + "01_journal.png")
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
