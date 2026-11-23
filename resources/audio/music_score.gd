class_name MusicScore
extends Resource
## One original cue as data. The renderer turns this into a stereo loop, so a
## new cue is a .tres row rather than a new audio file to licence.

@export var id: StringName = &""
@export var display_name: String = ""
@export_range(40, 200, 1) var tempo_bpm: int = 92
@export_range(4, 64, 4) var bars: int = 16
## Root note as a semitone offset from A4 (0 = A4).
@export_range(-24, 24, 1) var root: int = -9
## Diatonic scale steps in semitones from the root.
@export var scale: Array[int] = [0, 2, 4, 7, 9]
## Chords as scale degrees (0-based) — one chord per bar, cycled.
@export var progression: Array[int] = [0, 3, 4, 0]
## Melody as scale degrees; -1 is a rest. Cycled across bars.
@export var melody: Array[int] = [0, -1, 2, 4, -1, 2, 1, 0]
## The Heartstone leitmotif, in scale degrees. Every cue carries it.
@export var leitmotif: Array[int] = [0, 2, 4, 2, 1]
@export_enum("warm_pluck", "soft_pad", "flute", "glass_bell") var timbre: String = "warm_pluck"
@export_range(0.0, 1.0, 0.01) var percussion: float = 0.25
@export var loop: bool = true
@export var mood_tags: Array[StringName] = []


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and tempo_bpm >= 40 and bars >= 4 and not scale.is_empty() \
		and not progression.is_empty() and not melody.is_empty() \
		and leitmotif.size() >= 4
