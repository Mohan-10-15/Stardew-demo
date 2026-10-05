class_name LocationRegistry
extends RefCounted
## The one place named locations are found by id.
##
## Same contract as [NpcRegistry], [ResourceNodeRegistry], [CropRegistry] and
## [ItemRegistry]: a content directory, a static lookup, and a duplicate-id report. Five
## content directories now, one shape, so a schedule, a test and a save loader all ask
## the same question the same way.
##
## Static and content-only, like its siblings. It never touches the scene tree, so it
## loads in a `--script` run â€” which is how the content generator validates what it is
## about to write.

const LOCATION_DIRECTORY := "res://resources/world/locations/"
const LOCATION_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set is empty
## rather than discovering it as two places that quietly resolve to whichever loaded
## last, which would mean a schedule silently retargets when someone adds a file.
static var _duplicate_ids: Array[StringName] = []
static var _order: Array[Resource] = []


static func get_location(id: StringName) -> LocationData:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as LocationData


## Every location, sorted by id, so a world built twice places things in the same order.
static func all_locations() -> Array[LocationData]:
	ensure_loaded()
	var out: Array[LocationData] = []
	for data: Variant in _order:
		if data is LocationData:
			out.append(data)
	out.sort_custom(func(a: LocationData, b: LocationData) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func has_location(id: StringName) -> bool:
	return get_location(id) != null


static func locations_of_kind(kind: StringName) -> Array[LocationData]:
	var out: Array[LocationData] = []
	for data: LocationData in all_locations():
		if data.kind == kind:
			out.append(data)
	return out


static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
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
	_load_directory(LOCATION_DIRECTORY)
	RuntimeLog.info("LocationRegistry", "Loaded %d locations" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Not an error, same reasoning as [NpcRegistry]: a checkout with no authored
		# places yet still has a working world.
		RuntimeLog.info("LocationRegistry", "no location directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(LOCATION_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as LocationData
	if data == null:
		RuntimeLog.warn("LocationRegistry", "%s is not a LocationData" % path)
		return
	if not data.is_valid():
		RuntimeLog.warn("LocationRegistry", "%s is not a valid location definition" % path)
		return
	if _by_id.has(data.id):
		RuntimeLog.warn("LocationRegistry", "duplicate location id '%s' in %s, ignoring" % [
			data.id, path,
		])
		if not _duplicate_ids.has(data.id):
			_duplicate_ids.append(data.id)
		return
	_by_id[data.id] = data
	_order.append(data)