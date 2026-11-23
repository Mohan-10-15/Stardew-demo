extends SceneTree
## Writes the About the Game pages. Run:
##   Godot --headless --path . --script res://tools/generate_about_data.gd

const OUT := "res://resources/ui/about/"
const SCRIPT := "res://resources/ui/about_page.gd"

const PAGES: Array[Dictionary] = [
	{
		"id": &"what_is_this", "order": 0, "title": "What is Hollowbrook Hollow?",
		"icon": "heart",
		"body": "Hollowbrook Hollow is a cozy 3D farming and life simulator. " \
			+ "The ash-fall took the old road and the valley's Heartstone. " \
			+ "You inherit a burnt-out farm, work the soil back to life, and " \
			+ "befriend the twelve people who stayed. The valley remembers you.",
	},
	{
		"id": &"what_you_do", "order": 1, "title": "What you'll do",
		"icon": "seed",
		"body": "[b]Farm & forage[/b] — till, plant, water, harvest.\n" \
			+ "[b]Fish & cook[/b] — cast at the pond, turn catches into meals.\n" \
			+ "[b]Mine & build with blocks[/b] — dig the Deep Mines, build in the Builders' Plot.\n" \
			+ "[b]Befriend twelve villagers[/b] — gifts, festivals, romance.\n" \
			+ "[b]Celebrate festivals[/b] — four seasons of reasons to gather.\n" \
			+ "[b]Restore the Heartstone[/b] — the valley's long road home.",
	},
	{
		"id": &"a_day", "order": 2, "title": "A day in the valley",
		"icon": "clock",
		"body": "A day runs 06:00 to 02:00 and takes about ten real minutes. " \
			+ "Four seasons of 28 days make a year. Every swing, step and " \
			+ "conversation spends energy — choosing what to do with a finite " \
			+ "day is the game. At 02:00 you collapse and are carried home; " \
			+ "sleeping in your own bed is gentler.",
	},
	{
		"id": &"your_goal", "order": 3, "title": "Your goal",
		"icon": "star",
		"body": "Collections across Fields, Waters, Stone, Table, Wilds and " \
			+ "Hearts call the six lost Embers home. As the Heartstone mends, " \
			+ "paths and festivals open and the seasons settle. The last Ember " \
			+ "needs something no list can measure: being known. Afterwards " \
			+ "the valley is yours to keep playing.",
	},
	{
		"id": &"how_to_play", "order": 5, "title": "How to Play",
		"icon": "pad",
		"body": "Move with [b]WASD[/b], look with the mouse. [b]E[/b] talks, " \
			+ "picks up and opens; [b]left click[/b] uses the held tool and " \
			+ "[b]right click[/b] places or cancels. [b]Space[/b] jumps, " \
			+ "[b]1-9[/b] or the wheel swaps tools, [b]Esc[/b] goes back. " \
			+ "On a pad: left stick, right stick, [b]X[/b] interact, [b]RT[/b] " \
			+ "use, [b]LT[/b] alt-use, [b]A[/b] jump, [b]Start[/b] menu. " \
			+ "F2 opens the full remap and accessibility screen.",
	},
	{
		"id": &"who_stayed", "order": 4, "title": "Who stayed",
		"icon": "people",
		"body": "Twelve neighbours kept the hollow alive through the ash: " \
			+ "Mira, Bram, Fen, Odette, Sable, Aurel, Lyra, Cassia, Elke, " \
			+ "Garrick, Halda and Dorian. Each has a want, a fear, a birthday " \
			+ "and a gift they love. Learn their stories in the journal and " \
			+ "at the Heartstone's Mending.",
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in PAGES:
		var page: Object = script.new()
		page.set("id", spec["id"])
		page.set("title", spec["title"])
		page.set("body", spec["body"])
		page.set("icon", spec["icon"])
		page.set("order", int(spec["order"]))
		if not bool(page.call("is_valid")):
			printerr("[generate_about_data] invalid page %s" % spec["id"])
			errors += 1
			continue
		if ResourceSaver.save(page, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_about_data] wrote %d pages" % PAGES.size())
	quit(1 if errors > 0 else 0)
