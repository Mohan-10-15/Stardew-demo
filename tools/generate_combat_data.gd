extends SceneTree
## Headless tool: writes mine enemy definitions into `resources/combat/enemies/`.

const OUTPUT := "res://resources/combat/enemies/"
const SCRIPT_PATH := "res://resources/combat/enemy_data.gd"
const MODEL_DIR := "res://assets/models/kaykit/Characters/"

const ENEMIES: Array[Dictionary] = [
	{"id": &"cave_shade", "name": "Cave Shade", "model": "Rogue.fbx",
	 "tint": Color(0.28, 0.22, 0.42), "health": 55, "damage": 7, "speed": 2.4,
	 "range": 1.8, "cooldown": 1.3, "gold": 18, "ore": &"copper_ore"},
	{"id": &"cave_brute", "name": "Cave Brute", "model": "Barbarian.fbx",
	 "tint": Color(0.34, 0.20, 0.18), "health": 95, "damage": 12, "speed": 1.7,
	 "range": 2.0, "cooldown": 1.8, "gold": 30, "ore": &"iron_ore"},
	{"id": &"cave_stalker", "name": "Cave Stalker", "model": "RogueHooded.fbx",
	 "tint": Color(0.18, 0.30, 0.26), "health": 45, "damage": 9, "speed": 3.0,
	 "range": 1.6, "cooldown": 1.0, "gold": 22, "ore": &"stone"},
	{"id": &"mine_warden", "name": "The Mine Warden", "model": "Knight.fbx",
	 "tint": Color(0.55, 0.14, 0.20), "health": 260, "damage": 18, "speed": 2.0,
	 "range": 2.4, "cooldown": 1.6, "gold": 400, "ore": &"iron_ore", "boss": true},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var script := load(SCRIPT_PATH) as GDScript
	if script == null:
		printerr("[generate_combat_data] enemy script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in ENEMIES:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("model", MODEL_DIR + String(spec["model"]))
		data.set("tint", spec["tint"])
		data.set("target_height", 2.0 if bool(spec.get("boss", false)) else 1.8)
		data.set("max_health", int(spec["health"]))
		data.set("damage", int(spec["damage"]))
		data.set("speed", float(spec["speed"]))
		data.set("attack_range", float(spec["range"]))
		data.set("attack_cooldown", float(spec["cooldown"]))
		data.set("is_boss", bool(spec.get("boss", false)))
		data.set("gold_reward", int(spec["gold"]))
		data.set("ore_reward", spec["ore"])
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUTPUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_combat_data] wrote %d enemies" % ENEMIES.size())
	quit(1 if errors > 0 else 0)
