extends SceneTree
## Headless tool: writes the authored cutscenes and their generated overlay.
##
##     godot --headless --path . --script res://tools/generate_cutscene_data.gd
##
## Cutscenes are data: a nicer intro is a table edit here, never a branch in
## `main.gd`. Each entry describes a step, its skip behaviour and its params.

const OUT_DIR := "res://resources/cutscenes/"
const SCENE_PATH := "res://scenes/cutscenes/cutscene_overlay.tscn"

## skip: 0 = apply on skip, 1 = skip entirely, 2 = required (cannot be skipped)
const CUTSCENES: Array[Dictionary] = [
	{
		"id": &"intro", "title": "Arrival at Hollowbrook",
		"events": [
			{"kind": &"letterbox", "seconds": 0.1, "skip": 1, "show": true},
			{"kind": &"fade", "seconds": 0.3, "skip": 1, "alpha": 1.0},
			{"kind": &"wait", "seconds": 0.2, "skip": 1},
			{"kind": &"fade", "seconds": 0.3, "skip": 1, "alpha": 0.0},
			{"kind": &"dialogue", "seconds": 2.6, "skip": 1,
				"text": "The cart left you at the edge of the valley at dawn."},
			{"kind": &"dialogue", "seconds": 2.8, "skip": 1,
				"text": "An old farm, a locked gate, and a village that has not yet learned your name."},
			{"kind": &"dialogue", "seconds": 2.4, "skip": 1,
				"text": "Someone in the square is already offering you work."},
			{"kind": &"flag", "seconds": 0.0, "skip": 0,
				"name": &"intro_seen", "value": true},
			{"kind": &"fade", "seconds": 0.6, "skip": 1, "alpha": 0.0},
			{"kind": &"letterbox", "seconds": 0.1, "skip": 1, "show": false},
		],
	},
	{
		# Short fixtures used by the interruption tests. They ship as content so
		# the director is exercised through the same registry as the real ones.
		"id": &"test_short", "title": "Test: skip and restore",
		"events": [
			{"kind": &"flag", "seconds": 0.0, "skip": 0,
				"name": &"test_flag", "value": true},
			{"kind": &"wait", "seconds": 0.05, "skip": 1},
			{"kind": &"wait", "seconds": 0.05, "skip": 1},
		],
	},
	{
		"id": &"test_required", "title": "Test: required beat",
		"events": [
			{"kind": &"wait", "seconds": 0.10, "skip": 1},
			{"kind": &"flag", "seconds": 0.0, "skip": 2,
				"name": &"required_flag", "value": true},
			{"kind": &"wait", "seconds": 0.05, "skip": 1},
		],
	},
	{
		"id": &"first_village", "title": "The Square",
		"events": [
			{"kind": &"letterbox", "seconds": 0.1, "skip": 1, "show": true},
			{"kind": &"dialogue", "seconds": 2.6, "skip": 1,
				"text": "The square wakes in pieces: a shouted greeting, a door, a kettle."},
			{"kind": &"dialogue", "seconds": 2.6, "skip": 1,
				"text": "Six people glance up, then go back to what they were doing."},
			{"kind": &"flag", "seconds": 0.0, "skip": 0,
				"name": &"village_introduced", "value": true},
			{"kind": &"letterbox", "seconds": 0.1, "skip": 1, "show": false},
		],
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"res://scenes/cutscenes/"))
	var event_script := load("res://scripts/cutscenes/cutscene_event.gd") as GDScript
	var player_script := load("res://scripts/cutscenes/cutscene_player.gd") as GDScript
	if event_script == null or player_script == null:
		printerr("[generate_cutscene_data] cutscene scripts are missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in CUTSCENES:
		var cutscene: Object = player_script.new()
		cutscene.set("id", spec["id"])
		cutscene.set("title", spec["title"])
		var events: Array[CutsceneEvent] = []
		for entry: Dictionary in spec["events"]:
			var event: Object = event_script.new()
			event.set("kind", entry["kind"])
			event.set("seconds", float(entry.get("seconds", 1.0)))
			event.set("text", String(entry.get("text", "")))
			event.set("skip_mode", int(entry.get("skip", 0)))
			var params: Dictionary = {}
			for key: String in entry:
				if key not in ["kind", "seconds", "text", "skip"]:
					params[StringName(key)] = entry[key]
			event.set("params", params)
			events.append(event as CutsceneEvent)
		cutscene.set("events", events)
		if not bool(cutscene.call("is_valid")):
			printerr("[generate_cutscene_data] invalid cutscene %s" % spec["id"])
			errors += 1
			continue
		var path := "%s%s.tres" % [OUT_DIR, spec["id"]]
		if ResourceSaver.save(cutscene, path) != OK:
			printerr("[generate_cutscene_data] failed to write %s" % path)
			errors += 1
	_generate_overlay()
	print("[generate_cutscene_data] wrote %d cutscenes and an overlay" % CUTSCENES.size())
	quit(1 if errors > 0 else 0)


func _generate_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CutsceneOverlay"
	layer.layer = 20
	var fade := ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# An empty style box: the default PanelContainer would paint a grey sheet
	# over the whole screen and dim the cutscene behind the text.
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var bars := VBoxContainer.new()
	bars.name = "Bars"
	bars.visible = false
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.alignment = BoxContainer.ALIGNMENT_BEGIN
	layer.add_child(bars)
	var top := ColorRect.new()
	top.name = "Top"
	top.color = Color(0, 0, 0, 1)
	top.custom_minimum_size = Vector2(0, 74)
	bars.add_child(top)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bars.add_child(spacer)
	var bottom := ColorRect.new()
	bottom.name = "Bottom"
	bottom.color = Color(0, 0, 0, 1)
	bottom.custom_minimum_size = Vector2(0, 74)
	bars.add_child(bottom)
	var text := Label.new()
	text.name = "Text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 26)
	column.add_child(text)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "E — skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	column.add_child(hint)
	_own(layer, layer)
	var packed := PackedScene.new()
	packed.pack(layer)
	ResourceSaver.save(packed, SCENE_PATH)


func _own(node: Node, top: Node) -> void:
	for child: Node in node.get_children():
		_own(child, top)
		child.owner = top
