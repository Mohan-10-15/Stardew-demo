extends SceneTree
## Headless tool: generates `scenes/ui/title_screen.tscn`.
##
##     godot --headless --path . --script res://tools/generate_title_screen.gd
##
## One full-screen CanvasLayer with a title and two buttons. No hand-placed
## nodes, per AGENTS.md rule 1.

const OUTPUT := "res://scenes/ui/title_screen.tscn"


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "TitleScreen"
	root.set_script(load("res://scripts/ui/title_screen.gd"))

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	# Translucent so the real valley and its slow camera drift stay visible
	# behind the menu (W1.5). Do not build a second world for a title screen.
	backdrop.color = Color(0.04, 0.07, 0.12, 0.58)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# Fixed centred rect: a growing PanelContainer keeps its top at the anchor
	# and pushes the last buttons off the bottom of a 720p window.
	panel.offset_left = -250.0
	panel.offset_right = 250.0
	panel.offset_top = -320.0
	panel.offset_bottom = 320.0
	panel.custom_minimum_size = Vector2(500, 640)
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "HOLLOWBROOK HOLLOW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.text = "A valley that remembers you"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 15)
	column.add_child(tagline)

	column.add_child(_button("NewGame", "New Game"))
	column.add_child(_button("Continue", "Continue"))
	column.add_child(_button("About", "About the Game"))
	column.add_child(_button("HowToPlay", "How to Play"))
	column.add_child(_button("Settings", "Settings"))
	column.add_child(_button("Credits", "Credits"))
	column.add_child(_button("Quit", "Quit"))

	var hint := Label.new()
	hint.name = "Hint"
	# Labels come from InputGlyphs at runtime so a pad player sees the pad
	# glyphs. The generator only creates the node and an initial placeholder.
	hint.set_meta("glyph_kind", "save_hint")
	hint.text = "Save and load from the menu"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	column.add_child(hint)

	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, OUTPUT) != OK:
		printerr("[generate_title_screen] failed to write %s" % OUTPUT)
		quit(1)
		return
	print("[generate_title_screen] wrote %s" % OUTPUT)
	quit(0)


func _button(name: String, text: String) -> Button:
	var button := Button.new()
	button.name = name
	button.text = text
	button.custom_minimum_size = Vector2(220, 44)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.18, 0.96)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	return style


func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
