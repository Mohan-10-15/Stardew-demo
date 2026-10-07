class_name DialogueRegistry
extends RefCounted
## The one place a villager's authored words are found by id.
##
## Same contract as [ScheduleRegistry], [NpcRegistry], [LocationRegistry] and the
## rest: a content directory, a static lookup keyed by the id the content
## itself carries, and a duplicate report. Static and content-only — no scene
## tree, no signals — so it loads in a `--script` run and a content test can ask
## "does every villager have words, and do they all resolve" without booting a
## village.
##
## An invalid tree is refused here rather than at 08:00 when the player first
## says hello: [method DialogueTree.is_valid] names the entry at fault, and the
## message lands in the log at boot instead of as a villager who goes quiet.

const DIALOGUE_DIRECTORY := "res://resources/npc/dialogue/"
const DIALOGUE_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set
## is empty — the same reason [ScheduleRegistry] keeps its own: two trees for
## one villager would resolve to whichever loaded last, and a villager's words
## must not depend on directory iteration order.
static var _duplicate_ids: Array[StringName] = []
static var _order: Array[Resource] = []


## The tree for [param npc_id], or null if nobody authored one.
static func tree_for(npc_id: StringName) -> DialogueTree:
	if npc_id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(npc_id) as DialogueTree


static func has_tree(npc_id: StringName) -> bool:
	return tree_for(npc_id) != null


## Every tree, sorted by villager id, so a caller that iterates does so stably.
static func all_trees() -> Array[DialogueTree]:
	ensure_loaded()
	var out: Array[DialogueTree] = []
	for data: Variant in _order:
		if data is DialogueTree:
			out.append(data)
	out.sort_custom(func(a: DialogueTree, b: DialogueTree) -> bool:
		return String(a.npc_id) < String(b.npc_id)
	)
	return out


static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
	out.sort()
	return out


## Villagers who have a tree but no definition, and definitions with no tree.
##
## Both halves belong to the content test rather than the loader, for the reason
## [ScheduleRegistry] states: loading content should not need every other
## content directory. Returned as two lists so a failure can say which side of
## the mismatch is stale.
static func coverage_gaps(npc_ids: Array[StringName]) -> Dictionary:
	ensure_loaded()
	var missing: Array[StringName] = []
	var orphaned: Array[StringName] = []
	for npc_id: StringName in npc_ids:
		if not _by_id.has(npc_id):
			missing.append(npc_id)
	for id: StringName in _by_id.keys():
		if not npc_ids.has(id):
			orphaned.append(id)
	missing.sort()
	orphaned.sort()
	return {"missing": missing, "orphaned": orphaned}


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
	_load_directory(DIALOGUE_DIRECTORY)
	RuntimeLog.info("DialogueRegistry", "Loaded %d dialogue trees" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Not an error, same reasoning as [NpcRegistry]: a checkout with no
		# authored words yet still has a working village that says hello.
		RuntimeLog.info("DialogueRegistry", "no dialogue directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(DIALOGUE_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as DialogueTree
	if data == null:
		RuntimeLog.warn("DialogueRegistry", "%s is not a DialogueTree" % path)
		return
	var problem := data.is_valid()
	if not problem.is_empty():
		# An invalid tree is a content bug — most commonly a reply pointing at
		# an entry id that was renamed — and loading it anyway would make the
		# failure appear later as a villager who stops mid-conversation with
		# nothing in the log to explain it.
		RuntimeLog.warn("DialogueRegistry", "%s refused: %s" % [path, problem])
		return
	if _by_id.has(data.npc_id):
		RuntimeLog.warn("DialogueRegistry", "duplicate tree for '%s' in %s, ignoring" % [
			data.npc_id, path,
		])
		if not _duplicate_ids.has(data.npc_id):
			_duplicate_ids.append(data.npc_id)
		return
	_by_id[data.npc_id] = data
	_order.append(data)
