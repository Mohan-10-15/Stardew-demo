class_name VoxelInteractor
extends Node
## Eight-input block interaction: left click (USE) breaks, right click
## (ALT_USE) places. Both go through VoxelService so every outcome publishes a
## distinct EventBus event. No player action is switched on by node type.

@export var reach: float = 5.0
var _service: VoxelService = null
var _player: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_service = VoxelService.find(get_tree().get_root())
	_player = get_parent() as Node3D


func _unhandled_input(event: InputEvent) -> void:
	if _service == null or _player == null:
		return
	if event.is_action_pressed(InputActions.USE):
		var hit := _cast()
		if not hit.is_empty():
			_service.break_at(hit["cell"], _held_id())
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.ALT_USE):
		var hit := _cast()
		var block := VoxelService.block_for_item(_held_id())
		if not hit.is_empty() and block != &"":
			var cell: Vector3i = hit["cell"]
			var face: Vector3i = hit.get("normal", Vector3i.UP)
			_service.place_at(cell + face, block)
			get_viewport().set_input_as_handled()


func _cast() -> Dictionary:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return {}
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var hit := _service.raycast(from, dir, reach)
	if hit.is_empty():
		return {}
	# Recover the face from the hit point: the DDA records the cell but not the
	# normal, so compare with the camera-to-cell vector.
	var cell: Vector3i = hit["cell"]
	var centre := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var delta := centre - from
	var normal := Vector3i.ZERO
	var ax := absf(delta.x)
	var ay := absf(delta.y)
	var az := absf(delta.z)
	if ax >= ay and ax >= az:
		normal = Vector3i(-1 if delta.x > 0 else 1, 0, 0)
	elif ay >= az:
		normal = Vector3i(0, -1 if delta.y > 0 else 1, 0)
	else:
		normal = Vector3i(0, 0, -1 if delta.z > 0 else 1)
	hit["normal"] = normal
	return hit


func _held_id() -> StringName:
	var state := _find_named(get_tree().get_root(), &"PlayerState")
	if state == null:
		return &""
	var held: Dictionary = state.call("held_item_id")
	return StringName(held.get("id", &""))


static func find(start: Node) -> VoxelInteractor:
	if start == null:
		return null
	if start is VoxelInteractor:
		return start as VoxelInteractor
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


static func _find_named(node: Node, wanted: StringName) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
