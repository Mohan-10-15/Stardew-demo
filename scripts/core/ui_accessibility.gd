class_name UiAccessibility
extends Node
## Applies the accessibility settings to every Control in the live tree.
##
## Text scale is a *font size multiplier*, not `content_scale_factor`: scaling
## the whole viewport would push corner-anchored HUDs off screen, which is the
## opposite of accessible. Each label's original size is remembered in metadata
## on the first pass, so repeated applies never compound — 1.2 applied twice is
## still 1.2, not 1.44.
##
## High contrast adds a dark outline behind text. Colour stays decorative; the
## words and numbers next to it carry the meaning in every HUD already, and the
## tests in `test_accessibility.gd` assert that rather than trusting a palette.

const MIN_FONT_SIZE := 8
const MAX_FONT_SIZE := 48


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.settings_applied.connect(apply)
	apply()


func _exit_tree() -> void:
	if EventBus.settings_applied.is_connected(apply):
		EventBus.settings_applied.disconnect(apply)


func apply() -> void:
	var tree := Engine.get_main_loop()
	if not tree is SceneTree:
		return
	_apply((tree as SceneTree).root)


func _apply(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Label or node is Button:
		_apply_text(node as Control)
	for child: Node in node.get_children():
		_apply(child)


func _apply_text(control: Control) -> void:
	var scale := clampf(Config.settings.ui_scale, 0.75, 1.5)
	if not control.has_meta(&"base_font_size"):
		control.set_meta(&"base_font_size", int(control.get_theme_font_size(&"font_size")))
	var base: int = int(control.get_meta(&"base_font_size"))
	var size := clampi(roundi(float(base) * scale), MIN_FONT_SIZE, MAX_FONT_SIZE)
	control.add_theme_font_size_override(&"font_size", size)

	if Config.settings.colour_assist:
		control.add_theme_constant_override(&"font_outline_size", 2)
		control.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	else:
		control.remove_theme_constant_override(&"font_outline_size")
		control.remove_theme_color_override(&"font_outline_color")


## Whether a text scale still fits a control. Used by the settings panel and by
## tests so "scales without clipping" is a measured claim, not a hope.
static func fits(control: Control, scale: float) -> bool:
	if control.get_meta(&"base_font_size", null) == null:
		control.set_meta(&"base_font_size", int(control.get_theme_font_size(&"font_size")))
	var base: int = int(control.get_meta(&"base_font_size"))
	var size := clampi(roundi(float(base) * clampf(scale, 0.75, 1.5)), MIN_FONT_SIZE, MAX_FONT_SIZE)
	var font := control.get_theme_font(&"font")
	if font == null:
		return true
	var width := font.get_string_size(
		control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size
	).x
	var available := control.size.x
	if available <= 0.0:
		available = control.custom_minimum_size.x
	return available <= 0.0 or width <= available
