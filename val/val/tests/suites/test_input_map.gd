extends TestSuite
## Verifies every action in [InputActions] exists in the InputMap with at least
## one binding, so a missing input is caught here instead of mid-gameplay.


func get_cases() -> Array[StringName]:
	var cases: Array[StringName] = []
	for action: StringName in InputActions.movement_actions():
		cases.append(action)
	cases.append_array([
		InputActions.JUMP,
		InputActions.SPRINT,
		InputActions.CROUCH,
		InputActions.INTERACT,
		InputActions.INVENTORY,
		InputActions.JOURNAL,
		InputActions.TOGGLE_CAMERA_MODE,
		InputActions.PAUSE,
		InputActions.HOTBAR_1,
		InputActions.HOTBAR_9,
		InputActions.HOTBAR_SLOT_NEXT,
		InputActions.HOTBAR_SLOT_PREV,
		InputActions.ZOOM_IN,
		InputActions.ZOOM_OUT,
	])
	return cases


func _run(case: StringName) -> Dictionary:
	if not InputMap.has_action(case):
		return fail(case, "action '%s' is not registered in the InputMap" % case)
	var events := InputMap.action_get_events(case)
	if events.is_empty():
		return fail(case, "action '%s' has no bound events" % case)
	return succeeded(case, "%d binding(s)" % events.size())