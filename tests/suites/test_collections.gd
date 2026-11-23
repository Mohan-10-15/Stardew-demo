extends TestSuite
## W2.2 / W2.3: six data-driven collections, tier unlocks that emit Embers,
## and pure Heartstone state that only permits the Mending at six.

const SERVICE_SCRIPT := "res://scripts/collections/collection_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _embers: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"six_collections_are_authored", &"recording_progresses_the_collection",
		&"tiers_unlock_embers_at_their_thresholds", &"heartstone_needs_all_six_embers",
		&"collection_progress_survives_a_save",
	]


func setup() -> void:
	_rig = null
	_events = {}
	_embers = []


func teardown() -> void:
	var bus := autoload(&"EventBus")
	if bus.is_connected(&"collection_progressed", _on_progress):
		bus.disconnect(&"collection_progressed", _on_progress)
	if bus.is_connected(&"collection_tier_reached", _on_tier):
		bus.disconnect(&"collection_tier_reached", _on_tier)
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"six_collections_are_authored":
			return _t_content(case)
		&"recording_progresses_the_collection":
			return await _t_progress(case)
		&"tiers_unlock_embers_at_their_thresholds":
			return await _t_tiers(case)
		&"heartstone_needs_all_six_embers":
			return _t_heartstone(case)
		&"collection_progress_survives_a_save":
			return await _t_save(case)
	return fail(case, "no case implementation for %s" % case)


func _make_service() -> Node:
	if _rig == null:
		_rig = Node3D.new()
		_rig.name = "CollectionTestRig"
		root().add_child(_rig)
	var service: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	service.name = "CollectionService"
	_rig.add_child(service)
	return service


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"collection_progressed": 0, &"collection_tier_reached": 0,
		&"collection_failed": 0}
	_embers = []
	if not bus.is_connected(&"collection_progressed", _on_progress):
		bus.connect(&"collection_progressed", _on_progress)
	if not bus.is_connected(&"collection_tier_reached", _on_tier):
		bus.connect(&"collection_tier_reached", _on_tier)


func _on_progress(_id: StringName, _n: int, _t: int) -> void:
	_events[&"collection_progressed"] = int(_events[&"collection_progressed"]) + 1


func _on_tier(_id: StringName, _tier: int, _unlock: StringName, ember: StringName) -> void:
	_events[&"collection_tier_reached"] = int(_events[&"collection_tier_reached"]) + 1
	_embers.append(ember)


func _t_content(c: StringName) -> Dictionary:
	var service := _make_service()
	if service.collections.size() != 6:
		return fail(c, "expected 6 collections, got %d" % service.collections.size())
	var embers: Array[StringName] = []
	for data: CollectionData in service.collections:
		if data.entries.size() < 6 or data.tiers.size() != 3:
			return fail(c, "%s is too thin" % data.id)
		if embers.has(data.ember):
			return fail(c, "duplicate ember %s" % data.ember)
		embers.append(data.ember)
	return succeeded(c, "6 collections, 6 distinct embers, 3 tiers each")


func _t_progress(c: StringName) -> Dictionary:
	var service := _make_service()
	_watch()
	service.call("record", &"parsnip")
	await tree.process_frame
	if int(service.call("discovered_count", &"fields")) != 1:
		return fail(c, "parsnip was not recorded in Fields")
	if int(_events[&"collection_progressed"]) != 1:
		var bus := autoload(&"EventBus")
		return fail(c, "no distinct progress event (connected=%s events=%s)" % [
			str(bus.is_connected(&"collection_progressed", _on_progress)), str(_events),
		])
	service.call("record", &"parsnip")
	if int(service.call("discovered_count", &"fields")) != 1:
		return fail(c, "a duplicate entry was counted twice")
	return succeeded(c, "one entry, one event; duplicates ignored")


func _t_tiers(c: StringName) -> Dictionary:
	var service := _make_service()
	_watch()
	var data: CollectionData = service.definition(&"fields")
	for i: int in range(data.entries.size()):
		service.call("record", data.entries[i])
	await tree.process_frame
	if int(_events[&"collection_tier_reached"]) < 3:
		return fail(c, "only %d tiers fired" % int(_events[&"collection_tier_reached"]))
	if not _embers.has(&"fields"):
		return fail(c, "completing Fields did not yield its Ember")
	return succeeded(c, "three tiers fired and Fields yielded an Ember")


func _t_heartstone(c: StringName) -> Dictionary:
	var state := HeartstoneState.new()
	if state.can_mend():
		return fail(c, "an empty Heartstone can be mended")
	for ember: StringName in HeartstoneState.EMBERS:
		state.add_ember(ember)
	if not state.can_mend() or state.count() != 6:
		return fail(c, "six embers did not enable the Mending")
	return succeeded(c, "Mending requires all six Embers")


func _t_save(c: StringName) -> Dictionary:
	var service := _make_service()
	service.call("record", &"fish_trout")
	var data: Dictionary = service.call("to_dict")
	var fresh := _make_service()
	fresh.call("from_dict", data)
	if int(fresh.call("discovered_count", &"waters")) != 1:
		return fail(c, "collection progress did not round-trip")
	return succeeded(c, "discovered entries survived a save")
