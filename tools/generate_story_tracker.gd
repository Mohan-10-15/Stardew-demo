extends SceneTree
## Headless tool: generates `scenes/ui/story_tracker.tscn`.

const OUTPUT := "res://scenes/ui/story_tracker.tscn"


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "StoryTracker"
	root.set_script(load("res://scripts/ui/story_tracker.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 120
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style())
	root.add_child(panel)
	var label := Label.new()
	label.name = "Chapter"
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	panel.add_child(label)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_story_tracker] failed")
		quit(1)
		return
	print("[generate_story_tracker] wrote %s" % OUTPUT)
	quit(0)


func _style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.14, 0.5)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	return s


func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
