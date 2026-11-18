extends SceneTree
const OUTPUT := "res://scenes/ui/machine_panel.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "MachineUI"
	root.set_script(load("res://scripts/ui/machine_ui.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Build — number keys to place, B to close"
	column.add_child(heading)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	column.add_child(rows)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_machine_ui] failed")
		quit(1)
		return
	print("[generate_machine_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
