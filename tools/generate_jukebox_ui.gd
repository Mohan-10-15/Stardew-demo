extends SceneTree
const OUTPUT := "res://scenes/ui/jukebox_panel.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "JukeboxPanel"
	root.set_script(load("res://scripts/ui/jukebox_panel.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -220.0
	panel.offset_bottom = 220.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Jukebox — cues you have heard (F6 to close)"
	column.add_child(heading)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	column.add_child(rows)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_jukebox_ui] failed")
		quit(1)
		return
	print("[generate_jukebox_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
