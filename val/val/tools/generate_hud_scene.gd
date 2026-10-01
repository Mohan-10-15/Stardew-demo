extends SceneTree
## Headless tool: generates `scenes/ui/interaction_hud.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_hud_scene.gd

const OUTPUT_PATH := "res://scenes/ui/interaction_hud.tscn"

const CROSS_COLOR := Color(0.95, 0.95, 0.92, 0.85)
const PROMPT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.75)


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "InteractionHUD"
	root.layer = 10
	root.set_script(load("res://scripts/ui/interaction_hud.gd"))

	# --- Crosshair --------------------------------------------------------
	# A centre-anchored Control that draws itself, so no texture is needed.
	var crosshair := Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_script(load("res://scripts/ui/crosshair.gd"))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -16.0
	crosshair.offset_top = -16.0
	crosshair.offset_right = 16.0
	crosshair.offset_bottom = 16.0
	root.add_child(crosshair)

	# --- Prompt -----------------------------------------------------------
	var container := VBoxContainer.new()
	container.name = "PromptContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.72
	container.anchor_bottom = 0.72
	container.offset_left = -240.0
	container.offset_right = 240.0
	container.offset_top = -24.0
	container.offset_bottom = 60.0
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(container)

	var prompt := Label.new()
	prompt.name = "PromptLabel"
	prompt.text = ""
	prompt.visible = false
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", PROMPT_COLOR)
	prompt.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	prompt.add_theme_constant_override("shadow_offset_x", 2)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	prompt.add_theme_constant_override("shadow_outline_size", 2)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(prompt)

	var hold := ProgressBar.new()
	hold.name = "HoldBar"
	hold.visible = false
	hold.custom_minimum_size = Vector2(120, 6)
	hold.show_percentage = false
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.add_child(hold)

	for child: Node in [crosshair, container, prompt, hold]:
		child.owner = root

	var err := _save(root)
	if err != OK:
		printerr("[generate_hud_scene] failed: %d" % err)
		quit(1)
		return
	print("[generate_hud_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)