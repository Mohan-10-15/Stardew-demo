extends SceneTree
## Headless tool: writes the synthesised sound definitions into
## `resources/audio/sounds/`.
##
##     godot --headless --path . --script res://tools/generate_audio_data.gd
##
## Every sound is original generated audio — no third-party file, no licence
## question. The wave fields are the content; `AudioSynth` turns them into an
## AudioStreamWav at runtime and caches it per definition.

const OUTPUT_DIR := "res://resources/audio/sounds/"
## Loaded by path: a `--script` run compiles before new global classes are
## registered, so naming `AudioDefinition` here would fail until an import ran.
const DEFINITION_SCRIPT := "res://resources/audio/audio_definition.gd"

const SFX := 1
const MUSIC := 0
const AMBIENT := 2
const UI := 3

## wave indices: sine=0 triangle=1 square=2 noise=3 sweep=4 chime=5 pluck=6
const SOUNDS: Array[Dictionary] = [
	{"id": &"ui_move", "bus": UI, "wave": 1, "frequency": 620, "duration": 0.06, "decay": 9, "level": 0.18},
	{"id": &"ui_confirm", "bus": UI, "wave": 5, "frequency": 660, "frequency_end": 990, "duration": 0.16, "decay": 6, "level": 0.28},
	{"id": &"ui_cancel", "bus": UI, "wave": 5, "frequency": 440, "frequency_end": 260, "duration": 0.14, "decay": 7, "level": 0.24},
	{"id": &"ui_open", "bus": UI, "wave": 1, "frequency": 380, "frequency_end": 560, "duration": 0.12, "decay": 6, "level": 0.22},
	{"id": &"ui_error", "bus": UI, "wave": 2, "frequency": 180, "duration": 0.18, "decay": 5, "level": 0.22},

	{"id": &"footstep_grass", "bus": SFX, "wave": 3, "frequency": 900, "duration": 0.09, "decay": 9, "level": 0.14, "pitch_max": 1.3},
	{"id": &"footstep_wood", "bus": SFX, "wave": 6, "frequency": 220, "duration": 0.10, "decay": 11, "level": 0.20, "pitch_max": 1.25},
	{"id": &"footstep_stone", "bus": SFX, "wave": 2, "frequency": 150, "duration": 0.07, "decay": 13, "level": 0.15, "pitch_max": 1.2},
	{"id": &"footstep_dirt", "bus": SFX, "wave": 3, "frequency": 600, "duration": 0.09, "decay": 10, "level": 0.13, "pitch_max": 1.3},
	{"id": &"footstep_grass_b", "bus": SFX, "wave": 3, "frequency": 980, "duration": 0.08, "decay": 10, "level": 0.13, "pitch_max": 1.35},
	{"id": &"footstep_grass_c", "bus": SFX, "wave": 3, "frequency": 820, "duration": 0.10, "decay": 9, "level": 0.14, "pitch_max": 1.4},
	{"id": &"footstep_wood_b", "bus": SFX, "wave": 6, "frequency": 260, "duration": 0.09, "decay": 12, "level": 0.19, "pitch_max": 1.3},
	{"id": &"footstep_wood_c", "bus": SFX, "wave": 6, "frequency": 190, "duration": 0.11, "decay": 11, "level": 0.20, "pitch_max": 1.25},
	{"id": &"footstep_stone_b", "bus": SFX, "wave": 2, "frequency": 175, "duration": 0.08, "decay": 13, "level": 0.15, "pitch_max": 1.25},
	{"id": &"footstep_stone_c", "bus": SFX, "wave": 2, "frequency": 135, "duration": 0.07, "decay": 14, "level": 0.16, "pitch_max": 1.2},
	{"id": &"footstep_dirt_b", "bus": SFX, "wave": 3, "frequency": 680, "duration": 0.10, "decay": 10, "level": 0.13, "pitch_max": 1.35},
	{"id": &"footstep_dirt_c", "bus": SFX, "wave": 3, "frequency": 520, "duration": 0.09, "decay": 11, "level": 0.14, "pitch_max": 1.4},

	{"id": &"hoe_till", "bus": SFX, "wave": 3, "frequency": 520, "duration": 0.18, "decay": 7, "level": 0.32, "pitch_max": 1.15},
	{"id": &"water_pour", "bus": SFX, "wave": 3, "frequency": 1600, "duration": 0.32, "decay": 3, "level": 0.16},
	{"id": &"seed_plant", "bus": SFX, "wave": 6, "frequency": 480, "duration": 0.12, "decay": 9, "level": 0.20},
	{"id": &"crop_harvest", "bus": SFX, "wave": 5, "frequency": 720, "frequency_end": 1080, "duration": 0.22, "decay": 6, "level": 0.28},
	{"id": &"axe_hit", "bus": SFX, "wave": 6, "frequency": 170, "duration": 0.20, "decay": 10, "level": 0.36, "pitch_max": 1.2},
	{"id": &"pickaxe_hit", "bus": SFX, "wave": 2, "frequency": 240, "duration": 0.16, "decay": 12, "level": 0.30, "pitch_max": 1.18},
	{"id": &"scythe_swing", "bus": SFX, "wave": 4, "frequency": 900, "frequency_end": 300, "duration": 0.18, "decay": 6, "level": 0.20},

	{"id": &"farming_fail", "bus": SFX, "wave": 2, "frequency": 130, "frequency_end": 90, "duration": 0.16, "decay": 6, "level": 0.24},
	{"id": &"gather_hit", "bus": SFX, "wave": 6, "frequency": 300, "duration": 0.12, "decay": 10, "level": 0.26, "pitch_max": 1.2},
	{"id": &"gather_collect", "bus": SFX, "wave": 5, "frequency": 880, "frequency_end": 1320, "duration": 0.18, "decay": 7, "level": 0.26},
	{"id": &"gather_fail", "bus": SFX, "wave": 2, "frequency": 120, "duration": 0.14, "decay": 8, "level": 0.22},

	{"id": &"npc_talk", "bus": SFX, "wave": 1, "frequency": 520, "frequency_end": 610, "duration": 0.10, "decay": 8, "level": 0.16, "pitch_max": 1.25},
	{"id": &"npc_gift_liked", "bus": SFX, "wave": 5, "frequency": 660, "frequency_end": 990, "duration": 0.28, "decay": 5, "level": 0.30},
	{"id": &"npc_gift_disliked", "bus": SFX, "wave": 2, "frequency": 190, "frequency_end": 120, "duration": 0.24, "decay": 6, "level": 0.26},
	{"id": &"gift_refused", "bus": SFX, "wave": 2, "frequency": 140, "duration": 0.16, "decay": 7, "level": 0.24},
	{"id": &"romance_refused", "bus": SFX, "wave": 2, "frequency": 200, "duration": 0.20, "decay": 6, "level": 0.24},
	{"id": &"propose_refused", "bus": SFX, "wave": 2, "frequency": 260, "frequency_end": 130, "duration": 0.26, "decay": 6, "level": 0.26},
	{"id": &"romance_started", "bus": SFX, "wave": 5, "frequency": 523, "frequency_end": 784, "duration": 0.55, "decay": 3, "level": 0.32},
	{"id": &"marriage", "bus": MUSIC, "wave": 5, "frequency": 523, "frequency_end": 1046, "duration": 1.2, "decay": 2, "level": 0.36},

	{"id": &"quest_accepted", "bus": SFX, "wave": 5, "frequency": 585, "frequency_end": 880, "duration": 0.34, "decay": 5, "level": 0.30},
	{"id": &"quest_completed", "bus": MUSIC, "wave": 5, "frequency": 659, "frequency_end": 1318, "duration": 0.7, "decay": 3, "level": 0.34},
	{"id": &"quest_accept_refused", "bus": SFX, "wave": 2, "frequency": 160, "duration": 0.20, "decay": 6, "level": 0.24},
	{"id": &"quest_turnin_refused", "bus": SFX, "wave": 2, "frequency": 210, "duration": 0.22, "decay": 6, "level": 0.24},
	{"id": &"dialogue_failed", "bus": SFX, "wave": 2, "frequency": 300, "frequency_end": 180, "duration": 0.14, "decay": 8, "level": 0.20},
	{"id": &"stamina_empty", "bus": SFX, "wave": 2, "frequency": 110, "duration": 0.24, "decay": 6, "level": 0.26},
	{"id": &"fish_cast", "bus": SFX, "wave": 4, "frequency": 900, "frequency_end": 340, "duration": 0.22, "decay": 6, "level": 0.18},
	{"id": &"fish_bite", "bus": SFX, "wave": 5, "frequency": 880, "frequency_end": 1320, "duration": 0.14, "decay": 8, "level": 0.30},
	{"id": &"fish_caught", "bus": SFX, "wave": 5, "frequency": 660, "frequency_end": 1320, "duration": 0.42, "decay": 4, "level": 0.30},
	{"id": &"fish_escaped", "bus": SFX, "wave": 2, "frequency": 240, "frequency_end": 130, "duration": 0.24, "decay": 6, "level": 0.24},
	{"id": &"craft_ok", "bus": SFX, "wave": 5, "frequency": 520, "frequency_end": 1040, "duration": 0.30, "decay": 5, "level": 0.28},
	{"id": &"craft_fail", "bus": SFX, "wave": 2, "frequency": 200, "duration": 0.18, "decay": 7, "level": 0.22},
	{"id": &"animal_feed", "bus": SFX, "wave": 1, "frequency": 420, "frequency_end": 560, "duration": 0.16, "decay": 7, "level": 0.20},
	{"id": &"animal_product", "bus": SFX, "wave": 5, "frequency": 700, "frequency_end": 1050, "duration": 0.24, "decay": 6, "level": 0.26},
	{"id": &"animal_refused", "bus": SFX, "wave": 2, "frequency": 170, "duration": 0.16, "decay": 7, "level": 0.22},
	{"id": &"machine_placed", "bus": SFX, "wave": 6, "frequency": 260, "duration": 0.22, "decay": 8, "level": 0.28},
	{"id": &"machine_load", "bus": SFX, "wave": 1, "frequency": 340, "frequency_end": 460, "duration": 0.18, "decay": 7, "level": 0.22},
	{"id": &"machine_done", "bus": SFX, "wave": 5, "frequency": 520, "frequency_end": 780, "duration": 0.28, "decay": 6, "level": 0.26},
	{"id": &"machine_refused", "bus": SFX, "wave": 2, "frequency": 190, "duration": 0.16, "decay": 7, "level": 0.22},
	{"id": &"cook_done", "bus": SFX, "wave": 5, "frequency": 600, "frequency_end": 900, "duration": 0.34, "decay": 5, "level": 0.26},
	{"id": &"cook_refused", "bus": SFX, "wave": 2, "frequency": 230, "duration": 0.16, "decay": 7, "level": 0.22},
	{"id": &"machine_empty", "bus": SFX, "wave": 2, "frequency": 280, "duration": 0.14, "decay": 8, "level": 0.20},
	{"id": &"animal_bought", "bus": SFX, "wave": 5, "frequency": 480, "frequency_end": 720, "duration": 0.3, "decay": 5, "level": 0.26},
	{"id": &"building_placed", "bus": SFX, "wave": 6, "frequency": 200, "frequency_end": 320, "duration": 0.34, "decay": 6, "level": 0.30},
	{"id": &"building_upgraded", "bus": SFX, "wave": 5, "frequency": 520, "frequency_end": 1040, "duration": 0.4, "decay": 5, "level": 0.28},
	{"id": &"building_refused", "bus": SFX, "wave": 2, "frequency": 150, "duration": 0.2, "decay": 7, "level": 0.22},
	{"id": &"level_up", "bus": MUSIC, "wave": 5, "frequency": 784, "frequency_end": 1568, "duration": 0.8, "decay": 3, "level": 0.34},

	{"id": &"shop_buy", "bus": SFX, "wave": 5, "frequency": 740, "frequency_end": 1120, "duration": 0.18, "decay": 7, "level": 0.26},
	{"id": &"shop_sell", "bus": SFX, "wave": 5, "frequency": 620, "frequency_end": 930, "duration": 0.18, "decay": 7, "level": 0.26},
	{"id": &"trade_refused", "bus": SFX, "wave": 2, "frequency": 150, "duration": 0.18, "decay": 6, "level": 0.24},
	{"id": &"tool_broken", "bus": SFX, "wave": 3, "frequency": 1100, "duration": 0.30, "decay": 5, "level": 0.30},

	{"id": &"day_start", "bus": MUSIC, "wave": 5, "frequency": 392, "frequency_end": 784, "duration": 0.9, "decay": 3, "level": 0.28},
	{"id": &"rain_loop", "bus": AMBIENT, "wave": 3, "frequency": 2200, "duration": 2.0, "decay": 0.0, "level": 0.10, "loop": true},
	{"id": &"wind_loop", "bus": AMBIENT, "wave": 3, "frequency": 400, "duration": 2.0, "decay": 0.0, "level": 0.08, "loop": true},
	{"id": &"night_loop", "bus": AMBIENT, "wave": 3, "frequency": 180, "duration": 2.0, "decay": 0.0, "level": 0.07, "loop": true},
	# W6.5 layered ambience beds and one-shots. All original synthesised noise.
	{"id": &"birds_loop", "bus": AMBIENT, "wave": 3, "frequency": 1800, "duration": 2.5, "decay": 0.0, "level": 0.05, "loop": true},
	{"id": &"crickets_loop", "bus": AMBIENT, "wave": 3, "frequency": 4200, "duration": 2.5, "decay": 0.0, "level": 0.05, "loop": true},
	{"id": &"pond_loop", "bus": AMBIENT, "wave": 3, "frequency": 700, "duration": 3.0, "decay": 0.0, "level": 0.06, "loop": true},
	{"id": &"cave_loop", "bus": AMBIENT, "wave": 3, "frequency": 120, "duration": 3.0, "decay": 0.0, "level": 0.07, "loop": true},
	{"id": &"storm_loop", "bus": AMBIENT, "wave": 3, "frequency": 2600, "duration": 2.0, "decay": 0.0, "level": 0.12, "loop": true},
	{"id": &"snow_loop", "bus": AMBIENT, "wave": 3, "frequency": 900, "duration": 2.5, "decay": 0.0, "level": 0.05, "loop": true},
	{"id": &"bird_chirp", "bus": AMBIENT, "wave": 5, "frequency": 2400, "frequency_end": 3200, "duration": 0.18, "decay": 5, "level": 0.12},
	{"id": &"cricket_chirp", "bus": AMBIENT, "wave": 5, "frequency": 4800, "duration": 0.12, "decay": 7, "level": 0.10},
	{"id": &"cave_drip", "bus": AMBIENT, "wave": 5, "frequency": 900, "frequency_end": 300, "duration": 0.22, "decay": 6, "level": 0.12},
	{"id": &"village_theme", "bus": MUSIC, "wave": 5, "frequency": 330, "frequency_end": 660, "duration": 4.0, "decay": 0.0, "level": 0.18, "loop": true},
	{"id": &"farm_theme", "bus": MUSIC, "wave": 5, "frequency": 262, "frequency_end": 523, "duration": 4.0, "decay": 0.0, "level": 0.18, "loop": true},
	{"id": &"forest_theme", "bus": MUSIC, "wave": 5, "frequency": 294, "frequency_end": 587, "duration": 4.0, "decay": 0.0, "level": 0.18, "loop": true},
	{"id": &"title_theme", "bus": MUSIC, "wave": 5, "frequency": 349, "frequency_end": 698, "duration": 4.0, "decay": 0.0, "level": 0.16, "loop": true},
	{"id": &"beach_theme", "bus": MUSIC, "wave": 5, "frequency": 247, "frequency_end": 494, "duration": 4.0, "decay": 0.0, "level": 0.16, "loop": true},
	{"id": &"mines_theme", "bus": MUSIC, "wave": 3, "frequency": 140, "duration": 4.0, "decay": 0.0, "level": 0.14, "loop": true},
	{"id": &"combat_theme", "bus": MUSIC, "wave": 2, "frequency": 196, "duration": 4.0, "decay": 0.0, "level": 0.16, "loop": true},
	{"id": &"festival_theme", "bus": MUSIC, "wave": 5, "frequency": 440, "frequency_end": 880, "duration": 4.0, "decay": 0.0, "level": 0.18, "loop": true},
	{"id": &"cutscene_theme", "bus": MUSIC, "wave": 5, "frequency": 262, "frequency_end": 523, "duration": 4.0, "decay": 0.0, "level": 0.14, "loop": true},
	{"id": &"winter_theme", "bus": MUSIC, "wave": 5, "frequency": 233, "frequency_end": 466, "duration": 4.0, "decay": 0.0, "level": 0.16, "loop": true},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var errors := 0
	var seen: Dictionary = {}
	var script := load(DEFINITION_SCRIPT) as GDScript
	if script == null:
		printerr("[generate_audio_data] cannot load the definition script")
		quit(1)
		return
	for spec: Dictionary in SOUNDS:
		var definition: Object = script.new()
		definition.id = spec["id"]
		definition.bus = int(spec["bus"])
		definition.wave = int(spec["wave"])
		definition.frequency = float(spec.get("frequency", 440.0))
		definition.frequency_end = float(spec.get("frequency_end", 880.0))
		definition.duration = float(spec.get("duration", 0.2))
		definition.decay = float(spec.get("decay", 5.0))
		definition.level = float(spec.get("level", 0.3))
		definition.pitch_max = float(spec.get("pitch_max", 1.0))
		definition.loop = bool(spec.get("loop", false))
		if not bool(definition.call("is_valid")):
			printerr("[generate_audio_data] invalid sound %s" % definition.id)
			errors += 1
			continue
		if seen.has(definition.id):
			printerr("[generate_audio_data] duplicate sound id %s" % definition.id)
			errors += 1
			continue
		seen[definition.id] = true
		var path := "%s%s.tres" % [OUTPUT_DIR, definition.id]
		if ResourceSaver.save(definition, path) != OK:
			printerr("[generate_audio_data] failed to write %s" % path)
			errors += 1
	print("[generate_audio_data] wrote %d sounds to %s" % [seen.size(), OUTPUT_DIR])
	quit(1 if errors > 0 else 0)
