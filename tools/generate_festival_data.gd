extends SceneTree
## Headless tool: writes festival definitions and one gathering day per villager.

const FEST_DIR := "res://resources/festivals/"
const SCHEDULE_DIR := "res://resources/npc/schedules/"
const FEST_SCRIPT := "res://resources/festivals/festival_data.gd"
const SCHEDULE_SCRIPT := "res://scripts/npc/npc_schedule.gd"
const ENTRY_SCRIPT := "res://scripts/npc/npc_schedule_entry.gd"
const NPC_DIR := "res://resources/npc/npcs/"

const FESTIVALS: Array[Dictionary] = [
	{"id": &"bloom_day", "name": "Bloom Day", "season": 0, "day": 8,
	 "description": "The valley opens every garden gate and compares notes until dark.",
	 "gold": 120, "item": &"parsnip_seeds", "hearts": 1},
	{"id": &"harvest_tide", "name": "Harvest Tide", "season": 2, "day": 14,
	 "description": "Lanterns on the fences, the whole square full of tables, and Odette still reading the water.",
	 "gold": 320, "item": &"pumpkin", "hearts": 2},
	{"id": &"frost_lantern", "name": "Frost Lantern", "season": 3, "day": 12,
	 "description": "Everyone brings one warm thing to the coldest night of the year.",
	 "gold": 260, "item": &"wood", "hearts": 1},
	{"id": &"starfall", "name": "Starfall", "season": 1, "day": 21,
	 "description": "The orchard stays open past midnight and nobody pretends to be asleep.",
	 "gold": 280, "item": &"melon", "hearts": 1},
	# Update 2 W2.5: one more per season, each rewarding a different existing
	# loop (crops, fishing, cooking, foraging).
	{"id": &"seedling_day", "name": "Seedling Day", "season": 0, "day": 21,
	 "description": "Every garden gate opens again and the season's first seeds change hands.",
	 "gold": 150, "item": &"parsnip_seeds", "hearts": 1},
	{"id": &"sunfin_regatta", "name": "Sunfin Regatta", "season": 1, "day": 7,
	 "description": "A fishing contest at the pond; the biggest catch wins the feast.",
	 "gold": 260, "item": &"fish_trout", "hearts": 1},
	{"id": &"lantern_walk", "name": "Lantern Walk", "season": 2, "day": 21,
	 "description": "The village cooks together and carries the table into the square.",
	 "gold": 300, "item": &"berry_jam", "hearts": 2},
	{"id": &"hearth_night", "name": "Hearth Night", "season": 3, "day": 21,
	 "description": "The coldest week ends with wood, warm stories and a light in every window.",
	 "gold": 240, "item": &"wood", "hearts": 1},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FEST_DIR))
	var fest_script := load(FEST_SCRIPT) as GDScript
	var schedule_script := load(SCHEDULE_SCRIPT) as GDScript
	var entry_script := load(ENTRY_SCRIPT) as GDScript
	if fest_script == null or schedule_script == null or entry_script == null:
		printerr("[generate_festival_data] scripts missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in FESTIVALS:
		var festival: Object = fest_script.new()
		festival.set("id", spec["id"])
		festival.set("display_name", spec["name"])
		festival.set("season", int(spec["season"]))
		festival.set("day_of_month", int(spec["day"]))
		festival.set("description", String(spec["description"]))
		festival.set("reward_gold", int(spec["gold"]))
		festival.set("reward_item", spec["item"])
		festival.set("heart_reward", int(spec["hearts"]))
		if not bool(festival.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(festival, "%s%s.tres" % [FEST_DIR, spec["id"]]) != OK:
			errors += 1
	# Every villager needs a day that defers to the square. Generated from the
	# cast rather than hand-listed so adding a villager cannot miss a festival.
	var npcs := _npc_ids()
	for id: StringName in npcs:
		var schedule: Object = schedule_script.new()
		schedule.set("npc_id", StringName("%s_festival" % id))
		var entry: Object = entry_script.new()
		entry.set("from_minute", 600)
		entry.set("to_minute", NpcScheduleEntry.OPEN_END)
		entry.set("location", &"village_square")
		entry.set("activity", &"at the festival")
		var entries: Array[NpcScheduleEntry] = [entry as NpcScheduleEntry]
		schedule.set("entries", entries)
		if not bool(schedule.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(schedule, "%s%s_festival.tres" % [SCHEDULE_DIR, id]) != OK:
			errors += 1
	print("[generate_festival_data] wrote %d festivals and %d gathering days" % [
		FESTIVALS.size(), npcs.size(),
	])
	quit(1 if errors > 0 else 0)


func _npc_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open(NPC_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("%s%s" % [NPC_DIR, entry]) as NpcData
			if data != null:
				out.append(data.id)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
