class_name VoiceBlips
extends RefCounted
## W4.5: a short tonal blip per villager, scaled by their profile's voice_pitch.
## No voice acting, no downloaded audio — just a cheap, original "speaking"
## sound so a typewriter line feels spoken rather than silent.

const RATE := 22050
const DURATION := 0.09

static var _cache: Dictionary = {}


static func stream_for(pitch: float, mood: StringName = &"neutral") -> AudioStreamWAV:
	var key := "%.2f:%s" % [pitch, String(mood)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(RATE * DURATION)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	var base := 220.0 * clampf(pitch, 0.6, 1.6)
	var bend := 1.0
	match mood:
		&"happy":
			bend = 1.15
		&"sad":
			bend = 0.85
		&"angry":
			bend = 1.3
	for i: int in range(frames):
		var u := float(i) / float(frames)
		var envelope := sin(PI * u) * exp(-2.0 * u)
		var f := base * lerpf(1.0, bend, u)
		var sample := sin(TAU * f * float(i) / float(RATE)) \
			+ 0.25 * sin(TAU * f * 2.0 * float(i) / float(RATE))
		var value := int(clampf(sample * envelope * 0.35, -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	_cache[key] = stream
	return stream


static func clear_cache() -> void:
	_cache.clear()
