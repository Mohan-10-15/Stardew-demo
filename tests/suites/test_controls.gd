extends TestSuite
## W1.1: the generated control table must describe a real, conflict-free input
## map with a pad path for the eight-input core loop.

const KEYBOARD_ONLY: Array[StringName] = [
	InputActions.CRAFT, InputActions.BUILD, InputActions.BUILDINGS,
	InputActions.SETTINGS, InputActions.SAVE_GAME, InputActions.LOAD_GAME,
	InputActions.TOGGLE_LOG_PANEL, InputActions.JUKEBOX,
	# On a pad the nine slots are reached with D-pad left/right (next/prev);
	# individual digit shortcuts are keyboard conveniences.
	InputActions.HOTBAR_1, InputActions.HOTBAR_2, InputActions.HOTBAR_3,
	InputActions.HOTBAR_4, InputActions.HOTBAR_5, InputActions.HOTBAR_6,
	InputActions.HOTBAR_7, InputActions.HOTBAR_8, InputActions.HOTBAR_9,
]
const CORE_LOOP: Array[StringName] = [
	InputActions.MOVE_FORWARD, InputActions.LOOK_RIGHT, InputActions.JUMP,
	InputActions.INTERACT, InputActions.USE, InputActions.ALT_USE,
	InputActions.HOTBAR_SLOT_NEXT, InputActions.PAUSE,
]


func get_cases() -> Array[StringName]:
	return [
		&"no_two_actions_share_a_binding_in_the_same_context",
		&"the_eight_input_core_loop_has_pad_bindings",
		&"every_other_gameplay_action_has_a_pad_or_is_keyboard_only",
		&"the_generated_control_table_matches_the_input_map",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"no_two_actions_share_a_binding_in_the_same_context":
			return _t_conflicts(case)
		&"the_eight_input_core_loop_has_pad_bindings":
			return _t_core(case)
		&"every_other_gameplay_action_has_a_pad_or_is_keyboard_only":
			return _t_pad_coverage(case)
		&"the_generated_control_table_matches_the_input_map":
			return _t_doc(case)
	return fail(case, "no case implementation for %s" % case)


func _t_conflicts(c: StringName) -> Dictionary:
	var seen := {}
	for action: String in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key := _event_key(event)
			if key.is_empty():
				continue
			if seen.has(key) and String(seen[key]) != action:
				return fail(c, "%s and %s both bind %s" % [
					str(seen[key]), action, key,
				])
			seen[key] = action
	return succeeded(c, "%d distinct bindings" % seen.size())


func _t_core(c: StringName) -> Dictionary:
	for action: StringName in CORE_LOOP:
		if not InputMap.has_action(action):
			return fail(c, "%s is missing" % action)
		if not _has_pad(action):
			return fail(c, "%s has no gamepad binding" % action)
	# The primary button is use, not interact; attack keeps only K on keyboard.
	if _event_owners("mouse:1").has(String(InputActions.USE)) \
			and _event_owners("mouse:1").size() == 1:
		return succeeded(c, "eight core inputs present; left click is use")
	return fail(c, "left click is not the primary use binding")


func _t_pad_coverage(c: StringName) -> Dictionary:
	for action: String in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		if KEYBOARD_ONLY.has(StringName(action)):
			continue
		if not _has_pad(StringName(action)):
			return fail(c, "%s has no pad binding and is not keyboard-only" % action)
	return succeeded(c, "every non-keyboard-only action has a pad binding")


func _t_doc(c: StringName) -> Dictionary:
	var path := "res://docs/CONTROLS.md"
	if not FileAccess.file_exists(path):
		return fail(c, "docs/CONTROLS.md was not generated")
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	for action: String in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		if not text.contains("`%s`" % action):
			return fail(c, "the generated table omits %s" % action)
	return succeeded(c, "generated table lists every InputMap action")


func _has_pad(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _event_key(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return "key:%d" % code
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "padbtn:%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "padaxis:%d:%s" % [motion.axis, "+" if motion.axis_value > 0 else "-"]
	return ""


func _event_owners(key: String) -> Array[String]:
	var out: Array[String] = []
	for action: String in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if _event_key(event) == key:
				out.append(action)
				break
	return out
