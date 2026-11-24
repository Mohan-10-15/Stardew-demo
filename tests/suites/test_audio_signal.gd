extends TestSuite
## W6.8 - a NUMERIC listening substitute. This machine has no audible output
## device, so "is the score actually music?" cannot be answered by ear here.
## It can be answered by the waveform: render all 17 cues and assert they are
## non-silent, genuinely stereo, distinct from one another, unclipped and
## fade-seamed for looping. This does NOT claim the music sounds good - that
## stays a human-queue item - but it proves the signal is well formed.

const CUE_DIR := "res://resources/audio/cues"

func get_cases() -> Array[StringName]:
	return [&"every_cue_is_audible_stereo_and_distinct",
		&"loops_fade_at_the_seam_without_clipping"]


func _run(case: StringName) -> Dictionary:
	var cues := _cues()
	if cues.size() < 16:
		return fail(case, "only %d cue resources on disk" % cues.size())
	match case:
		&"every_cue_is_audible_stereo_and_distinct":
			var fingerprints: Dictionary = {}
			var quiet: Array[String] = []
			var mono: Array[String] = []
			for cue in cues:
				var stream: AudioStreamWAV = MusicSynth.stream_for(cue.score)
				if stream == null or stream.data.is_empty():
					return fail(case, "%s rendered no PCM" % cue.id)
				var m := _metrics(stream)
				if float(m["rms"]) < 0.01:
					quiet.append(String(cue.id))
				if float(m["side"]) < 0.0002:
					mono.append(String(cue.id))
				var fp := String(cue.id) + ":" + str(hash(stream.data))
				fingerprints[fp] = true
			if not quiet.is_empty():
				return fail(case, "silent cues: %s" % str(quiet))
			if not mono.is_empty():
				return fail(case, "cues with no stereo spread: %s" % str(mono))
			if fingerprints.size() < cues.size() - 1:
				return fail(case, "cues share PCM: only %d unique of %d" % [
					fingerprints.size(), cues.size(),
				])
			return succeeded(case, "%d cues audible, stereo, %d distinct waveforms" % [
				cues.size(), fingerprints.size(),
			])
		&"loops_fade_at_the_seam_without_clipping":
			var bad: Array[String] = []
			for cue in cues:
				var stream: AudioStreamWAV = MusicSynth.stream_for(cue.score)
				if stream == null:
					return fail(case, "%s rendered no stream" % cue.id)
				if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
					bad.append("%s:loop_mode" % cue.id)
				elif stream.loop_end <= 0 or stream.loop_end > stream.data.size() / 4:
					bad.append("%s:loop_end" % cue.id)
				var m := _metrics(stream)
				if float(m["peak"]) > 0.995:
					bad.append("%s:clipped" % cue.id)
				if float(m["edge"]) > float(m["rms"]) * 0.30:
					bad.append("%s:seam" % cue.id)
			if not bad.is_empty():
				return fail(case, str(bad))
			return succeeded(case, "%d cues unclipped with a faded loop seam" % cues.size())
	return fail(case, "unhandled case")


func _cues() -> Array:
	var dir := DirAccess.open(CUE_DIR)
	var out: Array = []
	if dir == null:
		return out
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var cue := load(CUE_DIR + "/" + file)
		if cue != null:
			out.append(cue)
	out.sort_custom(func(a, b) -> bool: return String(a.id) < String(b.id))
	return out


## Waveform facts a meter could show: overall RMS, peak, stereo difference and
## the RMS of the first/last 20 ms (which the synth fades for a click-free loop).
func _metrics(stream: AudioStreamWAV) -> Dictionary:
	var data := stream.data
	var frames: int = data.size() / 4
	# 2 ms, not the full 20 ms fade: the property that prevents a loop click is
	# that the boundary samples themselves are near zero, not that a whole
	# 20 ms window is quiet (it is a ramp, so its RMS is naturally ~0.5x).
	var edge_frames: int = mini(int(MusicSynth.RATE * 0.002), frames / 4)
	var sum_sq := 0.0
	var side_sq := 0.0
	var edge_sq := 0.0
	var peak := 0.0
	for i: int in range(frames):
		var l := float(data.decode_s16(i * 4)) / 32767.0
		var r := float(data.decode_s16(i * 4 + 2)) / 32767.0
		var mid := (l + r) * 0.5
		sum_sq += mid * mid
		var diff := (l - r) * 0.5
		side_sq += diff * diff
		peak = maxf(peak, maxf(absf(l), absf(r)))
		if i < edge_frames or i >= frames - edge_frames:
			edge_sq += mid * mid
	return {
		"rms": sqrt(sum_sq / maxf(frames, 1)),
		"side": sqrt(side_sq / maxf(frames, 1)),
		"edge": sqrt(edge_sq / maxf(edge_frames * 2, 1)),
		"peak": peak,
	}
