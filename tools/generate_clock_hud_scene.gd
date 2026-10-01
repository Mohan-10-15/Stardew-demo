extends SceneTree
## Headless tool: generates `scenes/ui/clock_hud.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_clock_hud_scene.gd
##
## A separate scene from `interaction_hud.tscn` rather than a panel bolted onto
## it, because the two have different lifetimes: the interaction HUD must draw
## over the pause menu and owns layer 10, while the clock is ordinary world
## information. Merging them would make "hide the HUD" a single flag that turns
## the clock off too.

const OUTPUT_PATH := "res://scenes/ui/clock_hud.tscn"

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const PANEL_COLOR := Color(0.09, 0.10, 0.13, 0.55)


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "ClockHUD"
	root.set_script(load("res://scripts/ui/clock_hud.gd"))

	# Top-right corner, inset from the edges so it does not touch the window
	# frame on a borderless fullscreen window.
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -230.0
	panel.offset_right = -18.0
	panel.offset_top = 18.0
	panel.offset_bottom = 86.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var date_label := _make_label("DateLabel", 16)
	column.add_child(date_label)

	var time_label := _make_label("TimeLabel", 30)
	column.add_child(time_label)

	var weather_label := _make_label("WeatherLabel", 14)
	column.add_child(weather_label)

	for child: Node in [panel, column, date_label, time_label, weather_label]:
		child.owner = root

	if _save(root) != OK:
		printerr("[generate_clock_hud_scene] failed")
		quit(1)
		return
	print("[generate_clock_hud_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


func _make_label(label_name: String, size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
