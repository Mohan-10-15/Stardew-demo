extends TestSuite
## M11: buildings are bought, placed, usable and upgradeable. The effects are
## real — a coop boosts the animal products and a well waters the plot — and
## they are queried through the BuildingService manager, not hard-coded.

const SERVICE_SCRIPT := "res://scripts/buildings/building_service.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const ANIMAL_SCRIPT := "res://scripts/animals/animal_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _reasons: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"buildings_are_authored", &"buying_and_placing_a_building",
		&"an_upgrade_doubles_the_effect", &"a_coop_boosts_animal_products",
		&"building_refusals_are_distinct", &"building_state_survives_a_save",
	]


func setup() -> void:
	_rig = null
	_events = {}
	_reasons = []


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"buildings_are_authored":
			return _t_content()
		&"buying_and_placing_a_building":
			return await _t_buy()
		&"an_upgrade_doubles_the_effect":
			return await _t_upgrade()
		&"a_coop_boosts_animal_products":
			return await _t_coop()
		&"building_refusals_are_distinct":
			return await _t_refusals()
		&"building_state_survives_a_save":
			return await _t_save()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"buildings_are_authored"
	var definitions := BuildingService.all_buildings()
	if definitions.size() < 2:
		return fail(c, "only %d buildings" % definitions.size())
	var kinds: Array[StringName] = []
	for data: BuildingData in definitions:
		if not data.is_valid():
			return fail(c, "%s is invalid" % data.id)
		if not kinds.has(data.effect_kind):
			kinds.append(data.effect_kind)
	if not kinds.has(&"product") or not kinds.has(&"water"):
		return fail(c, "expected a product and a water building, got %s" % str(kinds))
	return succeeded(c, "%d buildings with product and water effects" % definitions.size())


func _t_buy() -> Dictionary:
	var c := &"buying_and_placing_a_building"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	var wallet: Object = built["wallet"]
	wallet.call("set_gold", 5000)
	var before: int = int(wallet.get("gold"))
	var slot := int(built["service"].call("buy_and_place", &"hen_coop"))
	if slot < 0:
		return fail(c, "the coop could not be bought")
	if int(wallet.get("gold")) >= before:
		return fail(c, "buying did not spend gold")
	if int(built["service"].call("effect", &"product")) != 1:
		return fail(c, "the placed coop has no product effect")
	if int(_events.get(&"building_placed", 0)) != 1:
		return fail(c, "no distinct placement event")
	_stop_watch()
	return succeeded(c, "a coop was bought, placed and started producing")


func _t_upgrade() -> Dictionary:
	var c := &"an_upgrade_doubles_the_effect"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	var wallet: Object = built["wallet"]
	wallet.call("set_gold", 5000)
	var slot := int(built["service"].call("buy_and_place", &"hen_coop"))
	var base := int(built["service"].call("effect", &"product"))
	if not bool(built["service"].call("upgrade", slot)):
		return fail(c, "the coop could not be upgraded")
	if int(built["service"].call("effect", &"product")) != base * 2:
		return fail(c, "the upgrade did not double the effect")
	if int(_events.get(&"building_upgraded", 0)) != 1:
		return fail(c, "no distinct upgrade event")
	# A second upgrade must be refused, not silently charged.
	if bool(built["service"].call("upgrade", slot)):
		return fail(c, "a third-level upgrade was wrongly allowed")
	_stop_watch()
	return succeeded(c, "the coop's product effect doubled with its level")


func _t_coop() -> Dictionary:
	var c := &"a_coop_boosts_animal_products"
	var built := await _build(true)
	if built.is_empty():
		return fail(c, "could not build the rig")
	var animals: Node = built["animals"]
	var bag: Object = built["bag"]
	# Real loop each round: one feed, one fed day, one stored egg, then collect.
	var plain := _one_egg(animals, bag)
	var wallet: Object = built["wallet"]
	wallet.call("set_gold", 5000)
	var slot := int(built["service"].call("buy_and_place", &"hen_coop"))
	var with_coop := _one_egg(animals, bag)
	built["service"].call("upgrade", slot)
	var upgraded := _one_egg(animals, bag)
	if plain != 1 or with_coop != 2 or upgraded != 3:
		return fail(c, "products were %d/%d/%d, expected 1/2/3" % [
			plain, with_coop, upgraded,
		])
	return succeeded(c, "a coop doubled the eggs, its upgrade tripled them")


