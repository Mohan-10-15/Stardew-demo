extends SceneTree
const OUTPUT := "res://scenes/ui/about_panel.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "AboutPanel"
	root.set_script(load("res://scripts/ui/about_panel.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 520)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var body := RichTextLabel.new()
	body.name = "Body"
	body.custom_minimum_size = Vector2(700, 400)
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.add_theme_font_size_override("normal_font_size", 17)
	column.add_child(body)
	var counter := Label.new()
	counter.name = "Counter"
	counter.add_theme_font_size_override("font_size", 13)
	column.add_child(counter)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_about_ui] failed")
		quit(1)
		return
	print("[generate_about_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
