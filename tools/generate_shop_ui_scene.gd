extends SceneTree
## Headless tool: generates `scenes/ui/shop_ui.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_shop_ui_scene.gd
##
## The rows are *not* authored here. Each one is built by `shop_ui.gd` from the
## shop's content, so adding a seed packet to a shop adds a row with no scene edit.
## A hand-authored row list would need regenerating every time content changed and
## would put one fixed set of items in the UI layer — content logic in the view.
##
## Only the chrome is authored: title, gold line, the row container, the message
## line, and the close button.

const OUTPUT_PATH := "res://scenes/ui/shop_ui.tscn"

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const PANEL_COLOR := Color(0.10, 0.11, 0.14, 0.94)

const PANEL_W := 460.0


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "ShopUI"
	root.set_script(load("res://scripts/ui/shop_ui.gd"))
	# Modal: the panel takes clicks, so nothing behind it should.
	root.visible = false
	root.layer = 20

	# A full-screen Control to swallow clicks, so clicking beside the panel does
	# not fall through to the world and start an interaction behind the shop.
	var cover := Control.new()
	cover.name = "Cover"
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cover)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(_make_label("Title", "Shop", 22))
	column.add_child(_make_label("Gold", "Your gold: 0g", 15))

	# The header is separated from the rows so a long stock list cannot make the
	# title look like one of the items.
	var rule := HSeparator.new()
	rule.name = "Rule"
	column.add_child(rule)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 3)
	column.add_child(rows)

	var rule2 := HSeparator.new()
	rule2.name = "Rule2"
	column.add_child(rule2)

	var message := _make_label("Message", "", 15)
	column.add_child(message)

	var close := Button.new()
	close.name = "Close"
	close.text = "Close (E)"
	close.custom_minimum_size = Vector2(0, 30)
	column.add_child(close)

	_own(root, root)
	if _save(root) != OK:
		printerr("[generate_shop_ui_scene] failed")
		quit(1)
		return
	print("[generate_shop_ui_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


## Assigns `owner` down the whole subtree.
##
## Hand-listing was tried first and dropped the title and gold labels from the
## saved scene, because a node with no `owner` is omitted from a `PackedScene`
## without any error at all. The panel then opened as an empty box. Recursing
## cannot be forgotten; see `generate_hotbar_hud_scene.gd` for the same note.
func _own(node: Node, top: Node) -> void:
	node.owner = top
	for child: Node in node.get_children():
		_own(child, top)


func _make_label(label_name: String, text: String, size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
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
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.42, 0.36, 0.24, 0.95)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)