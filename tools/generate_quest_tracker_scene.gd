extends SceneTree
## Headless tool: generates `scenes/ui/quest_tracker.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_quest_tracker_scene.gd
##
## Its own scene rather than a panel inside `player_status_hud.tscn`, for the reason
## `generate_player_status_hud_scene.gd` states: different lifetime, and "hide the HUD"
## is one flag that must not take the crosshair with it. This one also has rows that are
## created and destroyed as jobs come and go, which is a different shape of scene from a
## fixed three-row readout.
##
## Below the clock in the top-right, because that corner already holds the date and a
## quest title is the longest line the HUD will ever draw. Top-left is the pocket, and the
## crosshair owns the middle.

const OUTPUT_PATH := "res://scenes/ui/quest_tracker.tscn"

const TEXT_COLOR := Color(0.98, 0.96, 0.88)
const SHADOW_COLOR := Color(0, 0, 0, 0.8)
const PANEL_COLOR := Color(0.09, 0.10, 0.13, 0.55)


func _initialize() -> void:
	var root := CanvasLayer.new()
	root.name = "QuestTracker"
	root.set_script(load("res://scripts/ui/quest_tracker_hud.gd"))

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored top-right: anchors grow from the right edge as the window widens, so the
	# panel stays in the corner instead of drifting toward the middle on a wide monitor.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -330.0
	panel.offset_right = -18.0
	panel.offset_top = 78.0
	# Bottom is left where the layout puts it: a VBoxContainer sizes to its children, and
	# pinning the bottom as well would letterbox the panel when a job has a long title.
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	# The heading names the list. A row reading "Bring 5 Parsnips to Mira  3/5" with no
	# heading is a mystery box in the corner of the screen; "Jobs" is what makes it a
	# list the player can check at a glance.
	column.add_child(_make_label("HeadingLabel", "Jobs", 13))

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	column.add_child(rows)

	# Deliberately no rows here. The tracker creates one label per active job and frees
	# them again, because the number of jobs changes with the quest log; a scene that
	# shipped a fixed set of rows would either show blanks or hide the fourth job.

	_own(root, root)
	if _save(root) != OK:
		printerr("[generate_quest_tracker_scene] failed")
		quit(1)
		return
	print("[generate_quest_tracker_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


## Assigns `owner` down the whole subtree.
##
## Recursive on purpose: a generator that hand-lists the nodes silently drops the ones it
## forgets, because a node with no owner is omitted from the saved scene without
## complaint. See `generate_player_status_hud_scene.gd`, where that cost a label.
##
## The root is left alone. A root whose owner is itself is a scene-pack error, not a
## harmless one — it prints `Condition "p_owner == this" is true` every time the scene is
## generated, and a generator that prints an error every run teaches everyone to ignore
## the error line.
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
