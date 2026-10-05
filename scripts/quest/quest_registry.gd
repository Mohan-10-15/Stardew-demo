class_name QuestRegistry
extends RefCounted
## The one place quest definitions are found by id.
##
## Same shape as [NpcRegistry], [ItemRegistry], [CropRegistry] and [ResourceNodeRegistry] on
## purpose: five content directories, one lookup contract, so the service, a test and a
## content generator all ask the same question the same way.
##
## Static and content-only, like its siblings. It never touches the scene tree, so it is
## loadable from a `--script` run â€” which is how the quest content generator validates what
## it is about to write.

const QUEST_DIRECTORY := "res://resources/quest/quests/"
const QUEST_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set is empty
## rather than discovering it as two identical-looking jobs with one of them unreachable.
static var _duplicate_ids: Array[StringName] = []
static var _order: Array[Resource] = []


static func get_quest(id: StringName) -> QuestData:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as QuestData


static func has_quest(id: StringName) -> bool:
	return get_quest(id) != null


## Everyone, in a stable order. Sorted by id for the same reason [method NpcRegistry.all_npcs]
## is: a world built twice must produce the same sequence.
static func all_quests() -> Array[QuestData]:
	ensure_loaded()
	var out: Array[QuestData] = []
	for data: Variant in _order:
		if data is QuestData:
			out.append(data)
	out.sort_custom(func(a: QuestData, b: QuestData) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


## Every job one villager offers, sorted.
##
## This is the query the NPC prompt needs, and it is a question about content rather than
## about the player â€” "what could Bram ask me for?" â€” so it stays here, next to the data,
## rather than the service filtering every quest on every prompt.
static func quests_from(giver: StringName) -> Array[QuestData]:
	var out: Array[QuestData] = []
	for data: QuestData in all_quests():
		if data.giver == giver:
			out.append(data)
	return out


## Every villager who has at least one job, with the count. For a content test that says out
## loud whether one villager ended up carrying the whole quest system.
static func givers() -> Dictionary:
	var out: Dictionary = {}
	for data: QuestData in all_quests():
		out[data.giver] = int(out.get(data.giver, 0)) + 1
	return out


## Ids claimed by more than one `.tres`.
static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
	out.sort()
	return out


## Definitions that loaded but are not playable. Collected rather than only logged so a
## content test can assert the list is empty â€” an invalid quest that merely warns is an
## invalid quest somebody will eventually ship.
static func invalid_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for data: QuestData in all_quests():
		if not data.is_valid():
			out.append(data.id)
	out.sort()
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
	_load_directory(QUEST_DIRECTORY)
	RuntimeLog.info("QuestRegistry", "Loaded %d quests" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		RuntimeLog.info("QuestRegistry", "no quest directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "" and !dir.current_is_dir():
		if not entry.begins_with(".") and entry.ends_with(QUEST_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as QuestData
	if data == null:
		RuntimeLog.warn("QuestRegistry", "%s is not a QuestData" % path)
		return
	if not data.is_valid():
		RuntimeLog.warn("QuestRegistry", "%s is not a completable quest definition" % path)
	if _by_id.has(data.id):
		RuntimeLog.warn("QuestRegistry", "duplicate quest id '%s' in %s, ignoring" % [data.id, path])
		if not _duplicate_ids.has(data.id):
			_duplicate_ids.append(data.id)
		return
	_by_id[data.id] = data
	_order.append(data)