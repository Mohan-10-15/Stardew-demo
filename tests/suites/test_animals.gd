extends TestSuite
## Animals: feed, wait a day, collect. Refusals are distinct from the reward.

const SERVICE_SCRIPT := "res://scripts/animals/animal_service.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _reasons: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"animals_are_authored_with_real_items",
		&"feeding_producing_and_collecting",
		&"refusals_are_distinct",
		&"animal_state_survives_a_save",
	]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"animals_are_authored_with_real_items":
			return _t_content()
		&"feeding_producing_and_collecting":
			return await _t_cycle()
		&"refusals_are_distinct":
			return await _t_refusals()
		&"animal_state_survives_a_save":
			return await _t_save()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"animals_are_authored_with_real_items"
	var dir := DirAccess.open("res://resources/animals/")
	if dir == null:
		return fail(c, "no animal directory")
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("res://resources/animals/%s" % entry) as AnimalData
			if data == null or not data.is_valid():
				return fail(c, "%s is invalid" % entry)
			if not ItemRegistry.has_item(data.feed_item):
				return fail(c, "%s wants an unknown feed" % data.id)
			if not ItemRegistry.has_item(data.product_item):
				return fail(c, "%s gives an unknown product" % data.id)
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	if count < 2:
		return fail(c, "only %d animals" % count)
	return succeeded(c, "%d animals with real feed and products" % count)


func _t_cycle() -> Dictionary:
	var c := &"feeding_producing_and_collecting"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	built["bag"].call("add", &"spring_onion", 1)
	if not bool(built["service"].call("feed", &"hen")):
		return fail(c, "the hen refused feed")
	built["service"].call("_on_day_started", 2)
	if int(built["service"].call("stored_of", &"hen")) != 1:
		return fail(c, "no egg after a fed day")
	var before: int = int(built["bag"].call("count", &"egg"))
	if not bool(built["service"].call("collect", &"hen")):
		return fail(c, "the egg could not be collected")
	if int(built["bag"].call("count", &"egg")) != before + 1:
		return fail(c, "the egg did not reach the bag")
	if int(_events.get(&"animal_fed", 0)) != 1 \
			or int(_events.get(&"animal_product_collected", 0)) != 1:
		return fail(c, "feed and collect are not distinct events")
	_stop_watch()
	return succeeded(c, "one corn, one day, one egg, two distinct events")


func _t_refusals() -> Dictionary:
	var c := &"refusals_are_distinct"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	built["service"].call("feed", &"hen")       # no feed
	built["service"].call("collect", &"hen")    # nothing ready
	var reasons: Array[StringName] = []
	for reason: StringName in _reasons:
		if not reasons.has(reason):
			reasons.append(reason)
	_stop_watch()
	if reasons.size() != 2 or not reasons.has(&"no_feed") \
			or not reasons.has(&"nothing_ready"):
		return fail(c, "refusals are not distinct: %s" % str(reasons))
	return succeeded(c, "no feed and nothing to collect sound different")


func _t_save() -> Dictionary:
	var c := &"animal_state_survives_a_save"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	built["bag"].call("add", &"spring_onion", 1)
	built["service"].call("feed", &"hen")
	var data: Dictionary = built["service"].call("to_dict")
	var fresh: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	_rig.add_child(fresh)
	fresh.call("from_dict", data)
	_stop_watch()
	return succeeded(c, "fed state round-tripped")


func _build() -> Dictionary:
	_stop_watch()
	_reset_rig()
	var service_script := load(SERVICE_SCRIPT) as GDScript
	var state_script := load(STATE_SCRIPT) as GDScript
	_ensure_rig()
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var service: Node = service_script.new()
	service.name = "AnimalService"
	_rig.add_child(service)
	await _step(2)
	return {"service": service, "bag": state.get("inventory"), "state": state}


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"animal_fed": 0, &"animal_product_collected": 0,
		&"animal_feed_failed": 0, &"animal_collect_failed": 0}
	bus.connect(&"animal_fed", _one(&"animal_fed"))
	bus.connect(&"animal_product_collected", _two(&"animal_product_collected"))
	bus.connect(&"animal_feed_failed", _one(&"animal_feed_failed"))
	bus.connect(&"animal_collect_failed", _one(&"animal_collect_failed"))
	_reasons = []


func _one(key: StringName) -> Callable:
	return func(_id: StringName, _a: StringName = &"") -> void:
		_events[key] = int(_events.get(key, 0)) + 1
		if key == &"animal_feed_failed" or key == &"animal_collect_failed":
			_reasons.append(_a)


func _two(key: StringName) -> Callable:
	return func(_id: StringName, _item: StringName, _amount: int) -> void:
		_events[key] = int(_events.get(key, 0)) + 1


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	for key: StringName in [&"animal_fed", &"animal_feed_failed", &"animal_collect_failed"]:
		var callable := _one(key)
		if bus.is_connected(key, callable):
			bus.disconnect(key, callable)
	var c2 := _two(&"animal_product_collected")
	if bus.is_connected(&"animal_product_collected", c2):
		bus.disconnect(&"animal_product_collected", c2)


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "AnimalTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
