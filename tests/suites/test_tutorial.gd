extends TestSuite
## W1.9: a non-blocking first-day hint chain that completes on real events,
## survives a save, and can be permanently disabled.

const SERVICE_SCRIPT := "res://scripts/ui/tutorial_service.gd"
const MAIN := "res://scenes/core/main.tscn"

var _rig: Node3D = null
var _main: Node = null
var _old_enabled: bool = true


func is_async() -> bool:
	return true


func setup() -> void:
	_rig = null
	_main = null
	_old_enabled = autoload(&"Config").settings.tutorial_enabled
	autoload(&"Config").settings.tutorial_enabled = true


func teardown() -> void:
	# skip() persists to user://config.cfg, so restore on disk too — otherwise
	# every later suite and the real game boot with the tutorial disabled.
	var config := autoload(&"Config")
	config.settings.tutorial_enabled = _old_enabled
	config.set_value(&"accessibility", "tutorial_enabled", _old_enabled)
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"the_first_day_has_eight_plus_valid_steps":
			return await _t_steps()
		&"a_real_event_advances_the_hint":
			return await _t_advance()
		&"hints_use_device_glyphs":
			return await _t_glyphs()
		&"skipping_disables_it_permanently":
			return await _t_skip()
		&"tutorial_progress_survives_a_save":
			return await _t_save()
	return fail(case, "no case implementation for %s" % case)


func get_cases() -> Array[StringName]:
	return [
		&"the_first_day_has_eight_plus_valid_steps", &"a_real_event_advances_the_hint",
		&"hints_use_device_glyphs", &"skipping_disables_it_permanently",
		&"tutorial_progress_survives_a_save",
	]


func _make_service() -> Node:
	if _rig == null:
		_rig = Node3D.new()
		_rig.name = "TutorialTestRig"
		root().add_child(_rig)
	var service: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	service.name = "TutorialService"
	_rig.add_child(service)
	return service


func _t_steps() -> Dictionary:
	var service := _make_service()
	if service.steps.size() < 8:
		return fail(&"the_first_day_has_eight_plus_valid_steps",
			"only %d steps authored" % service.steps.size())
	for step: TutorialStep in service.steps:
		if not step.is_valid():
			return fail(&"the_first_day_has_eight_plus_valid_steps",
				"step %s is invalid" % step.id)
	return succeeded(&"the_first_day_has_eight_plus_valid_steps",
		"%d valid steps" % service.steps.size())


func _t_advance() -> Dictionary:
	var service := _make_service()
	var c := &"a_real_event_advances_the_hint"
	var before: int = service.current
	autoload(&"EventBus").emit_signal(&"footstep", &"grass")
	await tree.process_frame
	if int(service.current) <= before:
		return fail(c, "a footstep did not advance the chain")
	return succeeded(c, "step %d -> %d on a real footstep" % [before, service.current])


func _t_glyphs() -> Dictionary:
	var c := &"hints_use_device_glyphs"
	var service := _make_service()
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD_MOUSE)
	var kb := String(service.call("current_hint"))
	InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
	var pad := String(service.call("current_hint"))
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD_MOUSE)
	if kb == pad or kb.is_empty():
		return fail(c, "the hint did not follow the active device")
	if kb.contains("{") or pad.contains("{"):
		return fail(c, "an unexpanded glyph placeholder remains")
	return succeeded(c, "hint changed with the device: %s -> %s" % [kb, pad])


func _t_skip() -> Dictionary:
	var c := &"skipping_disables_it_permanently"
	var service := _make_service()
	service.call("skip")
	if bool(service.enabled):
		return fail(c, "skip left the tutorial enabled")
	if autoload(&"Config").settings.tutorial_enabled:
		return fail(c, "skip was not persisted in config")
	return succeeded(c, "skip disabled the chain and persisted")


func _t_save() -> Dictionary:
	var c := &"tutorial_progress_survives_a_save"
	var service := _make_service()
	service.current = 4
	var data: Dictionary = service.call("to_dict")
	var fresh: Node = _make_service()
	fresh.call("from_dict", data)
	if int(fresh.current) != 4:
		return fail(c, "progress did not round-trip: %d" % fresh.current)
	return succeeded(c, "step 4 survived a save round-trip")
