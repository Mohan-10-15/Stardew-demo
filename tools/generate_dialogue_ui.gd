extends SceneTree
## Headless tool: generates `scenes/ui/dialogue_panel.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_dialogue_ui.gd
##
## Its own scene rather than a panel inside an existing HUD, for the reason
## `generate_quest_tracker_scene.gd` states: different lifetime. The conversation
## panel appears and disappears per sentence, pauses the game while it is up and
## must be able to release that pause on its own — which is a different shape of
## scene from a corner readout, and "hide the HUD" must not take it with the
## crosshair.
##
## Bottom-centre, because that is where a conversation happens: the player is
## looking at the villager in the middle of the screen, and the words belong
## under them rather than in a corner the eye has to leave the person to find.

const OUTPUT_PATH := "res://scenes/ui/dialogue_panel.tscn"

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const NAME_COLOR := Color(0.98, 0.85, 0.55)
const PANEL_COLOR := Color(0.07, 0.08, 0.11, 0.92)

## The panel's width on screen. Wide enough for two wrapped lines of a farmer's
## sentence, narrow enough that it never reaches either edge of a 1280 window.
const PANEL_WIDTH := 720.0


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "DialogueUI"
	root.set_script(load("res://scripts/dialogue/dialogue_ui.gd"))

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored bottom-centre: the horizontal centre holds as the window widens,
	# and the bottom edge holds as it grows taller, so the panel sits under the
	# villager on any resolution instead of drifting to a corner.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH / 2.0
	panel.offset_right = PANEL_WIDTH / 2.0
	panel.offset_top = -190.0
	panel.offset_bottom = -22.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var name_label := _make_label("NameLabel", "", 20, NAME_COLOR)
	column.add_child(name_label)

	var text_label := _make_label("TextLabel", "", 17, TEXT_COLOR)
	# Autowrap rather than a fixed width: a villager who says three sentences
	# grows the box downward instead of running off the right edge. A Label
	# inside a PanelContainer is free to be as tall as its text needs.
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(PANEL_WIDTH - 48.0, 0)
	column.add_child(text_label)

	var choices := VBoxContainer.new()
	choices.name = "Choices"
	choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices.add_theme_constant_override("separation", 3)
	column.add_child(choices)
	# Deliberately empty: replies are content, built one button per reply by
	# dialogue_ui.gd when a line actually offers some.

	var continue_label := _make_label("Continue", "▼  E  Continue", 13, TEXT_COLOR)
	continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_label.visible = false
	column.add_child(continue_label)

	_own(root, root)
	if _save(root) != OK:
		printerr("[generate_dialogue_ui] failed")
		quit(1)
		return
	print("[generate_dialogue_ui] wrote %s" % OUTPUT_PATH)
	quit(0)


## Assigns `owner` down the whole subtree.
##
## Recursive on purpose: a generator that hand-lists the nodes silently drops the
## ones it forgets, because a node with no owner is omitted from the saved scene
## without complaint. See `generate_player_status_hud_scene.gd`, where that cost
## a label.
##
## The root is left alone: a root whose owner is itself is a scene-pack error
## that prints `Condition "p_owner == this"` on every run.
func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top


func _make_label(label_name: String, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 2)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = Color(0.98, 0.85, 0.55, 0.35)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 10.0
	return style


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)
