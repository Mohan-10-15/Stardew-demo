class_name AudioDefinition
extends Resource
## One sound, as data. The stream is synthesised from the wave fields rather
## than loaded from a file: no CC0 audio pack can be downloaded here, and
## `docs/AUDIO_GUIDE.md` explicitly permits generated audio.
##
## Content is data: adding a sound is a new `.tres` in `resources/audio/sounds/`,
## never a new branch in the manager.

## Unique id the manager and the signal map use.
@export var id: StringName = &""
## Bus to play on: Music, SFX, Ambient or UI.
@export_enum("Music", "SFX", "Ambient", "UI") var bus: int = 1
## Wave shape used by the synthesizer.
@export_enum("sine", "triangle", "square", "noise", "sweep", "chime", "pluck") var wave: int = 0
## Base frequency in Hz. Ignored by `noise`.
@export_range(40.0, 4000.0, 1.0) var frequency: float = 440.0
## Length of the sound in seconds.
@export_range(0.03, 8.0, 0.01) var duration: float = 0.2
## Exponential decay: 0 keeps a flat envelope, higher values end sooner.
@export_range(0.0, 12.0, 0.1) var decay: float = 4.0
## Overall level multiplier, applied to the PCM samples.
@export_range(0.0, 1.0, 0.01) var level: float = 0.5
## Pitch variation range, in ratios. 1/1 means a fixed pitch — footsteps and
## impacts want a range or they machine-gun.
@export_range(1.0, 2.0, 0.01) var pitch_max: float = 1.0
## A second harmonic for chimes and a sweep end frequency for sweeps.
@export_range(40.0, 8000.0, 1.0) var frequency_end: float = 880.0
## Loop short ambience beds instead of firing once.
@export var loop: bool = false


static func bus_name(value: int) -> StringName:
	return ["Music", "SFX", "Ambient", "UI"][clampi(value, 0, 3)]


static func wave_name(value: int) -> StringName:
	return ["sine", "triangle", "square", "noise", "sweep", "chime", "pluck"][clampi(value, 0, 6)]


func is_valid() -> bool:
	return not id.is_empty() and duration > 0.0 and level > 0.0 \
		and pitch_max >= 1.0 and frequency_end >= 40.0
