class_name CropRegistry
extends RefCounted
## The one place crop definitions are found by id.
##
## A content loader, not a service: it scans `resources/farming/crops/` once and
## answers `get_crop(&"parsnip")`. Nothing else in the game touches the
## filesystem, and nothing else hard-codes a crop name. That is what lets a
## future save file store `"parsnip"` and be restorable by a build that has
## since gained corn and lost, say, melon.
##
## Static and cached because [SoilTile] needs it and [SoilTile] is in the scene
## tree hundreds of times. A scan per lookup would be absurd; a global
## singleton would break the "no scene dependency in the simulation lane" rule.

const CROP_DIRECTORY := "res://resources/farming/crops/"
const CROP_EXTENSION := ".tres"

## id -> [CropData]
static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids that failed validation, so a broken `.tres` is reported once per session
## instead of once per tile per frame.
static var _reported: Array[StringName] = []
## Ids seen more than once while scanning. Kept alongside the warnings so a test
## can assert there are none; see [method duplicate_ids].
static var _duplicate_ids: Array[StringName] = []


## Looks a crop up by id. Returns null for an unknown id rather than defaulting
## to some crop, because silently substituting a different plant would turn a
## content bug into a wrong-but-plausible game.
static func get_crop(id: StringName) -> CropData:
	if id.is_empty():
		return null
	ensure_loaded()
	var found: Variant = _by_id.get(id)
	return found as CropData


## Every known crop, sorted by id, for shop UIs and a "what can I plant in
## winter" answer.
static func all_crops() -> Array[CropData]:
	ensure_loaded()
	var out: Array[CropData] = []
	for id: StringName in _by_id.keys():
		var crop: Variant = _by_id[id]
		if crop is CropData:
			out.append(crop)
	out.sort_custom(func(a: CropData, b: CropData) -> bool: return String(a.id) < String(b.id))
	return out


## The crops a shop should offer in [param season].
static func crops_for_season(season: int) -> Array[CropData]:
	var out: Array[CropData] = []
	for crop: CropData in all_crops():
		if crop.grows_in(season):
			out.append(crop)
	return out


static func has_crop(id: StringName) -> bool:
	return get_crop(id) != null


## Ids claimed by more than one file, sorted.
##
## A separate accessor rather than only a log line, because the log is written
## once per session and a content test needs to assert the *absence* of the
## problem. Exported as a real value it can be checked after every edit to
## `resources/farming/crops/`.
static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
	out.sort()
	return out


## Scans the crop directory once. Idempotent.
##
## Exposed as [method reload] rather than only `ensure_loaded` so a tool or test
## that has just written new `.tres` files can pick them up without restarting.
static func reload() -> void:
	_by_id.clear()
	_reported.clear()
	_duplicate_ids.clear()
	_loaded = false
	ensure_loaded()


## Clears the cache without rescanning. For tests that want to assert the *next*
## lookup fails, which is the only way to test the unknown-id path.
static func clear_cache() -> void:
	_by_id.clear()
	_reported.clear()
	_duplicate_ids.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_directory(CROP_DIRECTORY)
	# One honest line at boot: how many crops the game actually has. A count of
	# zero means the directory moved or the scan broke, and every plant action
	# will fail for a reason the player cannot see.
	Log.info("CropRegistry", "Loaded %d crops" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		Log.warn("CropRegistry", "cannot open %s" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		# `_` prefixed entries are the `.` and `..` DirAccess still reports.
		if not entry.begins_with(".") and entry.ends_with(CROP_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var res := ResourceLoader.load(path)
	var crop := res as CropData
	if crop == null:
		Log.warn("CropRegistry", "%s is not a CropData" % path)
		return
	if not crop.is_valid():
		Log.warn("CropRegistry", "%s is not a valid crop definition" % path)
		return
	if _by_id.has(crop.id):
		# Two crops claiming one id is a content bug that would make a save
		# ambiguous. First definition wins, and the collision is named.
		Log.warn("CropRegistry", "duplicate crop id '%s' in %s, ignoring" % [crop.id, path])
		if not _duplicate_ids.has(crop.id):
			_duplicate_ids.append(crop.id)
		return
	_by_id[crop.id] = crop