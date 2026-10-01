class_name ItemRegistry
extends RefCounted
## The one place item definitions are found by id.
##
## Same shape as [CropRegistry] on purpose: crops and items are two content
## directories with the same lookup contract, so a shop, a gift dialog and a save
## loader all ask the same question the same way.

const ITEM_DIRECTORY := "res://resources/farming/items/"
const ITEM_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids seen more than once while scanning. Kept so a content test can assert the
## set is empty; see [method duplicate_ids].
static var _duplicate_ids: Array[StringName] = []


static func get_item(id: StringName) -> ItemDefinition:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as ItemDefinition


static func all_items() -> Array[ItemDefinition]:
	ensure_loaded()
	var out: Array[ItemDefinition] = []
	for id: StringName in _by_id.keys():
		var item: Variant = _by_id[id]
		if item is ItemDefinition:
			out.append(item)
	out.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func items_in_category(category: int) -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for item: ItemDefinition in all_items():
		if item.category == category:
			out.append(item)
	return out


static func has_item(id: StringName) -> bool:
	return get_item(id) != null


## Ids claimed by more than one file, sorted. Empty in a healthy content set.
static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
	out.sort()
	return out


static func reload() -> void:
	_by_id.clear()
	_duplicate_ids.clear()
	_loaded = false
	ensure_loaded()


static func clear_cache() -> void:
	_by_id.clear()
	_duplicate_ids.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_directory(ITEM_DIRECTORY)
	Log.info("ItemRegistry", "Loaded %d items" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		Log.warn("ItemRegistry", "cannot open %s" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(ITEM_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var item := ResourceLoader.load(path) as ItemDefinition
	if item == null:
		Log.warn("ItemRegistry", "%s is not an ItemDefinition" % path)
		return
	if not item.is_valid():
		Log.warn("ItemRegistry", "%s is not a valid item definition" % path)
		return
	if _by_id.has(item.id):
		Log.warn("ItemRegistry", "duplicate item id '%s' in %s, ignoring" % [item.id, path])
		if not _duplicate_ids.has(item.id):
			_duplicate_ids.append(item.id)
		return
	_by_id[item.id] = item