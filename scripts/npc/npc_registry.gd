class_name NpcRegistry
extends RefCounted
## The one place villager definitions are found by id.
##
## Same shape as [ResourceNodeRegistry], [CropRegistry] and [ItemRegistry] on
## purpose: four content directories, one lookup contract, so the manager, a test and
## a save loader all ask the same question the same way.
##
## Static and content-only, like its siblings. It never touches the scene tree, so it
## is loadable from a `--script` run — which is how the content generator validates
## what it is about to write.

const NPC_DIRECTORY := "res://resources/npc/npcs/"
const NPC_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set is
## empty rather than discovering it as two identical-looking villagers in the square.
static var _duplicate_ids: Array[StringName] = []
## Every loaded definition, so a caller can place the whole cast without walking ids
## it would otherwise have to invent.
static var _order: Array[Resource] = []


static func get_npc(id: StringName) -> NpcData:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as NpcData


## Everyone, in a stable order.
##
## Sorted by id rather than directory order, so a world built twice places the cast
## in the same sequence and a save lines up with the placement list it was written
## against. This is the same reason [method ResourceNodeRegistry.spawnable_nodes] sorts.
static func all_npcs() -> Array[NpcData]:
	ensure_loaded()
	var out: Array[NpcData] = []
	for data: Variant in _order:
		if data is NpcData:
			out.append(data)
	out.sort_custom(func(a: NpcData, b: NpcData) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func has_npc(id: StringName) -> bool:
	return get_npc(id) != null


## Ids claimed by more than one `.tres`.
static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
	out.sort()
	return out


## Every distinct (model, tint, height) triple the cast wears.
##
## Reported rather than policed: two villagers in the same outfit is a legitimate
## thing for an author to want, and the point is for a content test to be able to say
## so out loud instead of nobody noticing that five of the six are the same Knight.
static func appearances() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for data: NpcData in all_npcs():
		var key := "%s|%s|%.2f" % [data.model, data.model_tint.to_html(false), data.target_height]
		if not out.has(key):
			out.append(key)
	return out


## How many villagers wear one appearance.
static func count_per_appearance() -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	for data: NpcData in all_npcs():
		var key := "%s|%s|%.2f" % [data.model, data.model_tint.to_html(false), data.target_height]
		out[key] = int(out.get(key, 0)) + 1
	return out


static func reload() -> void:
	clear_cache()
	ensure_loaded()


static func clear_cache() -> void:
	_by_id.clear()
	_duplicate_ids.clear()
	_order.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_directory(NPC_DIRECTORY)
	Log.info("NpcRegistry", "Loaded %d villagers" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Not an error. A checkout with no villager content yet still has a working
		# world, and a warning here would turn "no villagers authored" into noise
		# nobody reads past.
		Log.info("NpcRegistry", "no villager directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(NPC_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as NpcData
	if data == null:
		Log.warn("NpcRegistry", "%s is not a NpcData" % path)
		return
	if not data.is_valid():
		Log.warn("NpcRegistry", "%s is not a valid villager definition" % path)
		return
	if _by_id.has(data.id):
		Log.warn("NpcRegistry", "duplicate villager id '%s' in %s, ignoring" % [
			data.id, path,
		])
		if not _duplicate_ids.has(data.id):
			_duplicate_ids.append(data.id)
		return
	_by_id[data.id] = data
	_order.append(data)