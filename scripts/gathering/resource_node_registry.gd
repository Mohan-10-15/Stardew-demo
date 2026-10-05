class_name ResourceNodeRegistry
extends RefCounted
## The one place gatherable node definitions are found by id.
##
## Same shape as [CropRegistry] and [ItemRegistry] on purpose: three content
## directories, one lookup contract, so a spawn table, a save loader and a test all
## ask the same question the same way.
##
## Static and content-only, like its siblings. It never touches the scene tree, so it
## is loadable from a `--script` run â€” which is how the content generator validates
## what it is about to write.

const NODE_DIRECTORY := "res://resources/gathering/nodes/"
const NODE_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set is
## empty rather than discovering it as two identical-looking trees in the wood.
static var _duplicate_ids: Array[StringName] = []


static func get_node(id: StringName) -> ResourceNodeData:
	if id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(id) as ResourceNodeData


static func all_nodes() -> Array[ResourceNodeData]:
	ensure_loaded()
	var out: Array[ResourceNodeData] = []
	for id: StringName in _by_id.keys():
		var data: Variant = _by_id[id]
		if data is ResourceNodeData:
			out.append(data)
	out.sort_custom(func(a: ResourceNodeData, b: ResourceNodeData) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


static func nodes_in_category(category: int) -> Array[ResourceNodeData]:
	var out: Array[ResourceNodeData] = []
	for data: ResourceNodeData in all_nodes():
		if data.category == category:
			out.append(data)
	return out


static func has_node(id: StringName) -> bool:
	return get_node(id) != null


## Every definition the generator actually scatters, in a stable order.
##
## Sorted rather than in directory order so a world built twice from the same seed
## gets its nodes in the same sequence, and a save therefore lines up with the
## placement list it was written against.
static func spawnable_nodes() -> Array[ResourceNodeData]:
	var out: Array[ResourceNodeData] = []
	for data: ResourceNodeData in all_nodes():
		if data.spawn_count > 0:
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
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_directory(NODE_DIRECTORY)
	RuntimeLog.info("ResourceNodeRegistry", "Loaded %d resource nodes" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Not an error. A checkout with no gathering content yet still has a working
		# world, and a warning here would turn "no nodes authored" into noise nobody
		# reads past.
		RuntimeLog.info("ResourceNodeRegistry", "no node directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(NODE_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as ResourceNodeData
	if data == null:
		RuntimeLog.warn("ResourceNodeRegistry", "%s is not a ResourceNodeData" % path)
		return
	if not data.is_valid():
		RuntimeLog.warn("ResourceNodeRegistry", "%s is not a valid node definition" % path)
		return
	if _by_id.has(data.id):
		RuntimeLog.warn("ResourceNodeRegistry", "duplicate node id '%s' in %s, ignoring" % [
			data.id, path,
		])
		if not _duplicate_ids.has(data.id):
			_duplicate_ids.append(data.id)
		return
	_by_id[data.id] = data