extends SceneTree
## Writes 12 villager profiles + the player profile (W4.2).
##   Godot --headless --path . --script res://tools/generate_character_profiles.gd

const OUT := "res://resources/npc/profiles/"
const SCRIPT := "res://resources/npc/character_profile.gd"
const MODELS := "res://assets/models/kaykit/Characters/"

const PROFILES: Array[Dictionary] = [
	{"id": &"mira", "name": "Mira", "model": "Knight.fbx", "build": 1, "head": 1.22, "hair": &"long_braid", "hair_c": "9b5a2e", "eye": "4f8fa8", "skin": "f0c6a8", "pal": ["2f7d6b","e8dcc0","c96f52"], "acc": &"seed_pouch", "pitch": 1.06},
	{"id": &"bram", "name": "Bram", "model": "Barbarian.fbx", "build": 2, "head": 1.12, "hair": &"short_tousled", "hair_c": "4a2f20", "eye": "6b4a2e", "skin": "d9a478", "pal": ["7a4a2e","c9b48a","39424a"], "acc": &"hammer", "pitch": 0.78},
	{"id": &"fen", "name": "Fen", "model": "Rogue.fbx", "build": 0, "head": 1.26, "hair": &"ponytail", "hair_c": "2d2a33", "eye": "8a6fb0", "skin": "e8bb9a", "pal": ["3d3b55","8c7aa8","c8b48a"], "acc": &"firewood", "pitch": 1.12},
	{"id": &"odette", "name": "Odette", "model": "Mage.fbx", "build": 1, "head": 1.30, "hair": &"long_wavy", "hair_c": "b9c7d8", "eye": "6fa8c9", "skin": "f2d0b6", "pal": ["6d8fb8","dbe6f0","9c7fb0"], "acc": &"almanac", "pitch": 1.18},
	{"id": &"sable", "name": "Sable", "model": "Knight.fbx", "build": 2, "head": 1.14, "hair": &"bob", "hair_c": "6d3b24", "eye": "b06f3a", "skin": "d9a07a", "pal": ["8a5a34","d8c9a8","4a6b52"], "acc": &"fence_post", "pitch": 0.86},
	{"id": &"aurel", "name": "Aurel", "model": "Knight.fbx", "build": 4, "head": 1.10, "hair": &"swept", "hair_c": "c9a84a", "eye": "4a7a9c", "skin": "eec3a0", "pal": ["b08a3a","e8dfc0","3f5f7a"], "acc": &"ledger", "pitch": 0.92},
	{"id": &"lyra", "name": "Lyra", "model": "Rogue.fbx", "build": 0, "head": 1.28, "hair": &"twin_tails", "hair_c": "a34a6a", "eye": "d0a24a", "skin": "f0c4a4", "pal": ["a24a6a","f0d8c0","6a8f70"], "acc": &"flute", "pitch": 1.24},
	{"id": &"cassia", "name": "Cassia", "model": "Mage.fbx", "build": 3, "head": 1.34, "hair": &"long_straight", "hair_c": "3d2a4a", "eye": "8f6fb0", "skin": "e6c0a8", "pal": ["4d3a6a","c8b8d8","8a9c6a"], "acc": &"notes", "pitch": 1.08},
	{"id": &"elke", "name": "Elke", "model": "RogueHooded.fbx", "build": 0, "head": 1.30, "hair": &"short_curly", "hair_c": "c98a4a", "eye": "5fa87a", "skin": "f2cba8", "pal": ["6fa86a","e8dcae","c98a4a"], "acc": &"watering_can", "pitch": 1.16},
	{"id": &"garrick", "name": "Garrick", "model": "Barbarian.fbx", "build": 4, "head": 1.08, "hair": &"bald_beard", "hair_c": "5a4030", "eye": "a04a3a", "skin": "c99872", "pal": ["5a4a3a","b8a080","8a3f34"], "acc": &"shield", "pitch": 0.70},
	{"id": &"halda", "name": "Halda", "model": "RogueHooded.fbx", "build": 3, "head": 1.24, "hair": &"bun", "hair_c": "d8d2c4", "eye": "7a9c6a", "skin": "e8c2a0", "pal": ["9a9a8a","e8e2d2","7a9c6a"], "acc": &"story_book", "pitch": 1.02},
	{"id": &"dorian", "name": "Dorian", "model": "Knight.fbx", "build": 2, "head": 1.18, "hair": &"short_neat", "hair_c": "2f3a4a", "eye": "c98a4a", "skin": "e0b6a0", "pal": ["3a4a6a","d8c8a8","a05a4a"], "acc": &"travel_bag", "pitch": 0.96},
	{"id": &"player", "name": "The Farmer", "model": "Rogue.fbx", "build": 1, "head": 1.20, "hair": &"short_messy", "hair_c": "6a4128", "eye": "5a9c8a", "skin": "eec6a8", "pal": ["3f8a70","d8e0d0","a86a48"], "acc": &"hoe", "pitch": 1.0},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in PROFILES:
		var profile: Object = script.new()
		profile.set("id", spec["id"])
		profile.set("display_name", spec["name"])
		profile.set("model", MODELS + String(spec["model"]))
		profile.set("build", int(spec["build"]))
		profile.set("head_scale", float(spec["head"]))
		profile.set("hair_style", spec["hair"])
		profile.set("hair_color", Color.html(String(spec["hair_c"])))
		profile.set("eye_color", Color.html(String(spec["eye"])))
		profile.set("skin_tone", Color.html(String(spec["skin"])))
		var palette: Array[Color] = []
		for hex: String in (spec["pal"] as Array):
			palette.append(Color.html(hex))
		profile.set("palette", palette)
		profile.set("accessory", spec["acc"])
		profile.set("voice_pitch", float(spec["pitch"]))
		profile.set("spring_hair", bool(spec.get("spring", false)))
		if not bool(profile.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(profile, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_character_profiles] wrote %d profiles" % PROFILES.size())
	quit(1 if errors > 0 else 0)
