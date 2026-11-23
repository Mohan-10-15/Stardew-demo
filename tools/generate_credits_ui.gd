extends SceneTree
const OUTPUT := "res://scenes/ui/credits_panel.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "CreditsPanel"
	root.set_script(load("res://scripts/ui/credits_panel.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 520)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var list := RichTextLabel.new()
	list.name = "List"
	list.custom_minimum_size = Vector2(680, 470)
	list.bbcode_enabled = true
	list.scroll_active = true
	column.add_child(list)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_credits_ui] failed")
		quit(1)
		return
	print("[generate_credits_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
