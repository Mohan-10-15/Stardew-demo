class_name ShopRegistry
extends RefCounted
## The one place shop definitions are found by id.
##
## Same shape as [ItemRegistry] and [CropRegistry] on purpose: three content
## directories, one lookup contract, so the world builder, a save loader and a shop
## UI all ask the same question the same way.

const SHOP_DIRECTORY := "res://resources/economy/shops/"
const SHOP_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
static var _duplicate_ids: Array[StringName] = []


static func get_shop(id: StringName) -> ShopDefinition:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as ShopDefinition


static func all_shops() -> Array[ShopDefinition]:
	ensure_loaded()
	var out: Array[ShopDefinition] = []
	for id: StringName in _by_id.keys():
		var shop: Variant = _by_id[id]
		if shop is ShopDefinition:
			out.append(shop)
	out.sort_custom(func(a: ShopDefinition, b: ShopDefinition) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func has_shop(id: StringName) -> bool:
	return get_shop(id) != null


## Ids claimed by more than one file, sorted. Empty in a healthy content set.
static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	return _duplicate_ids.duplicate()


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
	_load_directory(SHOP_DIRECTORY)
	RuntimeLog.info("ShopRegistry", "Loaded %d shops" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		RuntimeLog.warn("ShopRegistry", "cannot open %s" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(SHOP_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var shop := ResourceLoader.load(path) as ShopDefinition
	if shop == null:
		RuntimeLog.warn("ShopRegistry", "%s is not a ShopDefinition" % path)
		return
	if not shop.is_valid():
		RuntimeLog.warn("ShopRegistry", "%s is not a valid shop definition" % path)
		return
	if _by_id.has(shop.id):
		RuntimeLog.warn("ShopRegistry", "duplicate shop id '%s' in %s, ignoring" % [shop.id, path])
		if not _duplicate_ids.has(shop.id):
			_duplicate_ids.append(shop.id)
		return
	_by_id[shop.id] = shop