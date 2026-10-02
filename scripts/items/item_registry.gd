class_name ItemRegistry
extends RefCounted
## The one place item definitions are found by id.
##
## Same shape as [CropRegistry] on purpose: crops and items are two content
## directories with the same lookup contract, so a shop, a gift dialog and a save
## loader all ask the same question the same way.

## Where the crops' and tools' items live. Kept first because it is where the seed
## packets a farm needs to be playable already are.
const ITEM_DIRECTORY := "res://resources/farming/items/"

## Where gathering's items live.
##
## A second directory rather than moving the farming ones, because "the item
## registry scans two folders" is a strange thing to know and "where a thing is
## authored" is not. A tool or an ore is not farm content; the farm reads a handful
## of these through [ItemRegistry] without knowing or caring which folder they came
## from, which is the whole point of the registry existing.
const GATHERING_ITEM_DIRECTORY := "res://resources/gathering/items/"

## Every directory scanned, in load order. A second entry is only used when the
## first did not claim an id, so an id collision resolves in favour of the older
## content rather than whichever the filesystem happened to list first.
const ITEM_DIRECTORIES: Array[String] = [ITEM_DIRECTORY, GATHERING_ITEM_DIRECTORY]

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


## The name to show a player for [param id].
##
## Falls back to the raw id rather than an empty string. An unknown item has to say
## something: a blank label in a shop row or a bag slot looks like a rendering bug,
## whereas a bare id tells whoever is looking that the content is missing. Same
## reasoning as [method invalid_stock] on a shop.
static func display_name_of(id: StringName) -> String:
	var definition := get_item(id)
	if definition == null:
		return String(id)
	return definition.display_name


## What the player gets for selling one of [param id].
##
## Falls back to [CropData] because a harvested crop enters the bag under its own
## id and is a perfectly sellable thing, but it is defined in the crop directory
## and has no [ItemDefinition]. Asking this registry rather than making every
## caller try both is what keeps the fallback from being forgotten at the fourth
## call site.
##
## Zero means "not sellable", which is a real answer rather than a missing one: a
## seed packet costs money and has nothing to sell for, and a rock does too.
static func sell_price_of(id: StringName) -> int:
	var item := get_item(id)
	if item != null and item.sell_price > 0:
		return item.sell_price
	var crop := CropRegistry.get_crop(id)
	if crop != null:
		return crop.sell_price
	return 0


## What one of [param id] costs to buy.
##
## No crop fallback: crops are not bought, their seeds are, and those *are*
## [ItemDefinition]s with a `seed_id` pointing here. A crop with no seed packet
## has nothing to sell and correctly costs nothing.
static func buy_price_of(id: StringName) -> int:
	var item := get_item(id)
	if item == null:
		return 0
	return item.buy_price


## What one swing of [param id] costs in stamina. Zero for anything that is not a
## tool, including ids this registry has never heard of.
static func stamina_cost_of(id: StringName) -> int:
	var item := get_item(id)
	if item == null or not item.uses_durability:
		return 0
	return item.stamina_cost


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
	for directory: String in ITEM_DIRECTORIES:
		_load_directory(directory)
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