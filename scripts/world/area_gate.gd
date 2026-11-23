extends Interactable
## A soft, player-only barrier. The ash drift is visual; the collider lives on
## the GATE layer, which the player's mask includes and villagers' does not.
## Reaching the collection tier named by `unlock_id` opens it permanently.

@export var gate_id: StringName = &""
@export var unlock_id: StringName = &""
@export var region_name: String = "the path ahead"

var _body: StaticBody3D = null
var _ash: Node3D = null
var _open := false


func _ready() -> void:
	super()
	prompt_text = "Path closed — %s" % region_name
	_body = get_parent() as StaticBody3D
	if _body != null:
		_body.collision_layer = PhysicsLayers.GATE
		_body.collision_mask = 0
	_ash = _body.get_node_or_null(^"AshDrift") if _body != null else null
	var bus := _bus()
	if bus != null and not bus.collection_tier_reached.is_connected(_on_tier):
		bus.collection_tier_reached.connect(_on_tier)


func _exit_tree() -> void:
	var bus := _bus()
	if bus != null and bus.collection_tier_reached.is_connected(_on_tier):
		bus.collection_tier_reached.disconnect(_on_tier)


func _on_tier(_id: StringName, _tier: int, unlock: StringName, _ember: StringName) -> void:
	if unlock == unlock_id:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	if _body != null:
		_body.collision_layer = 0
	if _ash != null:
		_ash.visible = false
	EventBus.area_gate_opened.emit(gate_id)


func is_open() -> bool:
	return _open


func get_prompt(_actor: Node) -> String:
	if _open:
		return ""
	return "Path closed — %s" % region_name


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
