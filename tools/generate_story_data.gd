extends SceneTree
## Headless tool: writes the main-story chapters into `resources/story/chapters/`.
##
##     godot --headless --path . --script res://tools/generate_story_data.gd
##
## Chapter ids carry a numeric prefix so the registry's id sort *is* play order.

const OUTPUT := "res://resources/story/chapters/"
const CHAPTER_SCRIPT := "res://resources/story/story_chapter.gd"

const CHAPTERS: Array[Dictionary] = [
	{
		"id": &"ch01_arrival", "title": "A Cart at Dawn",
		"description": "You arrive at the old farm with a bill in your pocket and a valley you have never seen.",
		"requires": [], "cutscene": &"intro", "gold": 0,
	},
	{
		"id": &"ch02_village", "title": "The Square Wakes",
		"description": "The village notices you. Somebody has work, and somebody has advice.",
		"requires": [&"intro_seen"], "cutscene": &"first_village", "gold": 50,
	},
	{
		"id": &"ch03_harvest", "title": "Something Grows",
		"description": "Your first harvest goes into the bag, and Mira's question has an answer.",
		"requires": [&"first_village_seen", &"first_harvest"], "gold": 120,
	},
	{
		"id": &"ch04_friend", "title": "A Name Worth Knowing",
		"description": "You finish Mira's job and somebody in the valley is glad you stayed.",
		"requires": [&"quest_q_mira_first_harvest_done", &"first_friend"], "gold": 220,
	},
	{
		"id": &"ch05_trust", "title": "The Quiet Between Jobs",
		"description": "Odette trusts you with the frost dispute. The valley stops feeling like a map.",
		"requires": [&"quest_q_odette_first_frost_done"], "gold": 320,
	},
	{
		"id": &"ch06_ending", "title": "The Valley Remembers",
		"description": "Someone chooses to live here with you — the partnership beat, before the Mending.",
		"requires": [&"married"], "gold": 400, "ending": false,
		"act": 2, "order": 6,
	},
	# Act II — Embers. Each collection tier calls one fragment home and opens
	# a tangible part of the valley; the ids sort into play order (W2.5).
	{
		"id": &"ch07_fields", "title": "The Orchard Path",
		"description": "The first Ember answers the harvest. An old path to the orchard opens.",
		"requires": [&"ember_fields"], "gold": 200, "act": 2, "order": 7,
	},
	{
		"id": &"ch08_waters", "title": "Where the Water Remembers",
		"description": "The pond pier stands again, and a second Ember settles into the square.",
		"requires": [&"ember_waters"], "gold": 240, "act": 2, "order": 8,
	},
	{
		"id": &"ch09_stone", "title": "Below the Ash",
		"description": "The Deep Mines stairs are clear. Stone remembers what was buried.",
		"requires": [&"ember_stone"], "gold": 300, "act": 2, "order": 9,
	},
	{
		"id": &"ch10_table", "title": "A Seat at the Table",
		"description": "Recipes long forgotten come back, and the festival feasts have flavour again.",
		"requires": [&"ember_table"], "gold": 320, "act": 2, "order": 10,
	},
	{
		"id": &"ch11_wilds", "title": "The Forest Road",
		"description": "The wilds open their road. Something in the hollow exhales.",
		"requires": [&"ember_wilds"], "gold": 340, "act": 2, "order": 11,
	},
	# Act III — Hearth
	{
		"id": &"ch12_frost", "title": "The Early Frost",
		"description": "Winter comes too soon. The Frost Lantern will not light, and the village looks to you.",
		"requires": [&"ember_wilds", &"quest_q_odette_first_frost_done"],
		"gold": 400, "act": 3, "order": 12,
	},
	{
		"id": &"ch13_hearts", "title": "What the Valley Kept",
		"description": "The last Ember needs no collection. It needs twelve people who know your name.",
		"requires": [&"ember_hearts"], "gold": 500, "act": 3, "order": 13,
	},
	{
		"id": &"ch14_mending", "title": "The Mending",
		"description": "At the plinth, the hollow recites what you did and the Heartstone comes home.",
		"requires": [&"all_embers"], "cutscene": &"the_mending",
		"gold": 1200, "act": 3, "order": 14,
	},
	{
		"id": &"ch15_free_play", "title": "The Long Afternoon",
		"description": "The Heartstone is whole. The valley keeps going, and so do you.",
		"requires": [&"all_embers"], "gold": 0, "ending": true,
		"act": 3, "order": 15,
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var script := load(CHAPTER_SCRIPT) as GDScript
	if script == null:
		printerr("[generate_story_data] chapter script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in CHAPTERS:
		var chapter: Object = script.new()
		chapter.set("id", spec["id"])
		chapter.set("title", spec["title"])
		chapter.set("description", spec["description"])
		var reqs: Array[StringName] = []
		for r: StringName in spec.get("requires", []):
			reqs.append(r)
		chapter.set("requires", reqs)
		chapter.set("cutscene_id", StringName(spec.get("cutscene", &"")))
		chapter.set("reward_gold", int(spec.get("gold", 0)))
		chapter.set("is_ending", bool(spec.get("ending", false)))
		chapter.set("act", int(spec.get("act", 1)))
		chapter.set("order", int(spec.get("order", 0)))
		if not bool(chapter.call("is_valid")):
			printerr("[generate_story_data] invalid chapter %s" % spec["id"])
			errors += 1
			continue
		var path := "%s%s.tres" % [OUTPUT, spec["id"]]
		if ResourceSaver.save(chapter, path) != OK:
			printerr("[generate_story_data] failed to write %s" % path)
			errors += 1
	print("[generate_story_data] wrote %d chapters" % CHAPTERS.size())
	quit(1 if errors > 0 else 0)
