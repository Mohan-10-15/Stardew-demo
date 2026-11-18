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
		"description": "Someone chooses to live here with you. The story ends; the farming does not.",
		"requires": [&"married"], "gold": 1000, "ending": true,
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
