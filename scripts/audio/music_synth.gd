class_name MusicSynth
extends RefCounted
## Renders a MusicScore into a seamless stereo AudioStreamWAV. Original output
## only: three voices (bass, chord pad, melody), an ADSR envelope, a soft noise
## percussion bed and the Heartstone leitmotif on every fourth bar.

const RATE := 22050
const PEAK := 0.85

static var _cache: Dictionary = {}


static func stream_for(score: MusicScore) -> AudioStreamWAV:
	if score == null or not score.is_valid():
		return null
	if _cache.has(score.id):
		return _cache[score.id]
	var seconds_per_beat := 60.0 / float(score.tempo_bpm)
	var total_beats := float(score.bars) * 4.0
	var seconds := seconds_per_beat * total_beats
	var frames := int(seconds * RATE)
	var pcm := PackedByteArray()
	pcm.resize(frames * 4)  # stereo 16-bit
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(String(score.id)) & 0x7FFFFFFF)
	var peak := 0.0
	var raw := PackedFloat32Array()
	raw.resize(frames * 2)
	for i: int in range(frames):
		var t := float(i) / float(RATE)
		var beat := t / seconds_per_beat
		var bar: int = int(beat / 4.0)
		var beat_in_bar: int = int(beat) % 4
		var chord_degree: int = score.progression[bar % score.progression.size()]
		var chord_root := _freq(score, chord_degree)
		var bar_phase := fmod(beat, 4.0) / 4.0
		var beat_phase := fmod(beat, 1.0)

		# Bass: one root note per beat with a short pluck envelope.
		var bass := sin(TAU * chord_root * 0.5 * t) \
			* exp(-2.5 * beat_phase) * 0.30

		# Pad: the chord's third and fifth, swelling across the bar.
		var third := _freq(score, (chord_degree + 2) % score.scale.size())
		var fifth := _freq(score, (chord_degree + 4) % score.scale.size())
		var pad_env := sin(PI * clampf(bar_phase, 0.0, 1.0))
		var pad := (sin(TAU * third * t) + sin(TAU * fifth * t)) * 0.12 * pad_env

		# Melody: two notes per beat from the pattern; the leitmotif takes over
		# every fourth bar so the same five notes recur across every cue.
		var step: int = int(beat * 2.0)
		var degree: int = -1
		if bar % 4 == 3:
			var motif_index: int = int(fmod(beat * 1.0, float(score.leitmotif.size())))
			degree = score.leitmotif[motif_index]
		else:
			degree = score.melody[step % score.melody.size()]
		var melody := 0.0
		if degree >= 0:
			var f := _freq(score, degree % score.scale.size())
			var note_phase := fmod(beat * 2.0, 1.0)
			var adsr := _adsr(note_phase)
			melody = _timbre(f, t, score.timbre) * adsr * 0.34

		# Percussion: a soft filtered noise tick on beats 0 and 2.
		var perc := 0.0
		if beat_in_bar == 0 or beat_in_bar == 2:
			perc = rng.randf_range(-1.0, 1.0) * exp(-18.0 * beat_phase) \
				* score.percussion * 0.10

		var mono := bass + pad + melody + perc
		# Seam: fade the first and last 20 ms so the loop point cannot click.
		var edge := mini(i, frames - 1 - i)
		var fade := clampf(float(edge) / (RATE * 0.02), 0.0, 1.0)
		mono *= fade
		# Slight stereo spread on the pad/melody only.
		var left := mono + pad * 0.08
		var right := mono - pad * 0.08
		raw[i * 2] = left
		raw[i * 2 + 1] = right
		peak = maxf(peak, maxf(absf(left), absf(right)))
	for i: int in range(frames * 2):
		var scale_value := 1.0 if peak <= 0.0001 else PEAK / peak
		var value := int(clampf(raw[i] * scale_value, -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	stream.data = pcm
	if score.loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# An unset loop_end means a zero-length loop region in some builds, which
		# stops playback at the first wrap. Name the whole buffer explicitly.
		stream.loop_begin = 0
		stream.loop_end = frames
	_cache[score.id] = stream
	return stream


static func duration_seconds(score: MusicScore) -> float:
	return 60.0 / float(score.tempo_bpm) * float(score.bars) * 4.0


static func _freq(score: MusicScore, degree: int) -> float:
	var semitone: int = score.root + score.scale[degree % score.scale.size()]
	return 220.0 * pow(2.0, float(semitone) / 12.0)


static func _adsr(phase: float) -> float:
	if phase < 0.08:
		return phase / 0.08
	if phase < 0.35:
		return 1.0 - 0.3 * (phase - 0.08) / 0.27
	return 0.7 * exp(-3.0 * (phase - 0.35))


static func _timbre(f: float, t: float, kind: String) -> float:
	match kind:
		"soft_pad":
			return sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t)
		"flute":
			return sin(TAU * f * t) + 0.18 * sin(TAU * f * 3.0 * t)
		"glass_bell":
			return sin(TAU * f * t) + 0.45 * sin(TAU * f * 3.5 * t)
		_:
			return sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t) \
				+ 0.12 * sin(TAU * f * 3.0 * t)


static func clear_cache() -> void:
	_cache.clear()
