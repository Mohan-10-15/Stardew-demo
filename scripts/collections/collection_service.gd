class_name CollectionService
extends Node
## Driven by the EventBus signals the game already publishes. It never asks a
## gameplay system anything and never grants an item directly: reaching a tier
## emits an event with the unlock id, and the world reacts to that.

const DIR := "res://resources/collections/"
const SERVICE_GROUP := &"collection_service"

# All collection outcomes go through the one global hub (D3), never through
# service-local signals that every listener would have to know about.

var collections: Array[CollectionData] = []
var discovered: Dictionary = {}


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	_load()
	_connect_events()


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	for signal_name: StringName in _signal_names():
		if bus.has_signal(signal_name) and bus.is_connected(signal_name, _on_event):
			bus.disconnect(signal_name, _on_event)


func _signal_names() -> Array[StringName]:
	return [
		&"crop_harvested", &"fish_caught", &"dish_cooked", &"craft_succeeded",
		&"resource_collected", &"npc_friendship_changed", &"item_added",
	]


func _connect_events() -> void:
	var bus := _bus()
	if bus == null:
		return
	for signal_name: StringName in _signal_names():
		if bus.has_signal(signal_name) and not bus.is_connected(signal_name, _on_event):
			bus.connect(signal_name, _on_event)


func _load() -> void:
	collections.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for entry: String in dir.get_files():
		if ResourceFiles.is_resource(entry):
			var data := ResourceLoader.load(ResourceFiles.path_for(DIR, entry)) as CollectionData
			if data != null and data.is_valid():
				collections.append(data)
	collections.sort_custom(func(a: CollectionData, b: CollectionData) -> bool:
		return String(a.id) < String(b.id))
	for data: CollectionData in collections:
		if not discovered.has(data.id):
			discovered[data.id] = {}


func definition(id: StringName) -> CollectionData:
	for data: CollectionData in collections:
		if data.id == id:
			return data
	return null


func _on_event(_a = null, _b = null, _c = null) -> void:
	# The events carry different argument shapes. The item id is always the
	# first argument except friendship (npc id, then hearts), so both are tried.
	var value := ""
	if _a is StringName or _a is String:
		value = String(_a)
	if value.is_empty():
		return
	record(StringName(value))


## Records one entry id. Returns how many collections gained an entry.
func record(entry_id: StringName) -> int:
	var gained := 0
	for data: CollectionData in collections:
		if not data.entries.has(entry_id):
			continue
		var set: Dictionary = discovered[data.id]
		if set.has(entry_id):
			continue
		set[entry_id] = true
		discovered[data.id] = set
		gained += 1
		var count := set.size()
		var total := data.entries.size()
		_bus().collection_progressed.emit(data.id, count, total)
		_check_tiers(data, count, total)
	if gained == 0:
		_bus().collection_failed.emit(entry_id, &"no_collection")
	return gained


func _check_tiers(data: CollectionData, count: int, total: int) -> void:
	var fraction := float(count) / float(total)
	for i: int in range(data.tiers.size()):
		var tier: CollectionTier = data.tiers[i]
		if fraction + 0.0001 < tier.threshold:
			continue
		var key := "tier_%d" % i
		var set: Dictionary = discovered[data.id]
		if set.has(key):
			continue
		set[key] = true
		discovered[data.id] = set
		_bus().collection_tier_reached.emit(data.id, i, tier.unlock, tier.ember)


func progress(id: StringName) -> float:
	var data := definition(id)
	if data == null:
		return 0.0
	var set: Dictionary = discovered.get(id, {})
	var count := 0
	for entry: StringName in data.entries:
		if set.has(entry):
			count += 1
	return float(count) / float(data.entries.size())


func discovered_count(id: StringName) -> int:
	var set: Dictionary = discovered.get(id, {})
	var count := 0
	for key: Variant in set:
		if not String(key).begins_with("tier_"):
			count += 1
	return count


func tier_reached(id: StringName, tier: int) -> bool:
	var set: Dictionary = discovered.get(id, {})
	return bool(set.get("tier_%d" % tier, false))


func embers() -> Array[StringName]:
	var out: Array[StringName] = []
	for data: CollectionData in collections:
		if tier_reached(data.id, data.tiers.size() - 1):
			out.append(data.ember)
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id: StringName in discovered:
		out[String(id)] = (discovered[id] as Dictionary).duplicate()
	return out


func from_dict(data: Dictionary) -> void:
	for key: Variant in data:
		var id := StringName(String(key))
		if data[key] is Dictionary:
			discovered[id] = (data[key] as Dictionary).duplicate()


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
