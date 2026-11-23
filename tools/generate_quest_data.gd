extends SceneTree
## Writes the eleven new Update 2 quests (W2.5). The five original quest files
## are left untouched: their ids are referenced by chapters, dialogue and
## saves. Run:
##   Godot --headless --path . --script res://tools/generate_quest_data.gd

const OUT := "res://resources/quest/quests/"
const QUEST_SCRIPT := "res://scripts/quest/quest_data.gd"
const OBJECTIVE_SCRIPT := "res://scripts/quest/quest_objective.gd"
const REWARD_SCRIPT := "res://scripts/quest/quest_reward.gd"
const HEART_SCRIPT := "res://scripts/quest/quest_heart_reward.gd"

## One job per villager who did not have one, plus four spine jobs.
const QUESTS: Array[Dictionary] = [
	{"id": &"q_z_aurel_ledger", "giver": &"aurel", "title": "The Square Ledger",
	 "description": "Aurel wants the harvest numbers written down before the festival, so someone will know the valley was here.",
	 "item": &"parsnip", "count": 10, "gold": 240},
	{"id": &"q_z_lyra_song", "giver": &"lyra", "title": "A Song for the Square",
	 "description": "Lyra has forgotten the second verse. She thinks a basket of berries might bring it back.",
	 "item": &"wild_berry", "count": 8, "gold": 210},
	{"id": &"q_z_cassia_notes", "giver": &"cassia", "title": "Notes from the Ash",
	 "description": "Cassia's notes disagree about the old road. Bring her something from underground to check against.",
	 "item": &"copper_ore", "count": 8, "gold": 280},
	{"id": &"q_z_elke_garden", "giver": &"elke", "title": "A Garden of Her Own",
	 "description": "Elke wants seeds that will actually grow this season. There is a packet with her name on it.",
	 "item": &"corn_seeds", "count": 2, "gold": 190},
	{"id": &"q_z_garrick_watch", "giver": &"garrick", "title": "The Night Watch",
	 "description": "Garrick keeps the old road watched. He needs stone for the wall before the frost.",
	 "item": &"stone", "count": 18, "gold": 300},
	{"id": &"q_z_halda_story", "giver": &"halda", "title": "The Name She Forgot",
	 "description": "Halda remembers a story but not the name in it. A little milk, she says, helps her think.",
	 "item": &"milk", "count": 3, "gold": 220},
	{"id": &"q_z_dorian_belong", "giver": &"dorian", "title": "A Reason to Stay",
	 "description": "Dorian says he is only passing through. A cooked meal might make him stay for the evening.",
	 "item": &"milk", "count": 2, "gold": 260, "hearts": 2},
	# Heartstone spine jobs. Each rewards a villager's friendship as well as gold.
	{"id": &"q_z_main_orchard", "giver": &"mira", "title": "The Orchard Gate",
	 "description": "Mira says the orchard path has been closed since the ash. The harvest can open it.",
	 "item": &"pumpkin", "count": 6, "gold": 320},
	{"id": &"q_z_main_pond", "giver": &"odette", "title": "The Old Pier",
	 "description": "Odette reads the water and says the pier remembers being whole. Bring her a catch from it.",
	 "item": &"fish_trout", "count": 3, "gold": 300},
	{"id": &"q_z_main_mines", "giver": &"bram", "title": "Below the Stairs",
	 "description": "Bram cleared the mine stairs. He wants to know what is down there before anyone else does.",
	 "item": &"iron_ore", "count": 6, "gold": 380},
	{"id": &"q_z_main_mending", "giver": &"sable", "title": "Before the Mending",
	 "description": "Sable says a mended fence and a mended heart start the same way: one honest piece at a time.",
	 "item": &"wood", "count": 8, "gold": 420, "hearts": 4},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var quest_script := load(QUEST_SCRIPT) as GDScript
	var objective_script := load(OBJECTIVE_SCRIPT) as GDScript
	var reward_script := load(REWARD_SCRIPT) as GDScript
	var heart_script := load(HEART_SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in QUESTS:
		var objective: Object = objective_script.new()
		objective.set("kind", QuestObjective.KIND_COLLECT)
		objective.set("item_id", spec["item"])
		objective.set("count", int(spec["count"]))
		var heart: Object = heart_script.new()
		heart.set("npc", spec["giver"])
		heart.set("amount", 1)
		var reward: Object = reward_script.new()
		reward.set("gold", int(spec["gold"]))
		var hearts: Array[QuestHeartReward] = [heart as QuestHeartReward]
		reward.set("hearts", hearts)
		var quest: Object = quest_script.new()
		quest.set("id", spec["id"])
		quest.set("title", spec["title"])
		quest.set("description", spec["description"])
		quest.set("giver", spec["giver"])
		quest.set("objective", objective)
		quest.set("reward", reward)
		quest.set("repeats", &"once")
		# Gated behind friendship so a fresh player still meets the five
		# original jobs first — those ids are referenced by chapters and tests.
		quest.set("min_hearts", int(spec.get("hearts", 2)))
		if not bool(quest.call("is_valid")):
			printerr("[generate_quest_data] invalid %s" % spec["id"])
			errors += 1
			continue
		if ResourceSaver.save(quest, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_quest_data] wrote %d quests" % QUESTS.size())
	quit(1 if errors > 0 else 0)