func _one_egg(animals: Node, bag: Object) -> int:
	bag.call("add", &"spring_onion", 1)
	animals.call("feed", &"hen")
	animals.call("_on_day_started", 2)
	var before: int = int(bag.call("count", &"egg"))
	animals.call("collect", &"hen")
	return int(bag.call("count", &"egg")) - before


func _t_refusals() -> Dictionary:
	var c := &"building_refusals_are_distinct"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	built["wallet"].call("set_gold", 0)
	built["service"].call("buy_and_place", &"hen_coop")      # poor
	built["service"].call("upgrade", 0)                      # no building
	built["service"].call("buy_and_place", &"not_a_building")  # unknown
	_stop_watch()
	var unique: Array[StringName] = []
	for reason: StringName in _reasons:
		if not unique.has(reason):
			unique.append(reason)
	if not unique.has(&"poor") or not unique.has(&"no_building"):
		return fail(c, "refusals are not distinct: %s" % str(unique))
	return succeeded(c, "poor, missing and unknown buildings sound different")


func _t_save() -> Dictionary:
	var c := &"building_state_survives_a_save"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	built["wallet"].call("set_gold", 5000)
	var slot := int(built["service"].call("buy_and_place", &"farm_well"))
	built["service"].call("upgrade", slot)
	var data: Dictionary = built["service"].call("to_dict")
	var fresh: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	_rig.add_child(fresh)
	fresh.call("from_dict", data)
	if int(fresh.call("effect", &"water")) != 4:
		return fail(c, "the upgraded well did not round-trip")
	return succeeded(c, "a placed, upgraded well round-tripped")


func _build(with_animals: bool = false) -> Dictionary:
	_stop_watch()
	_reset_rig()
	var service_script := load(SERVICE_SCRIPT) as GDScript
	var state_script := load(STATE_SCRIPT) as GDScript
	_ensure_rig()
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var service: Node = service_script.new()
	service.name = "BuildingService"
	_rig.add_child(service)
	var out := {
		"service": service, "bag": state.get("inventory"),
		"wallet": state.get("wallet"), "animals": null,
	}
	if with_animals:
		var animals: Node = (load(ANIMAL_SCRIPT) as GDScript).new()
		animals.name = "AnimalService"
		_rig.add_child(animals)
		out["animals"] = animals
	await _step(3)
	return out


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"building_placed": 0, &"building_upgraded": 0, &"building_failed": 0}
	bus.connect(&"building_placed", _placed)
	bus.connect(&"building_upgraded", _upgraded)
	bus.connect(&"building_failed", _failed)
	_reasons = []


func _placed(_id: StringName, _slot: int) -> void:
	_events[&"building_placed"] = int(_events.get(&"building_placed", 0)) + 1


func _upgraded(_id: StringName, _slot: int, _level: int) -> void:
	_events[&"building_upgraded"] = int(_events.get(&"building_upgraded", 0)) + 1


func _failed(_id: StringName, reason: StringName) -> void:
	_events[&"building_failed"] = int(_events.get(&"building_failed", 0)) + 1
	_reasons.append(reason)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	if bus.is_connected(&"building_placed", _placed):
		bus.disconnect(&"building_placed", _placed)
	if bus.is_connected(&"building_upgraded", _upgraded):
		bus.disconnect(&"building_upgraded", _upgraded)
	if bus.is_connected(&"building_failed", _failed):
		bus.disconnect(&"building_failed", _failed)


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "BuildingTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	for child: Node in root().get_children():
		if child.name == "BuildingVisuals":
			child.free()
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
