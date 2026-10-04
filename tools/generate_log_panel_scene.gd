extends SceneTree
## Headless tool: generates `scenes/ui/log_panel.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_log_panel_scene.gd

const OUTPUT_PATH := "res://scenes/ui/log_panel.tscn"

const HEADER_COLOR := Color(0.86, 0.82, 0.62)
const SHADOW_COLOR := Color(0, 0, 0, 0.75)


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "LogPanel"
	root.layer = 15
	root.set_script(load("res://scripts/ui/log_panel.gd"))

	# Anchored top-left, a little in. Deliberately not centred and not full-screen: a
	# log that covers the world is a log you have to dismiss to play, and the point of
	# this panel is to read it *while* playing.
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 16.0
	panel.offset_top = 48.0
	panel.offset_right = 560.0
	panel.offset_bottom = 420.0
	root.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.86)
	style.border_color = Color(0.42, 0.40, 0.30, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header := Label.new()
	header.name = "Header"
	header.text = "Log"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	header.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	header.add_theme_constant_override("shadow_offset_x", 1)
	header.add_theme_constant_override("shadow_offset_y", 1)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	# One control for every line, appended to. A label per line is a node per line,
	# which is the wrong price to pay on the frames where the log is busiest.
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.scroll_following = true
	text.fit_content = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 12)
	scroll.add_child(text)

	# Every node, or none of them. `PackedScene.pack` only keeps nodes whose `owner` is
	# the scene root, and it does so *silently* — the save succeeds, the file is written,
	# and the panel instantiates as an empty layer. This has already happened twice in
	# this project, so it is written down here rather than rediscovered.
	for child: Node in [panel, column, header, scroll, text]:
		child.owner = root

	var err := _save(root)
	if err != OK:
		printerr("[generate_log_panel_scene] failed: %d" % err)
		quit(1)
		return
	print("[generate_log_panel_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)