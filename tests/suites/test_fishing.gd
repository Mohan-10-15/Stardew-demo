extends TestSuite
## Fishing: the moment matters, and a landed fish is four distinct events away
## from an escaped one.

const SERVICE_SCRIPT := "res://scripts/fishing/fishing_service.gd"
const TIME_SCRIPT := "res://scripts/time/time_service.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const DIR := "res://resources/fishing/fish/"

var _rig: Node3D = null
var _events: Dictionary = {}
var _watchers: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"fish_are_authored_as_content",
		&"a_cast_bites_and_lands",
		&"a_missed_bite_escapes_distinctly",
		&"a_cast_survives_a_save",
	]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"fish_are_authored_as_content":
			return _t_content()
		&"a_cast_bites_and_lands":
			return await _t_land()
		&"a_missed_bite_escapes_distinctly":
			return await _t_escape()
		&"a_cast_survives_a_save":
			return await _t_save()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"fish_are_authored_as_content"
	var dir := DirAccess.open(DIR)
	if dir == null:
		return fail(c, "no fish directory")
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("%s%s" % [DIR, entry]) as FishData
			if data == null or not data.is_valid():
				return fail(c, "%s is invalid" % entry)
			if not ItemRegistry.has_item(data.item_id):
				return fail(c, "%s has no item definition" % data.id)
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	if count < 4:
		return fail(c, "only %d fish authored" % count)
	return succeeded(c, "%d fish with real item drops" % count)


func _t_land() -> Dictionary:
	var c := &"a_cast_bites_and_lands"
	await _build()
	var service: Node = _rig.get_node(^"Fishing")
	_watch()
	if not bool(service.call("cast")):
		return fail(c, "the cast was refused")
	service.set("wait_left", 0.01)
	await _step(3)
	if int(_events.get(&"fish_bite", 0)) != 1:
		return fail(c, "no bite after the wait")
	var bag: Object = _rig.get_node(^"PlayerState").get("inventory")
	var caught: FishData = service.get("current_fish") as FishData
	var before: int = int(bag.call("count", caught.item_id))
	if not bool(service.call("land")):
		return fail(c, "the landing was refused")
	var after: int = int(bag.call("count", caught.item_id))
	if int(service.get("state")) != 0:
		return fail(c, "the service did not return to idle")
	if after != before + 1:
		return fail(c, "the fish did not reach the bag (%d -> %d)" % [before, after])
	if int(_events.get(&"fish_caught", 0)) != 1:
		return fail(c, "no distinct catch event")
	_stop_watch()
	return succeeded(c, "cast, bite and catch are three distinct outcomes")


func _t_escape() -> Dictionary:
	var c := &"a_missed_bite_escapes_distinctly"
	await _build()
	var service: Node = _rig.get_node(^"Fishing")
	_watch()
	service.call("cast")
	service.set("wait_left", 0.01)
	await _step(3)
	service.set("bite_left", 0.01)
	await _step(3)
	if int(_events.get(&"fish_escaped", 0)) != 1:
		return fail(c, "a missed bite did not escape: %s state=%s bite=%s" % [
			str(_events), str(service.get("state")), str(service.get("bite_left")),
		])
	if int(_events.get(&"fish_caught", 0)) != 0:
		return fail(c, "an escape looked like a catch")
	_stop_watch()
	return succeeded(c, "an escape is distinct from a catch")


func _t_save() -> Dictionary:
	var c := &"a_cast_survives_a_save"
	await _build()
	var service: Node = _rig.get_node(^"Fishing")
	service.call("cast")
	var data: Dictionary = service.call("to_dict")
	var fresh: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	_rig.add_child(fresh)
	fresh.call("from_dict", data)
	if int(fresh.get("state")) != int(service.get("state")):
		return fail(c, "the fishing state did not round-trip")
	_stop_watch()
	return succeeded(c, "an in-flight cast round-tripped")


func _build() -> void:
	_stop_watch()
	_reset_rig()
	var service_script := load(SERVICE_SCRIPT) as GDScript
	var time_script := load(TIME_SCRIPT) as GDScript
	var state_script := load(STATE_SCRIPT) as GDScript
	_ensure_rig()
	var clock: Node = time_script.new()
	clock.name = "TimeService"
	clock.running = false
	clock.time.season = 0
	clock.time.weather = 0
	clock.time.hour = 10
	_rig.add_child(clock)
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var service: Node = service_script.new()
	service.name = "Fishing"
	_rig.add_child(service)
	await _step(2)


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"fishing_cast": 0, &"fish_bite": 0, &"fish_caught": 0, &"fish_escaped": 0}
	for key: StringName in [&"fishing_cast", &"fish_bite", &"fish_caught", &"fish_escaped"]:
		var callable: Callable = _zero(key) if key == &"fishing_cast" \
			else _one(key) if key == &"fish_bite" else _two(key)
		_watchers[key] = callable
		bus.connect(key, callable)


func _zero(key: StringName) -> Callable:
	return func() -> void: _events[key] = int(_events.get(key, 0)) + 1


func _one(key: StringName) -> Callable:
	return func(_id: StringName) -> void: _events[key] = int(_events.get(key, 0)) + 1


func _two(key: StringName) -> Callable:
	return func(_id: StringName, _item: StringName) -> void: _events[key] = int(_events.get(key, 0)) + 1


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	for key: StringName in _watchers:
		if bus.is_connected(key, _watchers[key]):
			bus.disconnect(key, _watchers[key])
	_watchers.clear()


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "FishingTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
