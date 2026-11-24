class_name Destructible
extends Node
## W5.3: a breakable prop (crate, barrel, fence, pumpkin). Health comes from
## tool hits; on defeat it spawns bounded, non-blocking debris and its drop
## table through the existing ResourceDrop path.

const MAX_DEBRIS := 24
const DEBRIS_LIFETIME := 3.0

signal broken(node: Node)

@export var health: int = 2
@export var tool_kind: StringName = &"axe"
@export var drops: Array[StringName] = []
@export var debris_color: Color = Color(0.55, 0.38, 0.22)

var _debris: Array[Node3D] = []
var _debris_age: float = 0.0


func hit(damage: int, tool: StringName = &"") -> bool:
	if health <= 0:
		return false
	if tool != &"" and tool != tool_kind:
		return false
	health -= maxi(damage, 1)
	if health > 0:
		return false
	broken.emit(get_parent())
	_spawn_debris()
	_spawn_drops()
	return true


func _spawn_debris() -> void:
	var parent := get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(str(parent.name)) & 0x7FFFFFFF)
	for i: int in range(mini(6, MAX_DEBRIS - _debris.size())):
		var piece := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.12, 0.12, 0.12)
		piece.mesh = cube
		var mat := StandardMaterial3D.new()
		mat.albedo_color = debris_color
		piece.material_override = mat
		piece.position = Vector3(rng.randf_range(-0.3, 0.3), 0.3,
			rng.randf_range(-0.3, 0.3))
		get_tree().get_root().add_child(piece)
		piece.global_position = (parent as Node3D).global_position + piece.position
		_debris.append(piece)
	_debris_age = 0.0


func _process(delta: float) -> void:
	if _debris.is_empty():
		return
	_debris_age += delta
	if _debris_age >= DEBRIS_LIFETIME:
		_clear_debris()


func _clear_debris() -> void:
	for piece: Node3D in _debris:
		if is_instance_valid(piece):
			piece.free()
	_debris.clear()


func _spawn_drops() -> void:
	var parent := get_parent()
	if parent == null or not (parent is Node3D):
		return
	for item_id: StringName in drops:
		var drop := ResourceDrop.new()
		drop.item_id = item_id
		get_tree().get_root().add_child(drop)
		drop.global_position = (parent as Node3D).global_position + Vector3.UP * 0.4
		drop.pop(Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)))
