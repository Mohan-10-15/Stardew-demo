extends SceneTree
const OUTPUT := "res://scenes/ui/music_toast.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "MusicToast"
	root.set_script(load("res://scripts/ui/music_toast.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_top = -64.0
	panel.offset_bottom = -22.0
	panel.offset_left = -190.0
	panel.offset_right = 190.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var label := Label.new()
	label.name = "Text"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_music_toast] failed")
		quit(1)
		return
	print("[generate_music_toast] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
