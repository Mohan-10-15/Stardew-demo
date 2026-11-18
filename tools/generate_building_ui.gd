extends SceneTree
const OUTPUT := "res://scenes/ui/building_panel.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "BuildingUI"
	root.set_script(load("res://scripts/ui/building_ui.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 260)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Buildings — N to close, 1-3 buy, 7-9 upgrade"
	column.add_child(heading)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	column.add_child(rows)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_building_ui] failed")
		quit(1)
		return
	print("[generate_building_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
