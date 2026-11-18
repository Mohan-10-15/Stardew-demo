extends CanvasLayer
## Build panel: B opens, number keys buy and place a machine on the next free pad.

@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows") as VBoxContainer
var _open := false
var _ids: Array[StringName] = []
var _service: MachineService = null


func _ready() -> void:
	layer = 12
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = MachineService.find(get_tree().get_root())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.BUILD):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	var keys := InputActions.hotbar_actions()
	for i: int in range(keys.size()):
		if event.is_action_pressed(keys[i]):
			if i < _ids.size():
				_buy(_ids[i])
			get_viewport().set_input_as_handled()
			return


func _toggle() -> void:
	_open = not _open
	visible = _open
	if _open:
		_refresh()


func _buy(id: StringName) -> void:
	if _service == null:
		return
	var definition: MachineData = null
	for data: MachineData in MachineService.all_machines():
		if data.id == id:
			definition = data
			break
	if definition == null:
		return
	var state := _find_named(get_tree().get_root(), "PlayerState")
	if state == null or state.get("wallet") == null:
		return
	var wallet: Object = state.get("wallet")
	if int(wallet.get("gold")) < definition.price:
		return
	wallet.call("set_gold", int(wallet.get("gold")) - definition.price)
	_service.place(id)
	_refresh()


func _refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.free()
	_ids.clear()
	var machines := MachineService.all_machines()
	for i: int in range(machines.size()):
		var data := machines[i]
		_ids.append(data.id)
		var label := Label.new()
		label.name = "Machine%d" % i
		label.text = "%d  %s — %dg  (%s → %s in %dd)" % [
			i + 1, data.display_name, data.price, String(data.input_id),
			String(data.output_id), data.process_days,
		]
		_rows.add_child(label)


func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
