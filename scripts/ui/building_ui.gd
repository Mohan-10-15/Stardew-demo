extends CanvasLayer
## Building panel: N opens, keys 1-3 buy and place, keys 7-9 upgrade that slot.

@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows") as VBoxContainer
var _open := false
var _service: BuildingService = null
var _ids: Array[StringName] = []


func _ready() -> void:
	layer = 12
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = BuildingService.find(get_tree().get_root())
	var bus := _bus()
	if bus != null:
		bus.building_placed.connect(_on_change)
		bus.building_upgraded.connect(_on_change)


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.building_placed.is_connected(_on_change):
		bus.building_placed.disconnect(_on_change)
	if bus.building_upgraded.is_connected(_on_change):
		bus.building_upgraded.disconnect(_on_change)


func _on_change(_a: StringName, _b: int, _c: int = 0) -> void:
	if _open:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Escape is the universal exit. N toggles too, but never the only way out.
	if _open and event.is_action_pressed(&"ui_cancel"):
		_open = false
		visible = false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.BUILDINGS):
		_open = not _open
		visible = _open
		if _open:
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if not _open or _service == null:
		return
	var keys := InputActions.hotbar_actions()
	for i: int in range(keys.size()):
		if not event.is_action_pressed(keys[i]):
			continue
		if i < 3:
			_service.buy_and_place(_ids[i])
		elif i - 6 < _service.placed.size():
			_service.upgrade(i - 6)
		_refresh()
		get_viewport().set_input_as_handled()
		return


func _refresh() -> void:
	if _rows == null or _service == null:
		return
	for child: Node in _rows.get_children():
		child.free()
	_ids.clear()
	var definitions := BuildingService.all_buildings()
	for i: int in range(definitions.size()):
		var data := definitions[i]
		_ids.append(data.id)
		var label := Label.new()
		label.name = "Building%d" % i
		label.text = "%d  %s — %dg (%s +%d, upgrade %dg)" % [
			i + 1, data.display_name, data.price, String(data.effect_kind),
			data.effect_value, data.upgrade_price,
		]
		_rows.add_child(label)
	for i: int in range(_service.placed.size()):
		var state: Dictionary = _service.placed[i]
		var data: BuildingData = state["data"]
		var label := Label.new()
		label.name = "Placed%d" % i
		label.text = "%d  %s — level %d, built [7-9] to upgrade" % [
			i + 7, data.display_name, int(state["level"]),
		]
		_rows.add_child(label)


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
