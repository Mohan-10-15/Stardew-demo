extends CanvasLayer
## Keyboard-only settings and accessibility panel. F2 opens and closes it,
## arrows move the highlight, left/right change a value, Enter activates, and
## Escape always closes. While rebinding, the next key press becomes the new
## binding — there is no mouse-only step anywhere in the loop.

const SCALE_STEP := 0.05
const SCALE_MIN := 0.75
const SCALE_MAX := 1.5
const REBIND_ROWS: Array[StringName] = [
	InputActions.INTERACT, InputActions.INVENTORY, InputActions.CRAFT, InputActions.BUILD,
]

@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows") as VBoxContainer

var _open := false
var _selected := 0
var _listening: StringName = &""
var _service: RebindService = null


func _ready() -> void:
	layer = 14
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = RebindService.find(get_tree().get_root())
	var bus := _bus()
	if bus != null:
		bus.settings_applied.connect(_on_settings_applied)
		bus.input_rebound.connect(_on_rebound)


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.settings_applied.is_connected(_on_settings_applied):
		bus.settings_applied.disconnect(_on_settings_applied)
	if bus.input_rebound.is_connected(_on_rebound):
		bus.input_rebound.disconnect(_on_rebound)


static func find(start: Node) -> CanvasLayer:
	if start == null:
		return null
	for child: Node in start.get_children():
		if child is CanvasLayer and child.name == "SettingsUI":
			return child as CanvasLayer
		var found := find(child)
		if found != null:
			return found
	return null


func _on_settings_applied() -> void:
	if _open:
		_refresh()


func _on_rebound(_action: StringName, _keycode: int) -> void:
	_listening = &""
	if _open:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(InputActions.SETTINGS):
		if _open:
			_close()
		else:
			_open_panel()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return

	# A rebind consumes the very next key, including keys that would otherwise
	# navigate this menu — that is the whole point of a listening mode.
	if not _listening.is_empty():
		if event is InputEventKey and event.is_pressed():
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if code > 0 and _service != null:
				_service.rebind(_listening, code)
			_listening = &""
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_down"):
		_selected = (_selected + 1) % _row_count()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_up"):
		_selected = (_selected - 1 + _row_count()) % _row_count()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_left"):
		_adjust_scale(-SCALE_STEP)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_right"):
		_adjust_scale(SCALE_STEP)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		_activate()
		get_viewport().set_input_as_handled()


func _open_panel() -> void:
	_open = true
	visible = true
	_selected = 0
	_listening = &""
	_refresh()


func _close() -> void:
	_open = false
	_listening = &""
	visible = false


func _row_count() -> int:
	# scale, contrast, block textures, the rebind rows, then reset
	return 3 + REBIND_ROWS.size() + 1


func _adjust_scale(delta: float) -> void:
	if _selected != 0:
		return
	var next := clampf(
		snappedf(Config.settings.ui_scale + delta, SCALE_STEP), SCALE_MIN, SCALE_MAX
	)
	Config.set_value(&"accessibility", "ui_scale", next)


func _activate() -> void:
	if _selected == 0:
		_adjust_scale(SCALE_STEP)
	elif _selected == 1:
		Config.set_value(&"accessibility", "colour_assist", not Config.settings.colour_assist)
	elif _selected == 2:
		var other := "pixel16" if Config.settings.voxel_texture_pack != "pixel16" \
			else "hollowbrook_detailed"
		var voxels: Node = _panel(&"VoxelService")
		if voxels == null or not bool(voxels.call("set_texture_pack", other)):
			Config.set_value(&"world", "voxel_texture_pack", other)
	elif _selected < _row_count() - 1:
		_listening = REBIND_ROWS[_selected - 3]
		_refresh()
	else:
		Config.reset_to_defaults()
		if _service != null:
			_service.reset_all()
		_refresh()


func _refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.free()
	_add_row("Text size: %d%%  (< / > to change)" % roundi(Config.settings.ui_scale * 100.0), 0)
	_add_row("High contrast: %s  (Enter to toggle)" % (
		"ON" if Config.settings.colour_assist else "OFF"
	), 1)
	_add_row("Block textures: %s  (Enter to swap)" % Config.settings.voxel_texture_pack, 2)
	for i: int in range(REBIND_ROWS.size()):
		var action := REBIND_ROWS[i]
		var name := String(action).capitalize()
		var key := _service.label_for(action) if _service != null else "?"
		_add_row("Rebind %s: %s  (Enter, then a key)" % [name, key], i + 3)
	_add_row("Reset everything to defaults", _row_count() - 1)


func _add_row(text: String, index: int) -> void:
	var label := Label.new()
	label.name = "Row%d" % index
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prefix := "> " if index == _selected else "  "
	if index == _selected and not _listening.is_empty():
		prefix = "> (listening) "
	label.text = prefix + text
	_rows.add_child(label)


func _panel(name: StringName) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return _find_named((loop as SceneTree).root, name)


func _find_named(node: Node, wanted: StringName) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
