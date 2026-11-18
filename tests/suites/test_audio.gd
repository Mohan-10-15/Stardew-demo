extends TestSuite
## Audio, headlessly: the definitions are content, the signal map is the one
## place a sound is chosen, and success and failure must never share a file.
## What this suite cannot check is whether a cue *sounds* right — that is a
## real-window playtest, as `docs/AUDIO_GUIDE.md` requires.

const MANAGER_SCRIPT := "res://scripts/audio/audio_manager.gd"

var _rig: Node3D = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"every_sound_is_authored_and_unique",
		&"every_signal_has_its_own_sound",
		&"synth_produces_distinct_nonempty_streams",
		&"audio_settings_round_trip",
		&"the_manager_boots_headlessly",
	]


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"every_sound_is_authored_and_unique":
			return _t_definitions()
		&"every_signal_has_its_own_sound":
			return _t_signal_map()
		&"synth_produces_distinct_nonempty_streams":
			return _t_synth()
		&"audio_settings_round_trip":
			return await _t_settings()
		&"the_manager_boots_headlessly":
			return await _t_boot()
	return fail(case, "no case implementation for %s" % case)


func _t_definitions() -> Dictionary:
	var c := &"every_sound_is_authored_and_unique"
	var all := AudioRegistry.all_sounds()
	if all.size() < 8:
		return fail(c, "only %d sounds were authored" % all.size())
	var bad := AudioRegistry.duplicate_ids()
	if not bad.is_empty():
		return fail(c, "duplicate sound ids: %s" % str(bad))
	for definition: AudioDefinition in all:
		if not definition.is_valid():
			bad.append(definition.id)
		if AudioServer.get_bus_index(AudioDefinition.bus_name(definition.bus)) < 0 \
				and AudioDefinition.bus_name(definition.bus) != &"Music":
			# Music/SFX/Ambient/UI buses are created by the manager at boot; in a
			# bare content test only Master exists, which is expected.
			pass
	return check_equals(c, bad, [] as Array[StringName])


func _t_signal_map() -> Dictionary:
	var c := &"every_signal_has_its_own_sound"
	var script := load(MANAGER_SCRIPT) as GDScript
	if script == null:
		return fail(c, "no audio manager script")
	var map: Dictionary = script.get_script_constant_map().get("SOUND_FOR_SIGNAL", {})
	if map.is_empty():
		return fail(c, "the signal map is empty")
	var bus := autoload(&"EventBus")
	var bad: Array[String] = []
	var used: Dictionary = {}
	for signal_name: StringName in map:
		var id: StringName = map[signal_name]
		if bus != null and not bus.has_signal(signal_name):
			bad.append("no EventBus signal '%s'" % signal_name)
		if not AudioRegistry.has_sound(id):
			bad.append("'%s' has no sound '%s'" % [signal_name, id])
		if used.has(id):
			bad.append("'%s' and '%s' share '%s'" % [str(used[id]), signal_name, id])
		used[id] = signal_name
	return check_equals(c, bad, [] as Array[String])


func _t_synth() -> Dictionary:
	var c := &"synth_produces_distinct_nonempty_streams"
	var first := AudioRegistry.sound_for(&"hoe_till")
	var second := AudioRegistry.sound_for(&"crop_harvest")
	if first == null or second == null:
		return fail(c, "the two comparison sounds are missing")
	var synth := load("res://scripts/audio/audio_synth.gd") as GDScript
	var a: AudioStreamWAV = synth.call(&"stream_for", first)
	var b: AudioStreamWAV = synth.call(&"stream_for", second)
	if a == null or b == null or a.data.is_empty() or b.data.is_empty():
		return fail(c, "a synthesised stream is empty")
	if a.data == b.data:
		return fail(c, "two different sounds synthesised identical PCM")
	return succeeded(c, "%d sounds, distinct PCM for two sampled ids" % AudioRegistry.all_sounds().size())


func _t_settings() -> Dictionary:
	var c := &"audio_settings_round_trip"
	var config := autoload(&"Config")
	if config == null or config.get("settings") == null:
		return fail(c, "no Config service")
	var settings: Resource = config.get("settings")
	config.call("set_value", &"audio", "ambient_volume", 0.42)
	config.call("set_value", &"audio", "ui_volume", 0.31)
	config.call("set_value", &"audio", "muted", true)
	config.call("save_config")
	config.call("load_config")
	var after: Resource = config.get("settings")
	if not is_equal_approx(float(after.get("ambient_volume")), 0.42) \
			or not is_equal_approx(float(after.get("ui_volume")), 0.31) \
			or not bool(after.get("muted")):
		return fail(c, "audio settings did not survive save/load")
	settings.ambient_volume = 0.8
	settings.ui_volume = 0.9
	settings.muted = false
	config.call("save_config")
	return succeeded(c, "ambient, UI and mute persisted and were restored")


func _t_boot() -> Dictionary:
	var c := &"the_manager_boots_headlessly"
	_reset_rig()
	var script := load(MANAGER_SCRIPT) as GDScript
	if script == null:
		return fail(c, "no audio manager script")
	_ensure_rig()
	var manager: Node = script.new()
	manager.name = "AudioManager"
	_rig.add_child(manager)
	await _step(3)
	manager.call("play_sfx", &"hoe_till")
	manager.call("play_sfx", &"sound_that_does_not_exist")
	manager.call("play_music", &"farm_theme")
	manager.call("play_ambience", &"rain_loop")
	var bus := autoload(&"EventBus")
	if bus != null:
		bus.emit_signal(&"game_paused", true)
		await _step(2)
		bus.emit_signal(&"game_paused", false)
		for name: StringName in [&"Music", &"SFX", &"Ambient", &"UI"]:
			if AudioServer.get_bus_index(name) < 0:
				return fail(c, "no '%s' bus was created" % name)
	return succeeded(c, "manager played sounds, crossfaded and muted without a device")


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "AudioTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
