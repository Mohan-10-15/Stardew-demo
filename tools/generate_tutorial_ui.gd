extends SceneTree
const OUTPUT := "res://scenes/ui/tutorial_hud.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "TutorialHUD"
	root.set_script(load("res://scripts/ui/tutorial_hud.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_top = -72.0
	panel.offset_bottom = -18.0
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var hint := Label.new()
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_tutorial_ui] failed")
		quit(1)
		return
	print("[generate_tutorial_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
