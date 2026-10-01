class_name WorldRoot
extends Node3D
## Owns the generated valley and exposes the regions other systems care about.
##
## Generation is deferred one frame so the player (which main.gd adds as a
## sibling) can position itself relative to the finished terrain without
## spawning into geometry that does not exist yet.

@export var world_seed: int = 12345
@export var spawn_point: Vector3 = Vector3(0, 1.2, 14)
@export var generate: bool = true

var _built := false


func _ready() -> void:
	if not generate:
		return
	_build_world()


func _build_world() -> void:
	if _built:
		return
	_built = true
	WorldBuilder.build(self, world_seed)
	Log.info("World", "Built valley (seed=%d), %d children" % [world_seed, get_child_count()])
	EventBus.world_loaded.emit()


func get_spawn_point() -> Vector3:
	return spawn_point


## Region centres, so the minimap (Group 25) and area transitions (Group 31)
## do not need to know how the world was laid out.
func get_region_centre(region_name: StringName) -> Vector3:
	match region_name:
		&"farm":
			return Vector3(WorldBuilder.REGION_FARM.x, 0, WorldBuilder.REGION_FARM.y)
		&"village":
			return Vector3(WorldBuilder.REGION_VILLAGE.x, 0, WorldBuilder.REGION_VILLAGE.y)
		&"forest":
			return Vector3(WorldBuilder.REGION_FOREST.x, 0, WorldBuilder.REGION_FOREST.y)
		&"pond":
			return Vector3(WorldBuilder.REGION_POND.x, 0, WorldBuilder.REGION_POND.y)
	return Vector3.ZERO