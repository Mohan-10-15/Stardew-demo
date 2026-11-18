class_name AnimalService
extends Node
## The coop: feed an animal, wait a day or two, collect what it made.
## State is tiny and saved with the aggregate file.

const SERVICE_GROUP := &"animal_service"
const DIR := "res://resources/animals/"

var _states: Dictionary = {}


static func find(start: Node) -> AnimalService:
	if start == null:
		return null
	if start is AnimalService:
		return start as AnimalService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus != null:
		bus.day_started.connect(_on_day_started)
	_load_animals()


func _exit_tree() -> void:
	var bus := _bus()
	if bus != null and bus.day_started.is_connected(_on_day_started):
		bus.day_started.disconnect(_on_day_started)


func _load_animals() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("%s%s" % [DIR, entry]) as AnimalData
			if data != null and data.is_valid() and not _states.has(data.id):
				_states[data.id] = {
					"data": data, "fed_today": false,
					"days_left": data.days_to_product, "stored": 0,
				}
		entry = dir.get_next()
	dir.list_dir_end()


func all() -> Array[AnimalData]:
	var out: Array[AnimalData] = []
	for entry: Dictionary in _states.values():
		out.append(entry["data"] as AnimalData)
	return out


func feed(animal_id: StringName) -> bool:
	if not _states.has(animal_id):
		_fail_feed(animal_id, &"no_animal")
		return false
	var state: Dictionary = _states[animal_id]
	if bool(state["fed_today"]):
		_fail_feed(animal_id, &"already_fed_today")
		return false
	var bag := _bag()
	if bag == null:
		_fail_feed(animal_id, &"no_player_state")
		return false
	var data: AnimalData = state["data"]
	if int(bag.call("count", data.feed_item)) <= 0:
		_fail_feed(animal_id, &"no_feed")
		return false
	bag.call("remove", data.feed_item, 1)
	state["fed_today"] = true
	_states[animal_id] = state
	var bus := _bus()
	if bus != null:
		bus.animal_fed.emit(animal_id, data.feed_item)
	return true


func collect(animal_id: StringName) -> bool:
	if not _states.has(animal_id):
		_fail_collect(animal_id, &"no_animal")
		return false
	var state: Dictionary = _states[animal_id]
	var stored := int(state["stored"])
	if stored <= 0:
		_fail_collect(animal_id, &"nothing_ready")
		return false
	var bag := _bag()
	if bag == null:
		_fail_collect(animal_id, &"no_player_state")
		return false
	var data: AnimalData = state["data"]
	bag.call("add", data.product_item, stored)
	state["stored"] = 0
	_states[animal_id] = state
	var bus := _bus()
	if bus != null:
		bus.animal_product_collected.emit(animal_id, data.product_item, stored)
	return true


func _on_day_started(_day: int) -> void:
	for id: StringName in _states:
		var state: Dictionary = _states[id]
		var data: AnimalData = state["data"]
		if bool(state["fed_today"]):
			state["days_left"] = int(state["days_left"]) - 1
			state["fed_today"] = false
			if int(state["days_left"]) <= 0:
				state["stored"] = int(state["stored"]) + data.product_amount
				state["days_left"] = data.days_to_product
		_states[id] = state


func stored_of(animal_id: StringName) -> int:
	return int(_states.get(animal_id, {}).get("stored", 0))


func to_dict() -> Dictionary:
	var out := {}
	for id: StringName in _states:
		var state: Dictionary = _states[id]
		out[String(id)] = {
			"fed_today": state["fed_today"], "days_left": state["days_left"],
			"stored": state["stored"],
		}
	return out


func from_dict(data: Dictionary) -> void:
	if _states.is_empty():
		_load_animals()
	for key: Variant in data:
		var id := StringName(str(key))
		if not _states.has(id) or not (data[key] is Dictionary):
			continue
		var state: Dictionary = _states[id]
		var saved: Dictionary = data[key]
		state["fed_today"] = bool(saved.get("fed_today", false))
		state["days_left"] = maxi(int(saved.get("days_left", 1)), 1)
		state["stored"] = maxi(int(saved.get("stored", 0)), 0)
		_states[id] = state


func _bag() -> Object:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	return state.get("inventory") as Object if state != null else null


func _fail_feed(id: StringName, reason: StringName) -> void:
	var bus := _bus()
	if bus != null:
		bus.animal_feed_failed.emit(id, reason)


func _fail_collect(id: StringName, reason: StringName) -> void:
	var bus := _bus()
	if bus != null:
		bus.animal_collect_failed.emit(id, reason)


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
