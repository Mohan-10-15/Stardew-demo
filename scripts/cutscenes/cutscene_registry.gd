class_name CutsceneRegistry
extends RefCounted
## The one place authored cutscenes are found by id. Static and content-only,
## like [ScheduleRegistry], so a content test can check the catalogue without
## a scene tree.

const DIRECTORY := "res://resources/cutscenes/"

static var _by_id: Dictionary = {}
static var _duplicates: Array[StringName] = []
static var _loaded: bool = false


static func cutscene_for(id: StringName) -> CutscenePlayer:
	ensure_loaded()
	return _by_id.get(id) as CutscenePlayer


static func all() -> Array[CutscenePlayer]:
	ensure_loaded()
	var out: Array[CutscenePlayer] = []
	for item: Variant in _by_id.values():
		if item is CutscenePlayer:
			out.append(item)
	out.sort_custom(func(a: CutscenePlayer, b: CutscenePlayer) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	return _duplicates.duplicate()


static func clear_cache() -> void:
	_by_id.clear()
	_duplicates.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if ResourceFiles.is_resource(entry):
			_load(ResourceFiles.path_for(DIRECTORY, entry))
		entry = dir.get_next()
	dir.list_dir_end()


static func _load(path: String) -> void:
	var cutscene := ResourceLoader.load(path) as CutscenePlayer
	if cutscene == null or not cutscene.is_valid():
		RuntimeLog.warn("CutsceneRegistry", "%s is not a valid cutscene" % path)
		return
	if _by_id.has(cutscene.id):
		if not _duplicates.has(cutscene.id):
			_duplicates.append(cutscene.id)
		return
	_by_id[cutscene.id] = cutscene
