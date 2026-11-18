extends TestSuite
## Cooking at the stove: data dishes, distinct success and refusal.

const SERVICE_SCRIPT := "res://scripts/cooking/cooking_service.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _reasons: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [&"dishes_are_authored", &"cooking_a_dish", &"cooking_refusals_are_distinct"]


func setup() -> void:
	_rig = null
	_events = {}
	_reasons = []


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"dishes_are_authored":
			return _t_content()
		&"cooking_a_dish":
			return await _t_cook()
		&"cooking_refusals_are_distinct":
			return await _t_refusals()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"dishes_are_authored"
	var recipes := CookingService.all_recipes()
	if recipes.size() < 3:
		return fail(c, "only %d dishes" % recipes.size())
	for recipe: CookingRecipe in recipes:
		if not recipe.is_valid() or not ItemRegistry.has_item(recipe.output_id):
			return fail(c, "%s is invalid" % recipe.id)
	return succeeded(c, "%d valid dishes" % recipes.size())


func _t_cook() -> Dictionary:
	var c := &"cooking_a_dish"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	built["bag"].call("add", &"wild_berry", 2)
	var before: int = int(built["bag"].call("count", &"fish_smilte"))
	if not bool(built["service"].call("cook", &"berry_jam")):
		return fail(c, "the dish was refused")
	if int(built["bag"].call("count", &"fish_smilte")) != before + 1:
		return fail(c, "the dish did not reach the bag")
	if int(_events.get(&"dish_cooked", 0)) != 1:
		return fail(c, "no distinct cook event")
	_stop_watch()
	return succeeded(c, "two berries became a dish")


func _t_refusals() -> Dictionary:
	var c := &"cooking_refusals_are_distinct"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	built["service"].call("cook", &"no_such_dish")
	built["service"].call("cook", &"berry_jam")
	_stop_watch()
	var unique: Array[StringName] = []
	for reason: StringName in _reasons:
		if not unique.has(reason):
			unique.append(reason)
	if not unique.has(&"no_recipe") or not unique.has(&"missing_ingredients"):
		return fail(c, "refusals are not distinct: %s" % str(unique))
	return succeeded(c, "unknown dish and missing ingredients sound different")


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
	service.name = "CookingService"
	_rig.add_child(service)
	await _step(2)
	return {"service": service, "bag": state.get("inventory")}


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"dish_cooked": 0, &"cook_failed": 0}
	bus.connect(&"dish_cooked", _cooked)
	bus.connect(&"cook_failed", _failed)
	_reasons = []


func _cooked(_id: StringName, _out: StringName) -> void:
	_events[&"dish_cooked"] = int(_events.get(&"dish_cooked", 0)) + 1


func _failed(_id: StringName, reason: StringName) -> void:
	_events[&"cook_failed"] = int(_events.get(&"cook_failed", 0)) + 1
	_reasons.append(reason)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	if bus.is_connected(&"dish_cooked", _cooked):
		bus.disconnect(&"dish_cooked", _cooked)
	if bus.is_connected(&"cook_failed", _failed):
		bus.disconnect(&"cook_failed", _failed)


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "CookingTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
