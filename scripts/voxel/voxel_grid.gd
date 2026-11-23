class_name VoxelGrid
extends RefCounted
## Sparse chunks over an unbounded integer grid. Player edits are kept as
## deltas against the seeded generator, so a mined world can be saved as a
## handful of changes and reset weekly without storing every block.

var chunks: Dictionary = {}
var deltas: Dictionary = {}
var dirty: Dictionary = {}
var min_y: int = -16
var max_y: int = 48


static func chunk_coord(world: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(world.x) / VoxelChunk.SIZE),
		floori(float(world.y) / VoxelChunk.SIZE),
		floori(float(world.z) / VoxelChunk.SIZE)
	)


static func local_coord(world: Vector3i) -> Vector3i:
	return Vector3i(
		world.x - chunk_coord(world).x * VoxelChunk.SIZE,
		world.y - chunk_coord(world).y * VoxelChunk.SIZE,
		world.z - chunk_coord(world).z * VoxelChunk.SIZE
	)


func chunk_at(coord: Vector3i) -> VoxelChunk:
	if not chunks.has(coord):
		var chunk := VoxelChunk.new()
		chunks[coord] = chunk
	return chunks[coord] as VoxelChunk


func get_block(world: Vector3i) -> StringName:
	if world.y < min_y or world.y > max_y:
		return &""
	var coord := chunk_coord(world)
	if not chunks.has(coord):
		return &""
	var local := local_coord(world)
	return (chunks[coord] as VoxelChunk).get_local(local.x, local.y, local.z)


func set_block(world: Vector3i, block_id: StringName) -> bool:
	if world.y < min_y or world.y > max_y:
		return false
	var coord := chunk_coord(world)
	var local := local_coord(world)
	var chunk := chunk_at(coord)
	if not chunk.set_local(local.x, local.y, local.z, block_id):
		return false
	deltas[world] = block_id
	dirty[coord] = true
	return true


func is_air(world: Vector3i) -> bool:
	return get_block(world) == &""


func clear_dirty() -> void:
	dirty.clear()


func edit_hash() -> int:
	var keys: Array[Vector3i] = []
	for key: Variant in deltas:
		keys.append(key as Vector3i)
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x: return a.x < b.x
		if a.y != b.y: return a.y < b.y
		return a.z < b.z
	)
	var h := 0
	for key: Vector3i in keys:
		h = (h * 31 + key.x * 73856093 + key.y * 19349663 + key.z * 83492791) & 0x7FFFFFFF
		h = (h * 31 + hash(String(deltas[key]))) & 0x7FFFFFFF
	return h


func to_dict() -> Dictionary:
	var out := {}
	for key: Variant in deltas:
		out[str((key as Vector3i).x) + "," + str((key as Vector3i).y) + "," + str((key as Vector3i).z)] = String(deltas[key])
	return {"deltas": out, "min_y": min_y, "max_y": max_y}


func from_dict(data: Dictionary) -> void:
	deltas.clear()
	dirty.clear()
	var saved: Variant = data.get("deltas", {})
	if saved is Dictionary:
		for key: Variant in (saved as Dictionary):
			var parts := String(key).split(",")
			if parts.size() != 3:
				continue
			var pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			var id := StringName(String((saved as Dictionary)[key]))
			deltas[pos] = id
			var coord := chunk_coord(pos)
			var local := local_coord(pos)
			chunk_at(coord).set_local(local.x, local.y, local.z, id)
			dirty[coord] = true
	min_y = int(data.get("min_y", min_y))
	max_y = int(data.get("max_y", max_y))
