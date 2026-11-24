class_name WaterVolume
extends Area3D
## W5.3: the pond's water volume. An Area3D with no collision response of its
## own — navigation and the pond regression (D9) are untouched. It exposes pure
## WaterPhysics queries that the player/drops can use for buoyancy and swim.

@export var surface_y: float = -0.8
@export var depth: float = 1.6


func depth_at(world_y: float) -> float:
	return clampf(surface_y - world_y, 0.0, depth)


func buoyancy_at(world_y: float, body_height: float) -> float:
	return WaterPhysics.buoyancy(depth_at(world_y), body_height)


func supports_swim(world_y: float, body_height: float) -> bool:
	return WaterPhysics.can_swim(depth_at(world_y), body_height)
