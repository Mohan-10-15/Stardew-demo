extends SceneTree
const OUTPUT := "res://scenes/ui/journal_panel.tscn"

func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "JournalPanel"
	root.set_script(load("res://scripts/ui/journal_panel.gd"))
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0
	panel.offset_right = 360.0
	panel.offset_top = -260.0
	panel.offset_bottom = 260.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	panel.add_child(tabs)
	for name: String in ["Quests", "Collections", "Villagers", "Story"]:
		var page := ScrollContainer.new()
		page.name = name
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(page)
		var list := VBoxContainer.new()
		list.name = "List"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.custom_minimum_size = Vector2(660, 0)
		page.add_child(list)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_journal_ui] failed")
		quit(1)
		return
	print("[generate_journal_ui] wrote %s" % OUTPUT)
	quit(0)

func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
