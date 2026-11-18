extends SceneTree
## Headless tool: generates `scenes/ui/combat_hud.tscn`.

const OUTPUT := "res://scenes/ui/combat_hud.tscn"


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "CombatHUD"
	root.set_script(load("res://scripts/ui/combat_hud.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_top = -150
	panel.offset_bottom = -60
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style())
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)
	var bar := ProgressBar.new()
	bar.name = "Health"
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = true
	column.add_child(bar)
	var status := Label.new()
	status.name = "Status"
	status.text = ""
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_combat_hud] failed")
		quit(1)
		return
	print("[generate_combat_hud] wrote %s" % OUTPUT)
	quit(0)


func _style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.06, 0.08, 0.75)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
