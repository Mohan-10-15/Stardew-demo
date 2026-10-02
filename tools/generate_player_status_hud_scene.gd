extends SceneTree
## Headless tool: generates `scenes/ui/player_status_hud.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_player_status_hud_scene.gd
##
## Its own scene rather than a panel inside `interaction_hud.tscn`, for the same
## reason the clock has its own: different lifetime. The interaction HUD draws over
## the pause menu and owns layer 10; these are ordinary world readouts. Merging
## them would make "hide the HUD" one flag that takes the crosshair with it.
##
## Top-left, mirroring the clock's top-right, so the two do not fight for the same
## corner and the centre of the screen stays clear for aiming.

const OUTPUT_PATH := "res://scenes/ui/player_status_hud.tscn"

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const PANEL_COLOR := Color(0.09, 0.10, 0.13, 0.55)
const BAR_FILL := Color(0.55, 0.78, 0.42)
const BAR_BACK := Color(0.22, 0.24, 0.28, 0.85)


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "PlayerStatusHUD"
	root.set_script(load("res://scripts/ui/player_status_hud.gd"))

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 18.0
	panel.offset_right = 206.0
	panel.offset_top = 18.0
	panel.offset_bottom = 92.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	# The heading is not decoration: a bare "120g" in a corner is ambiguous, and
	# "Stamina" next to an unexplained number is the difference between a readable
	# bar and a mystery gauge.
	column.add_child(_make_label("HeadingLabel", "Pocket", 13))

	column.add_child(_make_label("GoldLabel", "", 22))

	var row := HBoxContainer.new()
	row.name = "StaminaRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var caption := _make_label("StaminaCaption", "Stamina", 14)
	caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(caption)

	var bar := ProgressBar.new()
	bar.name = "StaminaBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(96, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	bar.add_theme_stylebox_override("background", _bar_style(BAR_BACK))
	bar.add_theme_stylebox_override("fill", _bar_style(BAR_FILL))
	row.add_child(bar)

	row.add_child(_make_label("StaminaLabel", "100/100", 14))

	for child: Node in [panel, column, row, bar, caption]:
		child.owner = root
	for child: Node in column.get_children():
		child.owner = root

	if _save(root) != OK:
		printerr("[generate_player_status_hud_scene] failed")
		quit(1)
		return
	print("[generate_player_status_hud_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


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


func _bar_style(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)