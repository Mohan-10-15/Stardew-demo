class_name VoxelMesher
extends RefCounted
## Culled chunk mesher. Produces arrays plus a face count; a Node3D wrapper
## turns them into an ArrayMesh later. Pure here so face counts and AO can be
## tested without a rendering context.

const FACES: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func build(grid: VoxelGrid, coord: Vector3i) -> Dictionary:
	var chunk := grid.chunk_at(coord)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var face_count := 0
	for x: int in range(VoxelChunk.SIZE):
		for y: int in range(VoxelChunk.SIZE):
			for z: int in range(VoxelChunk.SIZE):
				var block_id := chunk.get_local(x, y, z)
				if block_id == &"":
					continue
				var data := BlockRegistry.get_block(block_id)
				var is_water := data != null and data.collision_kind == "water"
				for face: Vector3i in FACES:
					var world := coord * VoxelChunk.SIZE + Vector3i(x, y, z) + face
					var neighbour := grid.get_block(world)
					if neighbour != &"" and not is_water:
						continue
					face_count += 1
					var base := vertices.size()
					var origin := Vector3(x, y, z)
					var ao := ambient_occlusion(grid, coord, Vector3i(x, y, z), face)
					for corner: Vector3 in _face_corners(face):
						vertices.append(origin + corner)
						normals.append(Vector3(face))
						uvs.append(Vector2(corner.x + corner.z, corner.y + corner.z))
						colors.append(Color(ao, ao, ao, 1.0))
					indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return {
		"vertices": vertices, "normals": normals, "uvs": uvs,
		"colors": colors, "indices": indices, "faces": face_count,
	}


## Classic 4-neighbour vertex AO: each occluded side lowers the corner.
static func ambient_occlusion(grid: VoxelGrid, coord: Vector3i,
		local: Vector3i, face: Vector3i) -> float:
	var side_a := Vector3i.ZERO
	var side_b := Vector3i.ZERO
	if face.x != 0:
		side_a = Vector3i(0, 1, 0)
		side_b = Vector3i(0, 0, 1)
	elif face.y != 0:
		side_a = Vector3i(1, 0, 0)
		side_b = Vector3i(0, 0, 1)
	else:
		side_a = Vector3i(1, 0, 0)
		side_b = Vector3i(0, 1, 0)
	var base := coord * VoxelChunk.SIZE + local + face
	var occluded := 0
	if grid.get_block(base + side_a) != &"":
		occluded += 1
	if grid.get_block(base + side_b) != &"":
		occluded += 1
	if grid.get_block(base + side_a + side_b) != &"":
		occluded += 1
	return 1.0 - float(occluded) * 0.22


static func _face_corners(face: Vector3i) -> Array[Vector3]:
	if face.x != 0:
		return [Vector3(0.5, 0, 0), Vector3(0.5, 0, 1),
			Vector3(0.5, 1, 1), Vector3(0.5, 1, 0)] as Array[Vector3]
	if face.y != 0:
		return [Vector3(0, 0.5, 0), Vector3(1, 0.5, 0),
			Vector3(1, 0.5, 1), Vector3(0, 0.5, 1)] as Array[Vector3]
	return [Vector3(0, 0, 0.5), Vector3(1, 0, 0.5),
		Vector3(1, 1, 0.5), Vector3(0, 1, 0.5)] as Array[Vector3]
