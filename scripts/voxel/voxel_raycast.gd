class_name VoxelRaycast
extends RefCounted
## Amanatides & Woo voxel traversal. Returns the first solid cell along a ray,
## or an empty dictionary when nothing is hit inside the reach.

static func cast(grid: VoxelGrid, origin: Vector3, direction: Vector3,
		reach: float = 5.0) -> Dictionary:
	var dir := direction.normalized()
	if dir.length_squared() < 0.0001:
		return {}
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(
		1 if dir.x > 0.0 else -1 if dir.x < 0.0 else 0,
		1 if dir.y > 0.0 else -1 if dir.y < 0.0 else 0,
		1 if dir.z > 0.0 else -1 if dir.z < 0.0 else 0
	)
	var t_delta := Vector3(
		absf(1.0 / dir.x) if step.x != 0 else 1.0e9,
		absf(1.0 / dir.y) if step.y != 0 else 1.0e9,
		absf(1.0 / dir.z) if step.z != 0 else 1.0e9
	)
	var boundary := Vector3(
		(float(cell.x) + (1.0 if step.x > 0 else 0.0)) - origin.x,
		(float(cell.y) + (1.0 if step.y > 0 else 0.0)) - origin.y,
		(float(cell.z) + (1.0 if step.z > 0 else 0.0)) - origin.z
	)
	var t_max := Vector3(
		t_delta.x * boundary.x if step.x != 0 else 1.0e9,
		t_delta.y * boundary.y if step.y != 0 else 1.0e9,
		t_delta.z * boundary.z if step.z != 0 else 1.0e9
	)
	var travelled := 0.0
	for _i: int in range(256):
		var block_id := grid.get_block(cell)
		if block_id != &"":
			return {"cell": cell, "block": block_id, "distance": travelled}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			travelled = t_max.x
			cell.x += step.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			travelled = t_max.y
			cell.y += step.y
			t_max.y += t_delta.y
		else:
			travelled = t_max.z
			cell.z += step.z
			t_max.z += t_delta.z
		if travelled > reach:
			break
	return {}
