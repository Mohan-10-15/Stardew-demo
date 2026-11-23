extends TestSuite
## W1.2: one glyph source, driven by the last-used device, with no hard-coded
## key names left in player-facing UI strings.

const FORBIDDEN: Array[String] = ["F5", "F9", "F3", "Press E", "[E]"]


func get_cases() -> Array[StringName]:
	return [
		&"labels_follow_the_active_device",
		&"observing_a_pad_event_changes_the_device",
		&"player_facing_strings_have_no_hard_coded_keys",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"labels_follow_the_active_device":
			return _t_labels(case)
		&"observing_a_pad_event_changes_the_device":
			return _t_device(case)
		&"player_facing_strings_have_no_hard_coded_keys":
			return _t_literals(case)
	return fail(case, "no case implementation for %s" % case)


func _t_labels(c: StringName) -> Dictionary:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD_MOUSE)
	var kb_jump := InputGlyphs.label_for(InputActions.JUMP)
	var kb_use := InputGlyphs.label_for(InputActions.USE)
	InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
	var pad_jump := InputGlyphs.label_for(InputActions.JUMP)
	var pad_use := InputGlyphs.label_for(InputActions.USE)
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD_MOUSE)
	if kb_jump != "Space" or kb_use != "LMB":
		return fail(c, "keyboard labels were %s / %s" % [kb_jump, kb_use])
	if pad_jump != "A" or pad_use != "RT":
		return fail(c, "pad labels were %s / %s" % [pad_jump, pad_use])
	return succeeded(c, "Space/LMB swap to A/RT on device change")


func _t_device(c: StringName) -> Dictionary:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD_MOUSE)
	var bus := autoload(&"EventBus")
	var seen: Array[int] = []
	var callback := func(device: int) -> void: seen.append(device)
	bus.input_device_changed.connect(callback)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	InputGlyphs.observe(pad)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputGlyphs.observe(mouse)
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD_MOUSE)
	if bus.input_device_changed.is_connected(callback):
		bus.input_device_changed.disconnect(callback)
	if seen.size() != 2:
		return fail(c, "expected two device changes, got %s" % str(seen))
	return succeeded(c, "a pad press and a mouse click each changed the device")


func _t_literals(c: StringName) -> Dictionary:
	var dirs: Array[String] = ["res://scripts/ui", "res://tools"]
	var checked := 0
	for dir_path: String in dirs:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			if not (file_name.ends_with(".gd") or file_name.ends_with(".gd.uid")):
				continue
			if file_name == "input_glyphs.gd":
				continue
			# Dev-only tools log key names in their own diagnostics; they are
			# not player-facing strings and never ship in an export.
			if file_name.begins_with("playtest_") or file_name.begins_with("probe_") \
					or file_name.begins_with("release_") or file_name.begins_with("validate_"):
				continue
			if file_name.begins_with("generate_") and not file_name.ends_with(".gd"):
				continue
			var path := dir_path.path_join(file_name)
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				continue
			var text := file.get_as_text()
			file.close()
			checked += 1
			for line: String in text.split("\n"):
				var trimmed := line.strip_edges()
				if trimmed.begins_with("#"):
					continue
				for needle: String in FORBIDDEN:
					if trimmed.contains("\"%s" % needle) or trimmed.contains("%s\"" % needle) \
							or trimmed.contains("'%s" % needle):
						return fail(c, "%s contains a hard-coded %s" % [path, needle])
	if checked == 0:
		return fail(c, "no UI scripts scanned")
	return succeeded(c, "%d UI/generator scripts free of hard-coded key names" % checked)
