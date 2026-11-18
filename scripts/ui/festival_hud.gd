extends CanvasLayer
## One line announcing today's festival and whether the player has turned up.

@onready var _label: Label = get_node_or_null(^"Panel/Column/Text") as Label
var _service: Node = null


func _ready() -> void:
	layer = 7
	_service = _find()
	if _service == null:
		return
	var bus := _bus()
	bus.festival_started.connect(_on_changed)
	bus.festival_attended.connect(_on_changed)
	bus.festival_skipped.connect(_on_changed)
	bus.festival_ended.connect(_on_changed)
	_refresh()


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	for name: StringName in [&"festival_started", &"festival_attended",
			&"festival_skipped", &"festival_ended"]:
		if bus.is_connected(name, _on_changed):
			bus.disconnect(name, _on_changed)


func _on_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	if _label == null or _service == null:
		return
	var id := StringName(str(_service.get("current_id")))
	if id.is_empty():
		_label.text = ""
		return
	var data := FestivalRegistry.festival_for(id)
	var name := data.display_name if data != null else String(id)
	_label.text = "%s — %s" % [name, "ATTENDED" if bool(_service.get("attended")) \
		else "in the village square"]
	_label.visible = true


func _find() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return _search((loop as SceneTree).root)


func _search(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group(FestivalService.SERVICE_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
