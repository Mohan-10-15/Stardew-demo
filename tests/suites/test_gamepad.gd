extends TestSuite
## W1.8 - an alternative to a physical controller check. No gamepad is attached
## to this machine, but Godot's Input map can be driven with synthetic joypad
## events, so we can still prove a button press and an analog stick *reach the
## actions the game actually reads*. Feel and ergonomics stay a human-queue
## item; this only removes the "is the gamepad wired at all?" unknown.

func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [&"joypad_buttons_drive_actions", &"joypad_axes_drive_movement"]


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"joypad_buttons_drive_actions":
			var found := _first_button_binding()
			if found.is_empty():
				return fail(case, "no joypad button is bound to any action")
			var action: StringName = found["action"]
			var index: int = int(found["index"])
			var press := InputEventJoypadButton.new()
			press.button_index = index
			press.pressed = true
			Input.parse_input_event(press)
			await tree.process_frame
			var down := Input.is_action_pressed(action)
			var release := InputEventJoypadButton.new()
			release.button_index = index
			release.pressed = false
			Input.parse_input_event(release)
			await tree.process_frame
			var up := Input.is_action_pressed(action)
			if not down:
				return fail(case, "button %d did not press action '%s'" % [index, action])
			if up:
				return fail(case, "button %d did not release action '%s'" % [index, action])
			return succeeded(case, "button %d pressed and released '%s'" % [index, action])
		&"joypad_axes_drive_movement":
			var found := _first_motion_binding()
			if found.is_empty():
				return fail(case, "no joypad axis is bound to any action")
			var action: StringName = found["action"]
			var axis: int = int(found["axis"])
			var value: float = float(found["value"])
			var push := InputEventJoypadMotion.new()
			push.axis = axis
			push.axis_value = value
			Input.parse_input_event(push)
			await tree.process_frame
			var down := Input.is_action_pressed(action)
			var neutral := InputEventJoypadMotion.new()
			neutral.axis = axis
			neutral.axis_value = 0.0
			Input.parse_input_event(neutral)
			await tree.process_frame
			var up := Input.is_action_pressed(action)
			if not down:
				return fail(case, "axis %d at %.1f did not press '%s'" % [axis, value, action])
			if up:
				return fail(case, "axis %d at 0 did not release '%s'" % [axis, action])
			return succeeded(case, "axis %d drove '%s'" % [axis, action])
	return fail(case, "unhandled case")


func _first_button_binding() -> Dictionary:
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				return {"action": action, "index": (event as InputEventJoypadButton).button_index}
	return {}


func _first_motion_binding() -> Dictionary:
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				var m := event as InputEventJoypadMotion
				return {"action": action, "axis": m.axis, "value": m.axis_value}
	return {}
