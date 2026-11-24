class_name EnemyRegistry
extends RefCounted

const DIRECTORY := "res://resources/combat/enemies/"

static var _by_id: Dictionary = {}


static func enemy_for(id: StringName) -> EnemyData:
	ensure_loaded()
	return _by_id.get(id) as EnemyData


static func all() -> Array[EnemyData]:
	ensure_loaded()
	var out: Array[EnemyData] = []
	for item: Variant in _by_id.values():
		if item is EnemyData:
			out.append(item)
	return out


static func bosses() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for data: EnemyData in all():
		if data.is_boss:
			out.append(data)
	return out


static func clear_cache() -> void:
	_by_id.clear()


static func ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if ResourceFiles.is_resource(entry):
			var data := ResourceLoader.load(ResourceFiles.path_for(DIRECTORY, entry)) as EnemyData
			if data != null and data.is_valid():
				_by_id[data.id] = data
		entry = dir.get_next()
	dir.list_dir_end()
