class_name BlockRegistry
extends RefCounted
## One lookup contract for block content, shaped like NpcRegistry/AudioRegistry.
## Static and content-only so a --script tool can load it.

const DIR := "res://resources/voxel/blocks/"

static var _by_id: Dictionary = {}
static var _loaded := false
static var _duplicates: Array[StringName] = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for entry: String in dir.get_files():
		if not ResourceFiles.is_resource(entry):
			continue
		var data := ResourceLoader.load(ResourceFiles.path_for(DIR, entry)) as BlockData
		if data == null or not data.is_valid():
			continue
		if _by_id.has(data.id):
			_duplicates.append(data.id)
		_by_id[data.id] = data


static func get_block(id: StringName) -> BlockData:
	ensure_loaded()
	return _by_id.get(id) as BlockData


static func has_block(id: StringName) -> bool:
	return get_block(id) != null


static func all_blocks() -> Array[BlockData]:
	ensure_loaded()
	var out: Array[BlockData] = []
	for id: StringName in _by_id:
		var data: Variant = _by_id[id]
		if data is BlockData:
			out.append(data)
	out.sort_custom(func(a: BlockData, b: BlockData) -> bool: return String(a.id) < String(b.id))
	return out


static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	return _duplicates.duplicate()


static func clear_cache() -> void:
	_by_id.clear()
	_duplicates.clear()
	_loaded = false
