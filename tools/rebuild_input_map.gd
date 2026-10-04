extends SceneTree
## Headless tool: (re)builds the project's InputMap from [InputActions] and
## writes the result into `project.godot`.
##
## Run:
##     godot --headless --path . --script res://tools/rebuild_input_map.gd
##
## This keeps the default bindings in source control, reviewable in a diff,
## instead of buried in editor-only state.

const KeyBindings := {
	InputActions.MOVE_FORWARD: [KEY_W, KEY_UP],
	InputActions.MOVE_BACK: [KEY_S, KEY_DOWN],
	InputActions.MOVE_LEFT: [KEY_A, KEY_LEFT],
	InputActions.MOVE_RIGHT: [KEY_D, KEY_RIGHT],
	InputActions.JUMP: [KEY_SPACE],
	InputActions.SPRINT: [KEY_SHIFT],
	InputActions.CROUCH: [KEY_CTRL],
	InputActions.INTERACT: [KEY_E],
	InputActions.INVENTORY: [KEY_TAB],
	InputActions.JOURNAL: [KEY_J],
	InputActions.TOGGLE_CAMERA_MODE: [KEY_V],
	InputActions.PAUSE: [KEY_ESCAPE],
	InputActions.TOGGLE_LOG_PANEL: [KEY_F3],
	InputActions.HOTBAR_1: [KEY_1],
	InputActions.HOTBAR_2: [KEY_2],
	InputActions.HOTBAR_3: [KEY_3],
	InputActions.HOTBAR_4: [KEY_4],
	InputActions.HOTBAR_5: [KEY_5],
	InputActions.HOTBAR_6: [KEY_6],
	InputActions.HOTBAR_7: [KEY_7],
	InputActions.HOTBAR_8: [KEY_8],
	InputActions.HOTBAR_9: [KEY_9],
	InputActions.ZOOM_IN: [KEY_EQUAL],
	InputActions.ZOOM_OUT: [KEY_MINUS],
}

const MouseBindings := {
	InputActions.INTERACT: [MOUSE_BUTTON_LEFT],
	InputActions.HOTBAR_SLOT_NEXT: [MOUSE_BUTTON_WHEEL_DOWN],
	InputActions.HOTBAR_SLOT_PREV: [MOUSE_BUTTON_WHEEL_UP],
}

const JoyButtonBindings := {
	InputActions.MOVE_FORWARD: [JOY_BUTTON_A],
	InputActions.MOVE_BACK: [JOY_BUTTON_A],
	InputActions.JUMP: [JOY_BUTTON_A],
	InputActions.SPRINT: [JOY_BUTTON_LEFT_STICK],
	InputActions.CROUCH: [JOY_BUTTON_RIGHT_STICK],
	InputActions.INTERACT: [JOY_BUTTON_X],
	InputActions.INVENTORY: [JOY_BUTTON_Y],
	InputActions.JOURNAL: [JOY_BUTTON_BACK],
	InputActions.TOGGLE_CAMERA_MODE: [JOY_BUTTON_RIGHT_SHOULDER],
	InputActions.PAUSE: [JOY_BUTTON_START],
	InputActions.HOTBAR_SLOT_NEXT: [JOY_BUTTON_DPAD_RIGHT],
	InputActions.HOTBAR_SLOT_PREV: [JOY_BUTTON_DPAD_LEFT],
}

