class_name FestivalRegistry
extends RefCounted

const DIRECTORY := "res://resources/festivals/"

static var _by_id: Dictionary = {}


static func festival_for(id: StringName) -> FestivalData:
	ensure_loaded()
	return _by_id.get(id) as FestivalData


static func on(season: int, day: int) -> FestivalData:
	for festival: FestivalData in all():
		if festival.occurs_on(season, day):
			return festival
	return null


static func all() -> Array[FestivalData]:
	ensure_loaded()
	var out: Array[FestivalData] = []
	for item: Variant in _by_id.values():
		if item is FestivalData:
			out.append(item)
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
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("%s%s" % [DIRECTORY, entry]) as FestivalData
			if data != null and data.is_valid():
				_by_id[data.id] = data
		entry = dir.get_next()
	dir.list_dir_end()
