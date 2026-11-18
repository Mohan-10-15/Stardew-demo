extends SceneTree
const OUTPUT := "res://scenes/ui/festival_hud.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "FestivalHUD"
	root.set_script(load("res://scripts/ui/festival_hud.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 160
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var label := Label.new()
	label.name = "Text"
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_festival_hud] failed")
		quit(1)
		return
	print("[generate_festival_hud] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