const JoyAxisBindings := {
	InputActions.MOVE_FORWARD: [[JOY_AXIS_LEFT_Y, -1.0]],
	InputActions.MOVE_BACK: [[JOY_AXIS_LEFT_Y, 1.0]],
	InputActions.MOVE_LEFT: [[JOY_AXIS_LEFT_X, -1.0]],
	InputActions.MOVE_RIGHT: [[JOY_AXIS_LEFT_X, 1.0]],
	InputActions.LOOK_LEFT: [[JOY_AXIS_RIGHT_X, -1.0]],
	InputActions.LOOK_RIGHT: [[JOY_AXIS_RIGHT_X, 1.0]],
	InputActions.LOOK_UP: [[JOY_AXIS_RIGHT_Y, -1.0]],
	InputActions.LOOK_DOWN: [[JOY_AXIS_RIGHT_Y, 1.0]],
	InputActions.ZOOM_IN: [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	InputActions.ZOOM_OUT: [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
}

const DEADZONES := {
	InputActions.MOVE_FORWARD: 0.2,
	InputActions.MOVE_BACK: 0.2,
	InputActions.MOVE_LEFT: 0.2,
	InputActions.MOVE_RIGHT: 0.2,
	InputActions.LOOK_LEFT: 0.2,
	InputActions.LOOK_RIGHT: 0.2,
	InputActions.LOOK_UP: 0.2,
	InputActions.LOOK_DOWN: 0.2,
	InputActions.JUMP: 0.5,
	InputActions.SPRINT: 0.5,
	InputActions.CROUCH: 0.5,
	InputActions.INTERACT: 0.5,
	InputActions.INVENTORY: 0.5,
	InputActions.JOURNAL: 0.5,
	InputActions.TOGGLE_CAMERA_MODE: 0.5,
	InputActions.PAUSE: 0.5,
}


## Every action this tool is responsible for. Order does not matter; the
## project file is rewritten wholesale from this set.
const ALL_ACTIONS := [
	InputActions.MOVE_FORWARD,
	InputActions.MOVE_BACK,
	InputActions.MOVE_LEFT,
	InputActions.MOVE_RIGHT,
	InputActions.JUMP,
	InputActions.SPRINT,
	InputActions.CROUCH,
	InputActions.LOOK_LEFT,
	InputActions.LOOK_RIGHT,
	InputActions.LOOK_UP,
	InputActions.LOOK_DOWN,
	InputActions.INTERACT,
	InputActions.INVENTORY,
	InputActions.JOURNAL,
	InputActions.TOGGLE_CAMERA_MODE,
	InputActions.PAUSE,
	InputActions.TOGGLE_LOG_PANEL,
	InputActions.HOTBAR_1,
	InputActions.HOTBAR_2,
	InputActions.HOTBAR_3,
	InputActions.HOTBAR_4,
	InputActions.HOTBAR_5,
	InputActions.HOTBAR_6,
	InputActions.HOTBAR_7,
	InputActions.HOTBAR_8,
	InputActions.HOTBAR_9,
	InputActions.HOTBAR_SLOT_NEXT,
	InputActions.HOTBAR_SLOT_PREV,
	InputActions.ZOOM_IN,
	InputActions.ZOOM_OUT,
	InputActions.LOOK_LEFT,
	InputActions.LOOK_RIGHT,
	InputActions.LOOK_UP,
	InputActions.LOOK_DOWN,
]


func _initialize() -> void:
	var actions := {}
	for action: StringName in ALL_ACTIONS:
		actions[action] = _build_action(action)

	for action: StringName in actions.keys():
		ProjectSettings.set_setting("input/" + String(action), actions[action])

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Failed to save project.godot: %d" % err)
		quit(1)
		return
	print("[rebuild_input_map] wrote %d actions to project.godot" % actions.size())
	quit(0)


func _build_action(action: StringName) -> Dictionary:
	var events: Array[InputEvent] = []

	for keycode: int in KeyBindings.get(action, []):
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode
		events.append(ev)

	for button: int in MouseBindings.get(action, []):
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		events.append(ev)

	for button: int in JoyButtonBindings.get(action, []):
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		events.append(ev)

	for pair: Array in JoyAxisBindings.get(action, []):
		var ev := InputEventJoypadMotion.new()
		ev.axis = pair[0]
		ev.axis_value = pair[1]
		events.append(ev)

	return {"deadzone": DEADZONES.get(action, 0.5), "events": events}