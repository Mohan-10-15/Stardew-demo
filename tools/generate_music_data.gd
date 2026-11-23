extends SceneTree
## Writes the original cue set (W6.3/W6.4) from data. Each row is a real
## multi-voice score, not a single tone. Run:
##   Godot --headless --path . --script res://tools/generate_music_data.gd

const OUT := "res://resources/audio/cues/"
const CUE_SCRIPT := "res://resources/audio/music_cue.gd"
const SCORE_SCRIPT := "res://resources/audio/music_score.gd"

const CUES: Array[Dictionary] = [
	{"id": &"title", "name": "The Hollow Remembers", "bpm": 76, "bars": 28, "root": -9, "prog": [0,3,4,2], "mel": [0,-1,2,4,3,-1,2,1], "timbre": "glass_bell", "perc": 0.10, "prio": 10, "tags": ["menu"]},
	{"id": &"farm_spring", "name": "First Green", "bpm": 96, "bars": 28, "root": -7, "prog": [0,4,3,1], "mel": [0,2,4,-1,3,2,1,0], "timbre": "warm_pluck", "perc": 0.28, "prio": 20, "tags": ["farm","spring"]},
	{"id": &"farm_summer", "name": "Long Afternoon", "bpm": 104, "bars": 28, "root": -5, "prog": [0,1,4,3], "mel": [4,3,2,-1,1,2,4,3], "timbre": "flute", "perc": 0.32, "prio": 20, "tags": ["farm","summer"]},
	{"id": &"farm_autumn", "name": "Amber Rows", "bpm": 88, "bars": 28, "root": -8, "prog": [0,3,2,4], "mel": [2,1,0,-1,4,3,2,0], "timbre": "warm_pluck", "perc": 0.24, "prio": 20, "tags": ["farm","autumn"]},
	{"id": &"farm_winter", "name": "Quiet Frost", "bpm": 72, "bars": 28, "root": -11, "prog": [0,4,1,3], "mel": [0,-1,-1,2,1,0,-1,4], "timbre": "glass_bell", "perc": 0.08, "prio": 20, "tags": ["farm","winter"]},
	{"id": &"farm_night", "name": "Lantern Light", "bpm": 74, "bars": 28, "root": -9, "prog": [0,2,3,4], "mel": [0,1,2,-1,4,-1,2,0], "timbre": "soft_pad", "perc": 0.06, "prio": 22, "tags": ["farm","night"]},
	{"id": &"village_day", "name": "The Square Wakes", "bpm": 100, "bars": 28, "root": -4, "prog": [0,3,1,4], "mel": [2,4,3,2,-1,1,0,2], "timbre": "flute", "perc": 0.30, "prio": 24, "tags": ["village","day"]},
	{"id": &"village_night", "name": "Cottage Glow", "bpm": 70, "bars": 28, "root": -7, "prog": [0,4,2,3], "mel": [0,-1,1,2,4,-1,3,2], "timbre": "soft_pad", "perc": 0.05, "prio": 26, "tags": ["village","night"]},
	{"id": &"forest_edge", "name": "Under the Boughs", "bpm": 84, "bars": 28, "root": -6, "prog": [0,1,3,4], "mel": [4,2,-1,1,0,-1,2,3], "timbre": "flute", "perc": 0.16, "prio": 24, "tags": ["forest"]},
	{"id": &"pond", "name": "Water Remembering", "bpm": 78, "bars": 28, "root": -10, "prog": [0,4,3,1], "mel": [0,2,-1,4,3,-1,2,1], "timbre": "glass_bell", "perc": 0.10, "prio": 24, "tags": ["pond"]},
	{"id": &"upper_mines", "name": "Stone Under Stone", "bpm": 82, "bars": 28, "root": -12, "prog": [0,3,1,4], "mel": [0,-1,1,2,0,-1,3,2], "timbre": "soft_pad", "perc": 0.20, "prio": 30, "tags": ["mines"]},
	{"id": &"deep_mines", "name": "The Deep Ember", "bpm": 90, "bars": 28, "root": -14, "prog": [0,4,2,3], "mel": [2,1,0,-1,4,3,2,0], "timbre": "soft_pad", "perc": 0.26, "prio": 32, "tags": ["mines","deep"]},
	{"id": &"combat", "name": "Ash and Steel", "bpm": 132, "bars": 28, "root": -10, "prog": [0,3,0,4], "mel": [0,2,3,4,3,2,1,0], "timbre": "warm_pluck", "perc": 0.45, "prio": 50, "tags": ["combat"]},
	{"id": &"festival", "name": "Every Gate Open", "bpm": 112, "bars": 28, "root": -3, "prog": [0,4,1,3], "mel": [4,3,2,4,-1,2,1,0], "timbre": "flute", "perc": 0.42, "prio": 44, "tags": ["festival"]},
	{"id": &"cutscene", "name": "A Story Told", "bpm": 80, "bars": 28, "root": -8, "prog": [0,2,4,3], "mel": [0,1,2,4,-1,3,2,0], "timbre": "glass_bell", "perc": 0.08, "prio": 60, "tags": ["cutscene"]},
	{"id": &"mending", "name": "The Heartstone Whole", "bpm": 72, "bars": 32, "root": -5, "prog": [0,4,3,1], "mel": [0,2,4,2,1,0,-1,4], "timbre": "glass_bell", "perc": 0.06, "prio": 70, "tags": ["story","mending"]},
	{"id": &"credits", "name": "The Long Afternoon", "bpm": 76, "bars": 32, "root": -7, "prog": [0,3,4,2], "mel": [4,3,2,1,0,-1,2,4], "timbre": "flute", "perc": 0.12, "prio": 68, "tags": ["credits"]},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var cue_script := load(CUE_SCRIPT) as GDScript
	var score_script := load(SCORE_SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in CUES:
		var score: Object = score_script.new()
		score.set("id", StringName(String(spec["id"]) + "_score"))
		score.set("display_name", String(spec["name"]))
		score.set("tempo_bpm", int(spec["bpm"]))
		score.set("bars", int(spec["bars"]))
		score.set("root", int(spec["root"]))
		score.set("progression", _ints(spec["prog"]))
		score.set("melody", _ints(spec["mel"]))
		score.set("timbre", String(spec["timbre"]))
		score.set("percussion", float(spec["perc"]))
		if not bool(score.call("is_valid")):
			printerr("[generate_music_data] invalid score %s" % spec["id"])
			errors += 1
			continue
		var cue: Object = cue_script.new()
		cue.set("id", spec["id"])
		cue.set("display_name", String(spec["name"]))
		cue.set("score", score)
		cue.set("priority", int(spec["prio"]))
		var tags: Array[StringName] = []
		for tag: String in (spec["tags"] as Array):
			tags.append(StringName(tag))
		cue.set("tags", tags)
		if not bool(cue.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(cue, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_music_data] wrote %d cues" % CUES.size())
	quit(1 if errors > 0 else 0)


func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out
