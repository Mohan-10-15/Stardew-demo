class_name DecorationRegistry
extends RefCounted
## The one place scenery definitions are found by id.
##
## Same shape as [ResourceNodeRegistry] on purpose: one lookup contract for every
## content directory, so a generator, a test and the world builder all ask the same
## question the same way. Static and content-only, so it loads in a `--script` run —
## which is how `tools/generate_decoration_data.gd` validates what it is about to write.

const DECORATION_DIRECTORY := "res://resources/world/decoration/"
const DECORATION_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set is
## empty rather than discovering it as two identical-looking bushes.
static var _duplicate_ids: Array[StringName] = []


static func get_decoration(id: StringName) -> DecorationData:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as DecorationData


static func all_decorations() -> Array[DecorationData]:
	ensure_loaded()
	var out: Array[DecorationData] = []
	for id: StringName in _by_id:
		var data: Variant = _by_id[id]
		if data is DecorationData:
			out.append(data)
	out.sort_custom(func(a: DecorationData, b: DecorationData) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


## Every definition the world actually scatters, in a stable order.
##
## Sorted rather than in directory order so a world built twice from the same seed
## places its scenery in the same sequence — which is what makes the placement
## reproducible at all, and therefore testable.
static func scatterable_decorations() -> Array[DecorationData]:
	var out: Array[DecorationData] = []
	for data: DecorationData in all_decorations():
		if data.spawn_count > 0:
			out.append(data)
	return out


static func has_decoration(id: StringName) -> bool:
	return get_decoration(id) != null


static func duplicate_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _duplicate_ids:
		out.append(id)
	out.sort()
	return out


## The model paths in use, so a content test can assert that no definition points at
## a model a gatherable already owns — two definitions sharing one model is how the
## same tree ends up both harvestable and decorative.
static func model_paths() -> Array[String]:
	var out: Array[String] = []
	for data: DecorationData in all_decorations():
		if not out.has(data.model):
			out.append(data.model)
	out.sort()
	return out


static func clear_cache() -> void:
	_by_id.clear()
	_duplicate_ids.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_directory(DECORATION_DIRECTORY)
	Log.info("DecorationRegistry", "Loaded %d decorations" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Not an error, same as its siblings: a checkout with no scenery authored yet
		# still has a working world, and a warning here becomes noise nobody reads.
		Log.info("DecorationRegistry", "no decoration directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(DECORATION_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as DecorationData
	if data == null:
		Log.warn("DecorationRegistry", "%s is not a DecorationData" % path)
		return
	if not data.is_valid():
		Log.warn("DecorationRegistry", "%s is not a valid decoration definition" % path)
		return
	if _by_id.has(data.id):
		Log.warn("DecorationRegistry", "duplicate decoration id '%s' in %s, ignoring" % [
			data.id, path,
		])
		if not _duplicate_ids.has(data.id):
			_duplicate_ids.append(data.id)
		return
	_by_id[data.id] = data