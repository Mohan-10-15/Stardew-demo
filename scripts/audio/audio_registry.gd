class_name AudioRegistry
extends RefCounted
## The one place sound definitions are loaded from disk by id.
##
## Same shape as [NpcRegistry] and [ScheduleRegistry]: a directory, a lookup,
## a duplicate report, and a cache that content tools can clear. Static and
## content-only so a `--script` test can ask about ids without a scene tree.

const DIRECTORY := "res://resources/audio/sounds/"
const EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _order: Array[Resource] = []
static var _duplicates: Array[StringName] = []
static var _loaded: bool = false


static func sound_for(id: StringName) -> AudioDefinition:
	ensure_loaded()
	return _by_id.get(id) as AudioDefinition


static func has_sound(id: StringName) -> bool:
	return sound_for(id) != null


static func all_sounds() -> Array[AudioDefinition]:
	ensure_loaded()
	var out: Array[AudioDefinition] = []
	for item: Resource in _order:
		if item is AudioDefinition:
			out.append(item)
	out.sort_custom(func(a: AudioDefinition, b: AudioDefinition) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	return _duplicates.duplicate()


static func clear_cache() -> void:
	_by_id.clear()
	_order.clear()
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
		if entry.ends_with(EXTENSION):
			_load("%s%s" % [DIRECTORY, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load(path: String) -> void:
	var definition := ResourceLoader.load(path) as AudioDefinition
	if definition == null or not definition.is_valid():
		RuntimeLog.warn("AudioRegistry", "%s is not a valid sound" % path)
		return
	if _by_id.has(definition.id):
		RuntimeLog.warn("AudioRegistry", "duplicate sound '%s' in %s" % [definition.id, path])
		if not _duplicates.has(definition.id):
			_duplicates.append(definition.id)
		return
	_by_id[definition.id] = definition
	_order.append(definition)
