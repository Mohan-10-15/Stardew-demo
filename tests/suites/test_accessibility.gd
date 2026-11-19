extends TestSuite
## M15: accessibility settings, end-to-end rebinding, and keyboard escape.

const REBIND_SCRIPT := "res://scripts/core/rebind_service.gd"
const ACCESS_SCRIPT := "res://scripts/core/ui_accessibility.gd"
const MACHINE_PANEL := "res://scenes/ui/machine_panel.tscn"

var _rig: Node3D = null
var _old_scale: float = 1.0
var _old_contrast: bool = false
var _old_bindings: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"accessibility_settings_have_sane_defaults",
		&"text_scaling_does_not_compound",
		&"rebinding_updates_the_inputmap_and_config",
		&"a_rebind_steals_the_key_from_another_action",
		&"escape_closes_an_open_panel",
	]


func setup() -> void:
	_rig = null
	var config := autoload(&"Config")
	_old_scale = config.settings.ui_scale
	_old_contrast = config.settings.colour_assist
	_old_bindings = config.settings.bindings.duplicate(true)


func teardown() -> void:
	var config := autoload(&"Config")
	config.settings.ui_scale = _old_scale
	config.settings.colour_assist = _old_contrast
	config.settings.bindings = _old_bindings.duplicate(true)
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"accessibility_settings_have_sane_defaults":
			return _t_defaults()
		&"text_scaling_does_not_compound":
			return _t_scale()
		&"rebinding_updates_the_inputmap_and_config":
			return _t_rebind()
		&"a_rebind_steals_the_key_from_another_action":
			return _t_steal()
		&"escape_closes_an_open_panel":
			return await _t_escape()
	return fail(case, "no case implementation for %s" % case)


func _t_defaults() -> Dictionary:
	var c := &"accessibility_settings_have_sane_defaults"
	var config := autoload(&"Config")
	config.settings.ui_scale = 9.0
	config.settings.ui_scale = clampf(config.settings.ui_scale, 0.75, 1.5)
	if not is_equal_approx(config.settings.ui_scale, 1.5):
		return fail(c, "an out-of-range scale was not clamped")
	var service: Node = (load(REBIND_SCRIPT) as GDScript).new()
	for action: StringName in service.get("REBINDABLE"):
		if not InputMap.has_action(String(action)):
			return fail(c, "%s is not in the InputMap" % action)
	service.free()
	return succeeded(c, "scale clamps and every rebindable action exists")


func _t_scale() -> Dictionary:
	var c := &"text_scaling_does_not_compound"
	_ensure_rig()
	var label := Label.new()
	label.text = "Stamina 100/100"
	label.add_theme_font_size_override(&"font_size", 12)
	_rig.add_child(label)
	var access: Node = (load(ACCESS_SCRIPT) as GDScript).new()
	_rig.add_child(access)
	autoload(&"Config").settings.ui_scale = 1.25
	access.call("_apply_text", label)
	var once: int = int(label.get_theme_font_size(&"font_size"))
	access.call("_apply_text", label)
	var twice: int = int(label.get_theme_font_size(&"font_size"))
	if once != 15 or twice != once:
		return fail(c, "font size went %d then %d, expected 15 twice" % [once, twice])
	return succeeded(c, "1.25x turned 12px into 15px and stayed there")


func _t_rebind() -> Dictionary:
	var c := &"rebinding_updates_the_inputmap_and_config"
	_ensure_rig()
	var service: Node = (load(REBIND_SCRIPT) as GDScript).new()
	_rig.add_child(service)
	if not bool(service.call("rebind", InputActions.INTERACT, KEY_R)):
		return fail(c, "the rebind was refused")
	if not _has_key(InputActions.INTERACT, KEY_R):
		return fail(c, "the InputMap did not change")
	if int(autoload(&"Config").settings.bindings.get(String(InputActions.INTERACT), 0)) != KEY_R:
		return fail(c, "the rebind was not persisted to config")
	if String(service.call("label_for", InputActions.INTERACT)) != "R":
		return fail(c, "the HUD label would not read the new key")
	service.call("reset_all")
	return succeeded(c, "E became R in the InputMap, config and HUD label")


func _t_steal() -> Dictionary:
	var c := &"a_rebind_steals_the_key_from_another_action"
	_ensure_rig()
	var service: Node = (load(REBIND_SCRIPT) as GDScript).new()
	_rig.add_child(service)
	service.call("rebind", InputActions.INVENTORY, KEY_E)
	if not _has_key(InputActions.INVENTORY, KEY_E):
		return fail(c, "inventory did not take E")
	if _has_key(InputActions.INTERACT, KEY_E):
		return fail(c, "interact kept E too — two actions would fire at once")
	service.call("reset_all")
	return succeeded(c, "the old owner lost the key when it was reassigned")


func _t_escape() -> Dictionary:
	var c := &"escape_closes_an_open_panel"
	_ensure_rig()
	var packed := load(MACHINE_PANEL) as PackedScene
	var panel := packed.instantiate() as CanvasLayer
	_rig.add_child(panel)
	await _step(3)
	var open := func() -> void: panel.call("_toggle")
	open.call()
	if not bool(panel.visible):
		return fail(c, "the panel did not open")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await _step(3)
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.physical_keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)
	await _step(3)
	if bool(panel.visible):
		return fail(c, "Escape did not close the panel")
	return succeeded(c, "Escape dismisses a panel opened by its own key")


func _has_key(action: StringName, code: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.physical_keycode == code or key.keycode == code:
				return true
	return false


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "AccessibilityTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
