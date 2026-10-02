extends SceneTree
## Headless tool: generates `scenes/ui/hotbar_hud.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_hotbar_hud_scene.gd
##
## The nine slots are emitted as real sibling nodes rather than drawn in one
## `_draw` call. A drawn belt would be fewer nodes, but then each slot's text and
## highlight would have to be laid out by hand and would not line up with a
## different font size or a resized window. Nine `Panel`s under an `HBoxContainer`
## lay themselves out, which is the whole job.
##
## Bottom-centre, above the status and clock panels. Centred because the belt is
## what the player looks at while aiming, and the crosshair owns the middle of the
## screen — the belt sits below it rather than around it.

const OUTPUT_PATH := "res://scenes/ui/hotbar_hud.tscn"
const SLOT_COUNT := 9

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const SLOT_W := 104.0
const SLOT_H := 40.0


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "HotbarHUD"
	root.set_script(load("res://scripts/ui/hotbar_hud.gd"))

	var slots := HBoxContainer.new()
	slots.name = "Slots"
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.anchor_left = 0.5
	slots.anchor_right = 0.5
	slots.anchor_top = 1.0
	slots.anchor_bottom = 1.0
	slots.offset_left = -(SLOT_W * SLOT_COUNT + 6.0 * (SLOT_COUNT - 1)) * 0.5
	slots.offset_right = (SLOT_W * SLOT_COUNT + 6.0 * (SLOT_COUNT - 1)) * 0.5
	slots.offset_top = -66.0
	slots.offset_bottom = -18.0
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 6)
	root.add_child(slots)

	for i: int in range(SLOT_COUNT):
		slots.add_child(_make_slot(i))

	slots.owner = root
	if _save(root) != OK:
		printerr("[generate_hotbar_hud_scene] failed")
		quit(1)
		return
	print("[generate_hotbar_hud_scene] wrote %s (%d slots)" % [OUTPUT_PATH, SLOT_COUNT])
	quit(0)


## One slot: a bordered panel, the slot's contents, and its number.
##
## The number is drawn rather than left implicit because the bindings are 1-9 and
## a player needs to see which key maps to which slot to use them at all.
func _make_slot(index: int) -> Panel:
	var panel := Panel.new()
	panel.name = "Slot%d" % (index + 1)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	panel.add_theme_stylebox_override("panel", _slot_style(false))

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var number := Label.new()
	number.name = "NumberLabel"
	number.text = str(index + 1)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.add_theme_font_size_override("font_size", 11)
	number.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58))
	number.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	number.add_theme_constant_override("shadow_offset_x", 1)
	number.add_theme_constant_override("shadow_offset_y", 1)
	number.add_theme_constant_override("shadow_outline_size", 2)
	column.add_child(number)

	var label := Label.new()
	label.name = "SlotLabel"
	label.text = ""
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 2)
	# Short names are the norm here and must not be clipped to nothing; the slot is
	# a fixed size, so the text shrinks to fit rather than being cut off mid-word.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(label)

	number.owner = panel
	label.owner = panel
	column.owner = panel
	return panel


func _slot_style(held: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.30, 0.16, 0.88) if held else Color(0.10, 0.11, 0.14, 0.62)
	style.border_color = Color(0.95, 0.82, 0.45, 0.95) if held else Color(0.32, 0.30, 0.26, 0.85)
	style.set_border_width_all(2 if held else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)