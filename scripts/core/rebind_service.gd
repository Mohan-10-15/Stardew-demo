class_name RebindService
extends Node
## Runtime key rebinding for the actions a player can reasonably change.
##
## The default bindings live in `project.godot`, generated from `InputActions`
## by `tools/rebuild_input_map.gd`. This service does not rewrite that file —
## it applies overrides to the live InputMap and persists them in
## `GameConfig.bindings`, which `ConfigService` saves to `user://config.cfg`.
## So a rebind survives a restart without touching source control, and the
## generator remains the single source of *defaults*.
##
## Only key events are replaced. A rebind of `interact` must keep its mouse
## button, or a player who uses a mouse loses the ability to interact at all.

const SERVICE_GROUP := &"rebind_service"

## Deliberately not movement or the hotbar: eight directions plus nine slots
## is a menu nobody can navigate, and the hotbar labels are drawn as digits.
const REBINDABLE: Array[StringName] = [
	InputActions.INTERACT, InputActions.INVENTORY, InputActions.JOURNAL,
	InputActions.CRAFT, InputActions.BUILD, InputActions.BUILDINGS,
	InputActions.SETTINGS, InputActions.TOGGLE_CAMERA_MODE,
	InputActions.TOGGLE_LOG_PANEL, InputActions.ATTACK,
]


var _defaults: Dictionary = {}


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	# Captured before overrides are applied, so "reset" restores the real
	# generated InputMap (which may carry several keys and a mouse button)
	# instead of guessing at a ProjectSettings dictionary format.
	_capture_defaults()
	apply_bindings()


func _capture_defaults() -> void:
	_defaults.clear()
	for action: StringName in REBINDABLE:
		_defaults[action] = InputMap.action_get_events(action).duplicate()


static func find(start: Node) -> RebindService:
	if start == null:
		return null
	if start is RebindService:
		return start as RebindService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


static func is_rebindable(action: StringName) -> bool:
	return REBINDABLE.has(action)


## Applies every saved override. Safe to call repeatedly: the saved binding is
## the source of truth, so a second call reproduces the same InputMap.
func apply_bindings() -> void:
	var bindings: Dictionary = Config.settings.bindings
	for key: Variant in bindings:
		var action := StringName(String(key))
		if not is_rebindable(action):
			continue
		_apply_one(action, int(bindings[key]))


## Binds [param action] to [param keycode], stealing the key from any other
## rebindable action that held it. Returns false for an unknown action or a
## null key, so the settings panel never silently reports a successful rebind.
func rebind(action: StringName, keycode: int) -> bool:
	if not is_rebindable(action) or keycode <= 0:
		return false
	if not InputMap.has_action(action):
		return false
	for other: StringName in REBINDABLE:
		if other == action:
			continue
		if _has_key(other, keycode):
			_erase_keys(other)
			Config.settings.bindings[String(other)] = 0
	_apply_one(action, keycode)
	Config.settings.bindings[String(action)] = keycode
	Config.save_config()
	EventBus.input_rebound.emit(action, keycode)
	return true


## Clears every override and restores the generated defaults from project.godot.
## A restart also restores them, but doing it now makes the menu responsive.
func reset_all() -> void:
	Config.settings.bindings.clear()
	for action: StringName in REBINDABLE:
		InputMap.action_erase_events(action)
		var events: Variant = _defaults.get(action, [])
		if events is Array:
			for event: InputEvent in (events as Array):
				InputMap.action_add_event(action, event)
	Config.save_config()
	EventBus.input_rebound.emit(&"", 0)


func key_for(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if code > 0:
				return code
	return 0


func label_for(action: StringName) -> String:
	var code := key_for(action)
	return OS.get_keycode_string(code) if code > 0 else "?"


func _apply_one(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action) or keycode <= 0:
		return
	_erase_keys(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _erase_keys(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)


func _has_key(action: StringName, keycode: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.physical_keycode == keycode or key.keycode == keycode:
				return true
	return false


