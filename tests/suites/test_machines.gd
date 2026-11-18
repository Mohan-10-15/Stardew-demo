extends TestSuite
## Machines: place on a pad, load an input, wait a day, collect the output.

const SERVICE_SCRIPT := "res://scripts/machines/machine_service.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _reasons: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [&"machines_are_authored", &"a_machine_works_the_full_cycle",
		&"machine_refusals_are_distinct", &"machine_state_survives_a_save"]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"machines_are_authored":
			return _t_content()
		&"a_machine_works_the_full_cycle":
			return await _t_cycle()
		&"machine_refusals_are_distinct":
			return await _t_refusals()
		&"machine_state_survives_a_save":
			return await _t_save()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"machines_are_authored"
	var machines := MachineService.all_machines()
	if machines.size() < 2:
		return fail(c, "only %d machines" % machines.size())
	for data: MachineData in machines:
		if not data.is_valid():
			return fail(c, "%s invalid" % data.id)
		if not ItemRegistry.has_item(data.input_id) or not ItemRegistry.has_item(data.output_id):
			return fail(c, "%s names an unknown item" % data.id)
	return succeeded(c, "%d valid machines" % machines.size())


func _t_cycle() -> Dictionary:
	var c := &"a_machine_works_the_full_cycle"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	var slot := int(built["service"].call("place", &"furnace"))
	if slot < 0:
		return fail(c, "the furnace could not be placed")
	built["bag"].call("add", &"copper_ore", 1)
	if not bool(built["service"].call("load_from_bag", slot)):
		return fail(c, "the furnace refused its input")
	autoload(&"EventBus").emit_signal(&"day_started", 2)
	autoload(&"EventBus").emit_signal(&"day_started", 3)
	var before: int = int(built["bag"].call("count", &"iron_ore"))
	if not bool(built["service"].call("collect", slot)):
		return fail(c, "the output could not be collected")
	if int(built["bag"].call("count", &"iron_ore")) != before + 1:
		return fail(c, "the iron did not reach the bag")
	if int(_events.get(&"machine_placed", 0)) != 1 \
			or int(_events.get(&"machine_loaded", 0)) != 1 \
			or int(_events.get(&"machine_collected", 0)) != 1:
		return fail(c, "place, load and collect are not distinct events")
	_stop_watch()
	return succeeded(c, "placed, loaded, waited two days, collected iron")


func _t_refusals() -> Dictionary:
	var c := &"machine_refusals_are_distinct"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	var slot := int(built["service"].call("place", &"furnace"))
	built["service"].call("load_input", slot, &"wild_berry")  # wrong input
	built["service"].call("collect", slot)                    # not ready
	_stop_watch()
	var reasons: Array[StringName] = []
	for reason: StringName in _reasons:
		if not reasons.has(reason):
			reasons.append(reason)
	if not reasons.has(&"wrong_input") or not reasons.has(&"not_ready"):
		return fail(c, "refusals are not distinct: %s" % str(reasons))
	return succeeded(c, "wrong input and nothing ready sound different")


func _t_save() -> Dictionary:
	var c := &"machine_state_survives_a_save"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	built["service"].call("place", &"furnace")
	var data: Dictionary = built["service"].call("to_dict")
	var fresh: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	_rig.add_child(fresh)
	fresh.call("from_dict", data)
	_stop_watch()
	return succeeded(c, "a placed machine round-tripped")


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
	service.name = "MachineService"
	_rig.add_child(service)
	await _step(2)
	return {"service": service, "bag": state.get("inventory")}


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"machine_placed": 0, &"machine_loaded": 0, &"machine_collected": 0}
	bus.connect(&"machine_placed", _noargs(&"machine_placed"))
	bus.connect(&"machine_loaded", _load(&"machine_loaded"))
	bus.connect(&"machine_collected", _collect(&"machine_collected"))
	bus.connect(&"machine_load_failed", _fail(&"machine_load_failed"))
	bus.connect(&"machine_collect_failed", _fail(&"machine_collect_failed"))
	_reasons = []


func _noargs(key: StringName) -> Callable:
	return func(_id: StringName, _slot: int = -1) -> void:
		_events[key] = int(_events.get(key, 0)) + 1


func _load(key: StringName) -> Callable:
	return func(_id: StringName, _slot: int, _item: StringName) -> void:
		_events[key] = int(_events.get(key, 0)) + 1


func _collect(key: StringName) -> Callable:
	return func(_id: StringName, _slot: int, _item: StringName, _amount: int) -> void:
		_events[key] = int(_events.get(key, 0)) + 1


func _fail(key: StringName) -> Callable:
	return func(_id: StringName, _slot: int, reason: StringName) -> void:
		_reasons.append(reason)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	for key: StringName in [&"machine_placed", &"machine_loaded", &"machine_collected",
			&"machine_load_failed", &"machine_collect_failed"]:
		var callable: Callable = _noargs(key) if key == &"machine_placed" \
			else _load(key) if key == &"machine_loaded" \
			else _collect(key) if key == &"machine_collected" else _fail(key)
		if bus.is_connected(key, callable):
			bus.disconnect(key, callable)


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "MachineTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	for child: Node in root().get_children():
		if child.name == "MachineVisuals":
			child.free()
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
