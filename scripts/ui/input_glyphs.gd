class_name InputGlyphs
extends RefCounted
## One place that turns an InputMap action into the label the player should
## see, for whichever device they last used. Keycaps are plain text drawn in
## code; pad glyphs use the conventional button letters, so no CC0 prompt pack
## is needed and nothing new ships in the export.

enum Device { KEYBOARD_MOUSE, GAMEPAD }

static var _device: Device = Device.KEYBOARD_MOUSE

## Convenience glyphs. Kept here so a test can grep for hard-coded key names
## in the rest of scripts/ui/ and know they are wrong.
const PAD_GLYPHS := {
	InputActions.MOVE_FORWARD: "LS",
	InputActions.MOVE_BACK: "LS",
	InputActions.MOVE_LEFT: "LS",
	InputActions.MOVE_RIGHT: "LS",
	InputActions.LOOK_LEFT: "RS",
	InputActions.LOOK_RIGHT: "RS",
	InputActions.LOOK_UP: "RS",
	InputActions.LOOK_DOWN: "RS",
	InputActions.JUMP: "A",
	InputActions.INTERACT: "X",
	InputActions.USE: "RT",
	InputActions.ALT_USE: "LT",
	InputActions.INVENTORY: "Y",
	InputActions.JOURNAL: "Back",
	InputActions.TOGGLE_CAMERA_MODE: "RB",
	InputActions.PAUSE: "Start",
	InputActions.ATTACK: "B",
	InputActions.HOTBAR_SLOT_NEXT: "D→",
	InputActions.HOTBAR_SLOT_PREV: "D←",
	InputActions.SPRINT: "L3",
	InputActions.CROUCH: "R3",
	InputActions.ZOOM_IN: "D↑",
	InputActions.ZOOM_OUT: "D↓",
}


static func device() -> Device:
	return _device


static func set_device(value: Device) -> void:
	if _device == value:
		return
	_device = value
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var bus := (loop as SceneTree).root.get_node_or_null(^"EventBus")
		if bus != null:
			bus.input_device_changed.emit(int(value))


static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		set_device(Device.GAMEPAD)
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		set_device(Device.KEYBOARD_MOUSE)


## Human-readable label for an action on the active device.
static func label_for(action: StringName) -> String:
	if _device == Device.GAMEPAD and PAD_GLYPHS.has(action):
		return String(PAD_GLYPHS[action])
	return _keyboard_label(action)


## The first keyboard or mouse event bound to the action.
static func _keyboard_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			return OS.get_keycode_string(code)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
	return "?"


static func device_name() -> String:
	return "Gamepad" if _device == Device.GAMEPAD else "Keyboard"
