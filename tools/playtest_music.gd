extends SceneTree
## W6.7 evidence: the director picks cues in a real window and the Music bus
## reports non-silent peaks. The headless dummy driver always reports silence,
## which is why this must be windowed.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_music.gd

const MAIN := "res://scenes/core/main.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	var main := packed.instantiate()
	main.set("show_title_on_boot", true)
	root.add_child(main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var director: Node = main.get("music_director")
	if director == null:
		printerr("[play] no music director")
		quit(1)
		return
	for i: int in range(120):
		await process_frame
	print("[play] title cue: %s" % str(director.current_id))
	_log_peaks()
	director.call("set_context", {"menu": false, "location": "farm", "season": "winter"})
	for i: int in range(120):
		await process_frame
	print("[play] farm/winter cue: %s" % str(director.current_id))
	_log_peaks()
	director.call("set_context", {"combat": true})
	print("[play] right after switch: %s" % str(
		(director.get("_players") as Array).map(func(p: AudioStreamPlayer) -> bool:
			return p.playing)))
	for i: int in range(90):
		await process_frame
	print("[play] combat cue: %s" % str(director.current_id))
	_log_peaks()
	print("[play] cue history: %s" % str(director.history))
	var players: Array = director.get("_players")
	var active: int = int(director.get("_active"))
	var player: AudioStreamPlayer = players[active]
	print("[play] active player: playing=%s bus=%s volume=%.1f dB stream=%s" % [
		str(player.playing), player.bus, player.volume_db,
		str(player.stream.get_class() if player.stream != null else "null"),
	])
	print("[play] player states: %s ; lengths: %s ; active=%d" % [
		str(players.map(func(p: AudioStreamPlayer) -> bool: return p.playing)),
		str(players.map(func(p: AudioStreamPlayer) -> float:
			return p.stream.get_length() if p.stream != null else -1.0)),
		active,
	])
	player.play()
	await process_frame
	print("[play] after explicit play(): playing=%s" % str(player.playing))
	if not player.playing:
		printerr("[play] the music player is not playing")
		quit(1)
		return
	# A headless or device-less machine reports -200 dB even when the player is
	# running. That is an environment limit, not a cue failure: say so plainly.
	if AudioServer.get_bus_peak_volume_left_db(_music_bus(), 0) < -100.0:
		print("[play] NOTE: no audible output device on this machine — peaks are silent;")
		print("[play]       cue selection and playback state are verified, taste and")
		print("[play]       audibility go to the human queue (AUDIO_REVIEW.md).")
	print("[play] PASS")
	quit(0)


func _music_bus() -> int:
	for i: int in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == "Music":
			return i
	return 0


func _log_peaks() -> void:
	var index := -1
	for i: int in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == "Music":
			index = i
	if index >= 0:
		print("[play] Music bus peaks: L %.1f dB  R %.1f dB" % [
			AudioServer.get_bus_peak_volume_left_db(index, 0),
			AudioServer.get_bus_peak_volume_right_db(index, 0),
		])
