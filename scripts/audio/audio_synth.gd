class_name AudioSynth
extends RefCounted
## Turns an [AudioDefinition] into a real AudioStreamWAV, once per definition.
##
## All sounds are original generated waveforms — no downloaded asset, no licence
## to log beyond the "generated" note in ASSET_LICENSES.md. A simple sample loop
## is enough for short cues; the point is that success and failure *sound*
## different, not that they are orchestral.

const RATE := 22050

static var _cache: Dictionary = {}


static func stream_for(definition: AudioDefinition) -> AudioStreamWAV:
	if definition == null:
		return null
	if _cache.has(definition.id):
		return _cache[definition.id]
	var frames := maxi(1, int(RATE * definition.duration))
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(definition.id))
	var wave := AudioDefinition.wave_name(definition.wave)
	var phase := 0.0
	for i: int in range(frames):
		var t := float(i) / float(RATE)
		var u := float(i) / float(frames)
		var envelope := exp(-definition.decay * u)
		var sample := 0.0
		match wave:
			&"sine":
				sample = sin(TAU * definition.frequency * t)
			&"triangle":
				phase = fmod(phase + definition.frequency / float(RATE), 1.0)
				sample = 4.0 * absf(phase - 0.5) - 1.0
			&"square":
				sample = 1.0 if sin(TAU * definition.frequency * t) >= 0.0 else -1.0
			&"noise":
				sample = rng.randf_range(-1.0, 1.0)
			&"sweep":
				var f := lerpf(definition.frequency, definition.frequency_end, u)
				sample = sin(TAU * f * t)
			&"chime":
				sample = 0.6 * sin(TAU * definition.frequency * t) \
					+ 0.4 * sin(TAU * definition.frequency_end * t)
			&"pluck":
				sample = sin(TAU * definition.frequency * t) \
					* exp(-7.0 * u) * (0.6 + 0.4 * sin(TAU * 3.0 * definition.frequency * t))
			_:
				sample = 0.0
		var value := int(clampf(sample * envelope * definition.level, -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	if definition.loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_cache[definition.id] = stream
	return stream


static func clear_cache() -> void:
	_cache.clear()
