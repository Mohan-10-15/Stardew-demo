extends TestSuite
## W2.3: the plinth and area gates exist in the real world, gates are
## player-only, and a tier unlock opens the right gate.

const MAIN := "res://scenes/core/main.tscn"

var _main: Node = null
var _opened: Array[StringName] = []


func is_async() -> bool:
	return true


func setup() -> void:
	_main = null
	_opened = []


func teardown() -> void:
	var bus := autoload(&"EventBus")
	if bus.area_gate_opened.is_connected(_on_gate_opened):
		bus.area_gate_opened.disconnect(_on_gate_opened)
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"the_world_has_a_plinth_and_gates":
			return await _t_present(case)
		&"a_gate_opens_on_its_tier_unlock":
			return await _t_open(case)
		&"gates_do_not_block_villagers":
			return _t_masks(case)
		&"the_plinth_reports_its_ember_count":
			return await _t_plinth(case)
	return fail(case, "no case implementation for %s" % case)


func get_cases() -> Array[StringName]:
	return [&"the_world_has_a_plinth_and_gates", &"a_gate_opens_on_its_tier_unlock",
		&"gates_do_not_block_villagers", &"the_plinth_reports_its_ember_count"]


func _boot() -> void:
	if _main != null and is_instance_valid(_main):
		return
	var packed := load(MAIN) as PackedScene
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	root().add_child(_main)
	for _i: int in range(8):
		await tree.process_frame


func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _t_present(c: StringName) -> Dictionary:
	await _boot()
	if _find_named(_main, "HeartstonePlinth") == null:
		return fail(c, "no plinth in the world")
	var gates := _count_gates(_main)
	if gates < 3:
		return fail(c, "only %d gates" % gates)
	return succeeded(c, "plinth + %d gates present" % gates)


func _count_gates(node: Node) -> int:
	var count := 0
	for child: Node in node.get_children():
		if String(child.name).begins_with("Gate_"):
			count += 1
		count += _count_gates(child)
	return count


func _t_open(c: StringName) -> Dictionary:
	await _boot()
	var gate := _find_named(_main, "Gate_orchard_path") as StaticBody3D
	if gate == null:
		return fail(c, "no orchard gate")
	var component := gate.get_node_or_null(^"Interactable")
	if component == null or bool(component.call("is_open")):
		return fail(c, "gate starts open")
	var bus := autoload(&"EventBus")
	if not bus.area_gate_opened.is_connected(_on_gate_opened):
		bus.area_gate_opened.connect(_on_gate_opened)
	bus.collection_tier_reached.emit(&"fields", 0, &"orchard_path", &"fields")
	await tree.process_frame
	if not bool(component.call("is_open")):
		return fail(c, "the orchard gate stayed closed")
	if not _opened.has(&"orchard_path"):
		return fail(c, "no distinct gate-opened event")
	return succeeded(c, "Fields tier 1 opened the orchard gate")


func _on_gate_opened(gate_id: StringName) -> void:
	_opened.append(gate_id)


func _t_masks(c: StringName) -> Dictionary:
	if (PhysicsLayers.PLAYER_MASK & PhysicsLayers.GATE) == 0:
		return fail(c, "the player cannot collide with gates")
	if (PhysicsLayers.NPC & PhysicsLayers.GATE) != 0:
		return fail(c, "villagers would be blocked by gates")
	return succeeded(c, "gates are player-only")


func _t_plinth(c: StringName) -> Dictionary:
	await _boot()
	var plinth := _find_named(_main, "HeartstonePlinth")
	if plinth == null:
		return fail(c, "no plinth")
	var component := plinth.get_node_or_null(^"Interactable")
	if component == null:
		return fail(c, "plinth has no Interactable")
	var seen: Array[int] = []
	var callback := func(embers: int, needed: int) -> void:
		seen.append(embers)
		seen.append(needed)
	var bus := autoload(&"EventBus")
	bus.plinth_inspected.connect(callback)
	component.call("interact", null)
	await tree.process_frame
	bus.plinth_inspected.disconnect(callback)
	if seen.size() != 2 or seen[1] != 6:
		return fail(c, "plinth did not report its count: %s" % str(seen))
	return succeeded(c, "plinth reported %d/%d Embers" % [seen[0], seen[1]])
