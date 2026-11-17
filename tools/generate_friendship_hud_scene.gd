extends SceneTree
## Headless tool: generates `scenes/ui/friendship_hud.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_friendship_hud_scene.gd
##
## Its own scene rather than a panel inside the status HUD, for the same lifetime
## reason `generate_quest_tracker_scene.gd` gives: "hide the HUD" is one flag that
## must not take the relationship readout with it. Rows are created by the HUD at
## runtime because the cast is content and can grow; a fixed set of labels would
## either show blanks or hide the seventh villager.

const OUTPUT_PATH := "res://scenes/ui/friendship_hud.tscn"

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const PANEL_COLOR := Color(0.09, 0.10, 0.13, 0.55)


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "FriendshipHUD"
	root.set_script(load("res://scripts/ui/friendship_hud.gd"))

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-right: the top-right corner holds the clock and the jobs, and the
	# bottom-centre holds the hotbar. This is the one corner with room for six rows.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -300.0
	panel.offset_right = -18.0
	panel.offset_top = -214.0
	panel.offset_bottom = -74.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	column.add_child(_make_label("HeadingLabel", "Relationships", 13))

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	column.add_child(rows)

	_own(root, root)
	if _save(root) != OK:
		printerr("[generate_friendship_hud_scene] failed")
		quit(1)
		return
	print("[generate_friendship_hud_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


## Recursive so no node is left without an owner and silently dropped from the
## saved scene. The root is excluded for the scene-pack reason given in
## `generate_quest_tracker_scene.gd`.
func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top


func _make_label(label_name: String, text: String, size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 2)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)
