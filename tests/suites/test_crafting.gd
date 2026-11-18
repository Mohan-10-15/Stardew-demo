extends TestSuite
## Crafting: recipes are data, success and failure are distinct, and the panel
## is driven by the real key bindings.

const SERVICE_SCRIPT := "res://scripts/crafting/crafting_service.gd"
const PANEL_SCENE := "res://scenes/ui/crafting_panel.tscn"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _reasons: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"recipes_are_authored_content",
		&"crafting_takes_inputs_and_pays_output",
		&"every_refusal_has_its_own_reason",
		&"the_panel_crafts_on_a_number_key",
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
		&"recipes_are_authored_content":
			return _t_content()
		&"crafting_takes_inputs_and_pays_output":
			return await _t_success()
		&"every_refusal_has_its_own_reason":
			return await _t_failures()
		&"the_panel_crafts_on_a_number_key":
			return await _t_panel()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"recipes_are_authored_content"
	var recipes := CraftingService.all_recipes()
	if recipes.size() < 4:
		return fail(c, "only %d recipes" % recipes.size())
	for recipe: Recipe in recipes:
		if not recipe.is_valid():
			return fail(c, "%s is invalid" % recipe.id)
		if not ItemRegistry.has_item(recipe.output_id):
			return fail(c, "%s has an unknown output" % recipe.id)
	return succeeded(c, "%d valid recipes" % recipes.size())


func _t_success() -> Dictionary:
	var c := &"crafting_takes_inputs_and_pays_output"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	var recipe := CraftingService.recipe_for(&"parsnip_seeds")
	var bag: Object = built["bag"]
	bag.call("add", &"parsnip", 1)
	var before_wood: int = int(bag.call("count", &"parsnip"))
	var before_out: int = int(bag.call("count", recipe.output_id))
	if not bool(built["service"].call("craft", recipe.id)):
		return fail(c, "the craft was refused")
	if int(bag.call("count", &"parsnip")) != before_wood - 1:
		return fail(c, "the ingredients are still in the bag")
	if int(bag.call("count", recipe.output_id)) != before_out + recipe.output_count:
		return fail(c, "the output did not arrive")
	if int(_events.get(&"craft_succeeded", 0)) != 1:
		return fail(c, "no success event")
	_stop_watch()
	return succeeded(c, "a parsnip became 2 seeds with one success event")


func _t_failures() -> Dictionary:
	var c := &"every_refusal_has_its_own_reason"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	_watch()
	built["service"].call("craft", &"no_such_recipe")
	built["service"].call("craft", &"plank")
	_stop_watch()
	if _reasons.size() != 2:
		return fail(c, "%d refusal reasons: %s" % [_reasons.size(), str(_reasons)])
	var unique: Array[StringName] = []
	for reason: StringName in _reasons:
		if not unique.has(reason):
			unique.append(reason)
	if unique.size() != 2 or not unique.has(&"no_recipe") \
			or not unique.has(&"missing_ingredients"):
		return fail(c, "the refusals are not distinct: %s" % str(unique))
	return succeeded(c, "unknown recipe and missing ingredients sound different")


func _t_panel() -> Dictionary:
	var c := &"the_panel_crafts_on_a_number_key"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the rig")
	var packed := load(PANEL_SCENE) as PackedScene
	if packed == null:
		return fail(c, "no crafting panel scene")
	var panel: CanvasLayer = packed.instantiate() as CanvasLayer
	_rig.add_child(panel)
	await _step(2)
	var open := _key(KEY_C, true)
	await _step(2)
	if not bool(panel.visible):
		return fail(c, "C did not open the panel: %s" % open)
	built["bag"].call("add", &"parsnip", 1)
	await _step(2)
	_watch()
	# Recipe order is id-sorted: parsnip_seeds is third, so key 3.
	await _key(KEY_3, true)
	await _step(3)
	if int(_events.get(&"craft_succeeded", 0)) != 1:
		return fail(c, "the number key did not craft")
	_stop_watch()
	return succeeded(c, "C opened the panel and key 3 crafted seeds")


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
	service.name = "CraftingService"
	_rig.add_child(service)
	await _step(2)
	return {"service": service, "bag": state.get("inventory"), "state": state}


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"craft_succeeded": 0, &"craft_failed": 0}
	bus.connect(&"craft_succeeded", _on_success)
	bus.connect(&"craft_failed", _on_failure)
	_reasons = []


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	if bus.is_connected(&"craft_succeeded", _on_success):
		bus.disconnect(&"craft_succeeded", _on_success)
	if bus.is_connected(&"craft_failed", _on_failure):
		bus.disconnect(&"craft_failed", _on_failure)


func _on_success(_id: StringName, _out: StringName, _count: int) -> void:
	_events[&"craft_succeeded"] = int(_events.get(&"craft_succeeded", 0)) + 1


func _on_failure(_id: StringName, reason: StringName) -> void:
	_events[&"craft_failed"] = int(_events.get(&"craft_failed", 0)) + 1
	_reasons.append(reason)


func _key(code: int, _unused: bool = true) -> String:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	return "pressed"


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "CraftingTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
