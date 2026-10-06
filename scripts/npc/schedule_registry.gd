class_name ScheduleRegistry
extends RefCounted
## The one place a villager's authored day is found by id.
##
## Same contract as [LocationRegistry], [NpcRegistry], [ResourceNodeRegistry],
## [CropRegistry] and [ItemRegistry]: a content directory, a static lookup keyed by
## the id the content itself carries, and a duplicate report. Six content
## directories now, one shape.
##
## Keyed on [member NpcSchedule.npc_id] rather than the file name, because the file
## name is not load-bearing and a renamed `.tres` must not silently detach a
## villager from their day. The id in the file is what the schedule says it is about.
##
## Static and content-only, like its siblings: no scene tree, no signals, so it loads
## in a `--script` run. That is what lets the content generator validate what it is
## about to write and what lets a test ask "does every destination resolve" without
## booting a village.
##
## A schedule for a villager who is not in `resources/npc/npcs/` is *not* refused
## here - that check belongs to the content test, because a registry whose job is
## "load the schedules" should not need to know every other content directory to do
## it. It is refused at test time, where the message can say which of the two files
## is the stale one.

const SCHEDULE_DIRECTORY := "res://resources/npc/schedules/"
const SCHEDULE_EXTENSION := ".tres"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
## Ids claimed by more than one file, kept so a content test can assert the set is
## empty rather than discovering it as two days that quietly resolve to whichever
## loaded last - which would mean a villager's morning routine changes depending on
## directory iteration order.
static var _duplicate_ids: Array[StringName] = []
static var _order: Array[Resource] = []


## The schedule for [param npc_id], or null if nobody authored one.
static func schedule_for(npc_id: StringName) -> NpcSchedule:
	if npc_id.is_empty():
		return null
	ensure_loaded()
	return _by_id.get(npc_id) as NpcSchedule


static func has_schedule(npc_id: StringName) -> bool:
	return schedule_for(npc_id) != null


## Every schedule, sorted by id, so a caller that iterates does so stably.
static func all_schedules() -> Array[NpcSchedule]:
	ensure_loaded()
	var out: Array[NpcSchedule] = []
	for data: Variant in _order:
		if data is NpcSchedule:
			out.append(data)
	out.sort_custom(func(a: NpcSchedule, b: NpcSchedule) -> bool:
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
	_load_directory(SCHEDULE_DIRECTORY)
	RuntimeLog.info("ScheduleRegistry", "Loaded %d schedules" % _by_id.size())


static func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# Not an error, same reasoning as [NpcRegistry]: a checkout with no authored
		# days yet still has a working village that wanders.
		RuntimeLog.info("ScheduleRegistry", "no schedule directory at %s yet" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(SCHEDULE_EXTENSION):
			_load_resource("%s%s" % [path, entry])
		entry = dir.get_next()
	dir.list_dir_end()


static func _load_resource(path: String) -> void:
	var data := ResourceLoader.load(path) as NpcSchedule
	if data == null:
		RuntimeLog.warn("ScheduleRegistry", "%s is not an NpcSchedule" % path)
		return
	if not data.is_valid():
		# A schedule that fails `is_valid` is a content bug - most commonly two
		# blocks claiming the same clock, or a block naming no place - and loading
		# it anyway would make the failure appear later as a villager standing in
		# the wrong part of the valley with nothing in the log to explain it.
		RuntimeLog.warn("ScheduleRegistry", "%s is not a valid schedule: %s" % [
			path, data.describe(),
		])
		return
	if _by_id.has(data.npc_id):
		RuntimeLog.warn("ScheduleRegistry", "duplicate schedule for '%s' in %s, ignoring" % [
			data.npc_id, path,
		])
		if not _duplicate_ids.has(data.npc_id):
			_duplicate_ids.append(data.npc_id)
		return
	_by_id[data.npc_id] = data
	_order.append(data)
