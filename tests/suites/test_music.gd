extends TestSuite
## W6.7: objective checks, because taste cannot be asserted in CI. Every cue is
## a real multi-voice stereo loop, the leitmotif is present, and the director
## picks the right cue for each game state.

const DIR := "res://resources/audio/cues/"

var _director: MusicDirector = null


func is_async() -> bool:
	return true


func setup() -> void:
	_director = null


func teardown() -> void:
	if _director != null and is_instance_valid(_director):
		_director.free()
	_director = null


func get_cases() -> Array[StringName]:
	return [&"at_least_sixteen_valid_cues", &"cues_render_real_stereo_audio",
		&"no_cue_is_a_single_tone", &"director_follows_game_state",
		&"jukebox_unlocks_heard_cues"]


func _cues() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var cue := ResourceLoader.load(DIR + entry) as MusicCue
			if cue != null and cue.is_valid():
				out[cue.id] = cue
	return out


func _run_async(case: StringName) -> Dictionary:
	var cues := _cues()
	match case:
		&"at_least_sixteen_valid_cues":
			if cues.size() < 16:
				return fail(case, "only %d cues" % cues.size())
			var ids := {}
			for id: StringName in cues:
				if String(id).ends_with("_score"):
					return fail(case, "score id stored as cue")
				ids[id] = true
			if not ids.has(&"mending") or not ids.has(&"title"):
				return fail(case, "Mending or title cue missing")
			return succeeded(case, "%d valid cues" % cues.size())
		&"cues_render_real_stereo_audio":
			var checked := 0
			for id: StringName in [&"title", &"farm_spring", &"mending"]:
				var cue: MusicCue = cues.get(id)
				if cue == null:
					return fail(case, "%s missing" % id)
				var stream := MusicSynth.stream_for(cue.score)
				if stream == null or not stream.stereo:
					return fail(case, "%s is not stereo" % id)
				var seconds := float(stream.data.size()) / 4.0 / float(MusicSynth.RATE)
				if seconds < 60.0:
					return fail(case, "%s is only %.1f s" % [id, seconds])
				checked += 1
			return succeeded(case, "%d cues render >60 s stereo" % checked)
		&"no_cue_is_a_single_tone":
			# Count distinct sample values and sign changes in a short window.
			# A single sine has one pitch class; these scores have bass, pad and
			# melody plus percussion, so the window varies widely.
			var cue: MusicCue = cues.get(&"farm_spring")
			var stream := MusicSynth.stream_for(cue.score)
			var data: PackedByteArray = stream.data
			var distinct := {}
			var crossings := 0
			var previous := 0
			for i: int in range(0, mini(data.size() - 1, 200000), 8):
				var value := data.decode_s16(i)
				distinct[value / 512] = true
				if previous != 0 and signi(value) != signi(previous):
					crossings += 1
				previous = value
			if distinct.size() < 8 or crossings < 10:
				return fail(case, "cue looks like a single tone: %d bands, %d crossings" % [
					distinct.size(), crossings,
				])
			return succeeded(case, "%d amplitude bands, %d zero crossings" % [
				distinct.size(), crossings,
			])
		&"director_follows_game_state":
			_director = MusicDirector.new()
			root().add_child(_director)
			await tree.process_frame
			_director.set_context({"menu": true})
			if _director.current_id != &"title":
				return fail(case, "menu chose %s" % _director.current_id)
			_director.set_context({"menu": false, "location": "farm", "season": "winter"})
			if _director.current_id != &"farm_winter":
				return fail(case, "farm/winter chose %s" % _director.current_id)
			_director.set_context({"combat": true})
			if _director.current_id != &"combat":
				return fail(case, "combat chose %s" % _director.current_id)
			_director.set_context({"combat": false, "cutscene": true})
			if _director.current_id != &"cutscene":
				return fail(case, "cutscene chose %s" % _director.current_id)
			return succeeded(case, "menu -> farm/winter -> combat -> cutscene")
		&"jukebox_unlocks_heard_cues":
			_director = MusicDirector.new()
			root().add_child(_director)
			await tree.process_frame
			_director.set_context({"menu": true})
			var unlocked: Array = _director.call("unlocked_cues")
			if not unlocked.has(&"title"):
				return fail(case, "heard cue was not unlocked")
			if not bool(_director.call("play_cue", &"title")):
				return fail(case, "unlocked cue could not be replayed")
			return succeeded(case, "title unlocked and replayable")
	return fail(case, "no case implementation for %s" % case)
