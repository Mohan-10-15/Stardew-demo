class_name VoxelChunk
extends RefCounted
## A 16³ palette-compressed chunk. Palette index 0 is always air, so an
## untouched chunk is one array of zeroes and one short palette.

const SIZE := 16
const VOLUME := SIZE * SIZE * SIZE

var palette: Array[StringName] = [&""]
var voxels: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	voxels.resize(VOLUME)


static func index(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < SIZE and z >= 0 and z < SIZE


func get_local(x: int, y: int, z: int) -> StringName:
	if not in_bounds(x, y, z):
		return &""
	var i := index(x, y, z)
	if i >= voxels.size():
		return &""
	var p: int = voxels[i]
	return palette[p] if p >= 0 and p < palette.size() else &""


func set_local(x: int, y: int, z: int, block_id: StringName) -> bool:
	if not in_bounds(x, y, z):
		return false
	var i := index(x, y, z)
	var p := 0
	if block_id != &"":
		p = palette.find(block_id)
		if p < 0:
			palette.append(block_id)
			p = palette.size() - 1
	voxels[i] = p
	return true


func is_air(x: int, y: int, z: int) -> bool:
	return get_local(x, y, z) == &""


func fill(block_id: StringName) -> void:
	var p := 0
	if block_id != &"":
		p = palette.find(block_id)
		if p < 0:
			palette.append(block_id)
			p = palette.size() - 1
	for i: int in range(VOLUME):
		voxels[i] = p


func occupied_count() -> int:
	var n := 0
	for v: int in voxels:
		if v != 0:
			n += 1
	return n


func grid_hash() -> int:
	var h := hash(str(palette))
	for v: int in voxels:
		h = (h * 31 + v) & 0x7FFFFFFF
	return h


func to_dict() -> Dictionary:
	return {"palette": palette.duplicate(), "voxels": voxels.duplicate()}


func from_dict(data: Dictionary) -> void:
	palette.clear()
	var saved_palette: Variant = data.get("palette", [])
	if saved_palette is Array:
		for id: Variant in (saved_palette as Array):
			palette.append(StringName(String(id)))
	if palette.is_empty():
		palette.append(&"")
	var saved_voxels: Variant = data.get("voxels", [])
	voxels = PackedInt32Array()
	if saved_voxels is PackedInt32Array:
		voxels = (saved_voxels as PackedInt32Array).duplicate()
	voxels.resize(VOLUME)
