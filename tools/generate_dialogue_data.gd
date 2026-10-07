extends SceneTree
## Headless tool: writes the villager dialogue trees into
## `resources/npc/dialogue/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_dialogue_data.gd
##
## Generated rather than hand-authored for the same reason as
## [generate_npc_data] and [generate_gathering_data]: the content lives in one
## readable table in source control, the `.tres` files stay the runtime format
## [DialogueRegistry] loads, and every tree is validated *before* it is written —
## a reply pointing at a renamed entry fails the generator with the entry's id
## instead of failing the game mid-conversation.
##
## ## The shape of a villager's tree
##
## Every villager gets the same fifteen *kinds* of line and none of the same
## words:
##
## - `intro` — a `once` first meeting that raises `met_<id>`. Scored above
##   everything else while unseen, so a new player always gets it first.
## - `greeting` — the unconditional fallback. The one entry the validator
##   demands, because a tree that can be talked out of everything is a villager
##   who goes silent.
## - `morning` / `evening` / `night` — the day's shape. `night` wraps midnight
##   (23 → 5), which the condition window supports precisely so a late line
##   does not have to be two entries.
## - `rain` / `snow` (+ `storm` where the personality warrants it) — weather.
## - `spring` / `summer` / `fall` / `winter` — one line per season.
## - `friend_2` / `friend_4` — what they say once they actually know you.
## - `story_1` → `story_2` — a `once` two-beat story with a reply in the
##   middle: the first branching conversation in the game, and the pattern a
##   quest or heart event will reuse. The second beat grants a heart and raises
##   a flag nothing reads yet — that is what flags are for; the story group
##   hangs content off them later without touching this file. **Both** beats
##   carry `needs: met_<id>`, so they score identically while unseen and
##   authored order decides — which is what makes the *question* speak before
##   the answer. Drop the gate from either one and the more conditioned beat
##   outscores the other, so a player who just met a villager is greeted with
##   the middle of their story.

const OUTPUT_DIR := "res://resources/npc/dialogue/"

## One tree per villager: `npc` names the file and the content, `entries` is
## authored order (the final tie-break in selection).
##
## Keys on an entry:
##   id, text                              — required
##   season, weather                       — WorldTime enums, absent = any
##   from, to                              — inclusive hour window; from > to wraps midnight
##   min_hearts, max_hearts                — relationship gates
##   needs, without                        — flag must be set / must not be set
##   once                                  — at most once per save
##   hearts, flags                         — effects applied when the line is left
##   next                                  — line to follow, absent = end
##   choices                               — [{text, next?, hearts?, flags?}]
const TREES: Array[Dictionary] = [
	{
		"npc": &"mira",
		"entries": [
			{
				"id": &"intro", "once": true, "flags": [&"met_mira"],
				"text": "You're the one who took the old farm up the path. I'm Mira. " +
					"If it's advice you want, I take payment in parsnips.",
			},
			{
				"id": &"greeting",
				"text": "Soil's telling you something every day. You just have to " +
					"stop shouting long enough to hear it.",
			},
			{
				"id": &"morning", "from": 6, "to": 10,
				"text": "Been up since first light. The garden doesn't care what " +
					"time I got to bed.",
			},
			{
				"id": &"evening", "from": 17, "to": 22,
				"text": "A long day looks longer from the porch. Sit, if you've got " +
					"the time.",
			},
			{
				"id": &"night", "from": 23, "to": 5,
				"text": "Shouldn't you be asleep? Neither should I, apparently.",
			},
			{
				"id": &"rain", "weather": WorldTime.Weather.RAIN,
				"text": "Rain does half my watering. The other half I still do by " +
					"hand, out of tradition.",
			},
			{
				"id": &"snow", "weather": WorldTime.Weather.SNOW,
				"text": "Under that snow, everything's still alive. Waiting. That's " +
					"the whole trick of it.",
			},
			{
				"id": &"spring", "season": WorldTime.Season.SPRING,
				"text": "Spring lies to you. One warm week, then a frost that takes " +
					"the lot. Trust the calendar, not the sky.",
			},
			{
				"id": &"summer", "season": WorldTime.Season.SUMMER,
				"text": "Water early, harvest late. Everything else is standing in " +
					"the dirt hoping at your plants.",
			},
			{
				"id": &"fall", "season": WorldTime.Season.FALL,
				"text": "This is the season that pays for the whole year. Don't " +
					"waste it being sociable.",
			},
			{
				"id": &"winter", "season": WorldTime.Season.WINTER,
				"text": "Winter's for mending and planning. I plan the garden four " +
					"times and plant it once.",
			},
			{
				"id": &"friend_2", "min_hearts": 2,
				"text": "You actually listen. Most people nod and then do the " +
					"opposite of what they nodded at.",
			},
			{
				"id": &"friend_4", "min_hearts": 4,
				"text": "This valley's better with you in it. Don't make me say " +
					"that again for at least a season.",
			},
			{
				"id": &"story_1", "once": true, "needs": &"met_mira",
				"text": "Did anyone tell you about the field behind the barn? The " +
					"one nobody works.",
				"choices": [
					{"text": "Why not?", "next": &"story_2"},
					{"text": "I'd rather not know.", "flags": [&"mira_field_dodged"]},
				],
			},
			{
				"id": &"story_2", "once": true, "needs": &"met_mira",
				"hearts": 1, "flags": [&"mira_field_secret"],
				"text": "Because whatever's in that soil, something grows there " +
					"nobody planted. Halda tried. Once.",
			},
		],
	},
	{
		"npc": &"bram",
		"entries": [
			{
				"id": &"intro", "once": true, "flags": [&"met_bram"],
				"text": "Bram. I build. If it's still standing next winter, I made it.",
			},
			{
				"id": &"greeting",
				"text": "Wind's changed. Good day to get something finished.",
			},
			{
				"id": &"morning", "from": 6, "to": 10,
				"text": "Early. Nothing to it but starting.",
			},
			{
				"id": &"evening", "from": 17, "to": 22,
				"text": "Put the tools down. Whatever it is, it'll still be broken " +
					"tomorrow.",
			},
			{
				"id": &"night", "from": 23, "to": 5,
				"text": "Still up. A joint won't dry any faster for being watched.",
			},
			{
				"id": &"rain", "weather": WorldTime.Weather.RAIN,
				"text": "Rain finds every gap you were proud of.",
			},
			{
				"id": &"storm", "weather": WorldTime.Weather.STORM,
				"text": "Storm takes fences. Hold the door too; it'll test that next.",
			},
			{
				"id": &"snow", "weather": WorldTime.Weather.SNOW,
				"text": "Snow's honest. It shows you exactly where the roof is thin.",
			},
			{
				"id": &"spring", "season": WorldTime.Season.SPRING,
				"text": "Ground softens in spring. Best month to set a foundation.",
			},
			{
				"id": &"summer", "season": WorldTime.Season.SUMMER,
				"text": "Heat swells the timber. Measure twice in summer — it'll " +
					"have moved by winter.",
			},
			{
				"id": &"fall", "season": WorldTime.Season.FALL,
				"text": "Before the frost. Anything left unbuilt stays unbuilt till " +
					"the thaw.",
			},
			{
				"id": &"winter", "season": WorldTime.Season.WINTER,
				"text": "Indoor work now. Small jobs, done properly.",
			},
			{
				"id": &"friend_2", "min_hearts": 2,
				"text": "You hold the other end well. That's more than most manage.",
			},
			{
				"id": &"friend_4", "min_hearts": 4,
				"text": "Valley needs people who finish things. You finish things.",
			},
			{
				"id": &"story_1", "once": true, "needs": &"met_bram",
				"text": "The old bridge over the brook. I fixed it. Twice.",
				"choices": [
					{"text": "Who broke it?", "next": &"story_2"},
					{"text": "Good for you.", "flags": [&"bram_bridge_dodged"]},
				],
			},
			{
				"id": &"story_2", "once": true, "needs": &"met_bram",
				"hearts": 1, "flags": [&"bram_bridge_truth"],
				"text": "Nobody broke it. It was built wrong. I don't say that about " +
					"work — I'm saying it about mine.",
			},
		],
	},
	{
		"npc": &"odette",
		"entries": [
			{
				"id": &"intro", "once": true, "flags": [&"met_odette"],
				"text": "Odette. I read the water. You can call it guessing if it " +
					"keeps you comfortable.",
			},
			{
				"id": &"greeting",
				"text": "The brook's quiet today. That means something. It always " +
					"means something.",
			},
			{
				"id": &"morning", "from": 6, "to": 10,
				"text": "Mist on the water. Rain by evening — you didn't hear that " +
					"from me, you heard it from the river.",
			},
			{
				"id": &"evening", "from": 17, "to": 22,
				"text": "The air's gone heavy. Something out there is deciding " +
					"whether to arrive.",
			},
			{
				"id": &"night", "from": 23, "to": 5,
				"text": "The water's black at night and honest about nothing. I " +
					"look anyway.",
			},
			{
				"id": &"rain", "weather": WorldTime.Weather.RAIN,
				"text": "I told the well about this days ago. It's been telling " +
					"everyone since.",
			},
			{
				"id": &"storm", "weather": WorldTime.Weather.STORM,
				"text": "Storm's got teeth tonight. Stay off the ridgeline and away " +
					"from the old oak.",
			},
			{
				"id": &"snow", "weather": WorldTime.Weather.SNOW,
				"text": "Snow mutes the water's voice. Even I can't read it under ice.",
			},
			{
				"id": &"spring", "season": WorldTime.Season.SPRING,
				"text": "Spring runoff talks more than the brook does all the rest " +
					"of the year. Half of it's complaining.",
			},
			{
				"id": &"summer", "season": WorldTime.Season.SUMMER,
				"text": "The lake gives up its heat at night. Stand close and you " +
					"can hear it breathing.",
			},
			{
				"id": &"fall", "season": WorldTime.Season.FALL,
				"text": "Water runs low and clear in fall. That's when everything " +
					"true shows up.",
			},
			{
				"id": &"winter", "season": WorldTime.Season.WINTER,
				"text": "Ice is a lid. Whatever's under it keeps its own counsel.",
			},
			{
				"id": &"friend_2", "min_hearts": 2,
				"text": "Most people look at water to see themselves. You look at " +
					"the water.",
			},
			{
				"id": &"friend_4", "min_hearts": 4,
				"text": "I don't say this to many. You'd have made a fine reader " +
					"of water.",
			},
			{
				"id": &"story_1", "once": true, "needs": &"met_odette",
				"text": "There's a spot past the mine where the water runs the " +
					"wrong way.",
				"choices": [
					{"text": "Wrong how?", "next": &"story_2"},
					{"text": "A trick of the light.", "flags": [&"odette_water_dodged"]},
				],
			},
			{
				"id": &"story_2", "once": true, "needs": &"met_odette",
				"hearts": 1, "flags": [&"odette_wrong_water"],
				"text": "Upstream. Against the slope. Nobody's ever explained it, " +
					"and I've stopped going there after dusk.",
			},
		],
	},
	{
		"npc": &"fen",
		"entries": [
			{
				"id": &"intro", "once": true, "flags": [&"met_fen"],
				"text": "Fen. Don't follow me into the trees. ...You can, if you " +
					"keep up.",
			},
			{
				"id": &"greeting",
				"text": "Berries are ripe somewhere. I'm not saying where.",
			},
			{
				"id": &"morning", "from": 6, "to": 10,
				"text": "Dew still on. Best hour of the day. Also the hour with the " +
					"most mosquitoes.",
			},
			{
				"id": &"evening", "from": 17, "to": 22,
				"text": "Back before dark. Usually.",
			},
			{
				"id": &"night", "from": 23, "to": 5,
				"text": "What's awake at this hour isn't berry-picking.",
			},
			{
				"id": &"rain", "weather": WorldTime.Weather.RAIN,
				"text": "Rain washes the tracks. Mine, and everyone else's.",
			},
			{
				"id": &"snow", "weather": WorldTime.Weather.SNOW,
				"text": "Deep snow. Easy to follow a man, easy to be followed. I " +
					"think about which one I'm doing.",
			},
			{
				"id": &"spring", "season": WorldTime.Season.SPRING,
				"text": "Spring reaches the forest floor first. Before the trees " +
					"can't-be-bothered to notice.",
			},
			{
				"id": &"summer", "season": WorldTime.Season.SUMMER,
				"text": "Everything grows fast enough to hear out here. Even the " +
					"trouble.",
			},
			{
				"id": &"fall", "season": WorldTime.Season.FALL,
				"text": "Mushrooms and rats. Best and worst of the year, same month.",
			},
			{
				"id": &"winter", "season": WorldTime.Season.WINTER,
				"text": "The valley keeps its food underground in winter. So do I.",
			},
			{
				"id": &"friend_2", "min_hearts": 2,
				"text": "You walk quiet for a farmer.",
			},
			{
				"id": &"friend_4", "min_hearts": 4,
				"text": "Alright. The good berries are past the fallen birch, north " +
					"where the moss goes thick. Don't tell Halda.",
			},
			{
				"id": &"story_1", "once": true, "needs": &"met_fen",
				"text": "Someone used to live in the deep woods. Before.",
				"choices": [
					{"text": "Before what?", "next": &"story_2"},
					{"text": "Whatever you say.", "flags": [&"fen_old_camp_dodged"]},
				],
			},
			{
				"id": &"story_2", "once": true, "needs": &"met_fen",
				"hearts": 1, "flags": [&"fen_old_camp"],
				"text": "Before the village. There's a chimney still standing out " +
					"there. I don't take anything from it.",
			},
		],
	},
	{
		"npc": &"halda",
		"entries": [
			{
				"id": &"intro", "once": true, "flags": [&"met_halda"],
				"text": "Halda. I grow pumpkins. I grow them better than anyone has " +
					"a right to.",
			},
			{
				"id": &"greeting",
				"text": "Soil's alright. People are the tricky crop.",
			},
			{
				"id": &"morning", "from": 6, "to": 10,
				"text": "Mornings are mine. Afternoons are for other people's opinions.",
			},
			{
				"id": &"evening", "from": 17, "to": 22,
				"text": "Sun's off the patch. Honest work's done for the day.",
			},
			{
				"id": &"night", "from": 23, "to": 5,
				"text": "If you're sleepwalking toward my patch, wake up.",
			},
			{
				"id": &"rain", "weather": WorldTime.Weather.RAIN,
				"text": "Rain's fine. Hail's the one I hold a proper grudge against.",
			},
			{
				"id": &"storm", "weather": WorldTime.Weather.STORM,
				"text": "Storm takes fences. I've rebuilt that fence three times and " +
					"I remember each one.",
			},
			{
				"id": &"snow", "weather": WorldTime.Weather.SNOW,
				"text": "Under snow, my patch sleeps better than the village does.",
			},
			{
				"id": &"spring", "season": WorldTime.Season.SPRING,
				"text": "Everything's a seed now and a regret by July. Plant carefully.",
			},
			{
				"id": &"summer", "season": WorldTime.Season.SUMMER,
				"text": "Don't touch a vine to see if it's growing. It knows you're there.",
			},
			{
				"id": &"fall", "season": WorldTime.Season.FALL,
				"text": "This is my season. Stand back and admire.",
			},
			{
				"id": &"winter", "season": WorldTime.Season.WINTER,
				"text": "Winter I count seed packets and stare at walls. It's called " +
					"planning.",
			},
			{
				"id": &"friend_2", "min_hearts": 2,
				"text": "You water on time. That already puts you ahead of most.",
			},
			{
				"id": &"friend_4", "min_hearts": 4,
				"text": "This valley has trouble coming — it does, every year. You " +
					"look like the kind who faces it.",
			},
			{
				"id": &"story_1", "once": true, "needs": &"met_halda",
				"text": "You've seen the size of my pumpkins. Want to know why?",
				"choices": [
					{"text": "Go on.", "next": &"story_2"},
					{"text": "I assumed sorcery.", "flags": [&"halda_seed_dodged"]},
				],
			},
			{
				"id": &"story_2", "once": true, "needs": &"met_halda",
				"hearts": 1, "flags": [&"halda_seed_line"],
				"text": "Seed line. Saved it twenty years running. It remembers what " +
					"the ground did wrong.",
			},
		],
	},
	{
		"npc": &"sable",
		"entries": [
			{
				"id": &"intro", "once": true, "flags": [&"met_sable"],
				"text": "Sable. I mend things. Eventually.",
			},
			{
				"id": &"greeting",
				"text": "Everything around here is broken in a friendly way.",
			},
			{
				"id": &"morning", "from": 6, "to": 10,
				"text": "Give it a minute. Things sort themselves out if nobody " +
					"rushes them.",
			},
			{
				"id": &"evening", "from": 17, "to": 22,
				"text": "End of the day's for looking at everything that didn't get " +
					"finished.",
			},
			{
				"id": &"night", "from": 23, "to": 5,
				"text": "Insomnia's just mending without thread.",
			},
			{
				"id": &"rain", "weather": WorldTime.Weather.RAIN,
				"text": "Rain rusts what it finds. I'll get to it.",
			},
			{
				"id": &"snow", "weather": WorldTime.Weather.SNOW,
				"text": "Snow's a repair job on the whole valley. Temporary, but tidy.",
			},
			{
				"id": &"spring", "season": WorldTime.Season.SPRING,
				"text": "Hinges, shutters, gates. Spring sends me a list every year " +
					"and I lose it every year.",
			},
			{
				"id": &"summer", "season": WorldTime.Season.SUMMER,
				"text": "Heat warps everything. Including my ambition.",
			},
			{
				"id": &"fall", "season": WorldTime.Season.FALL,
				"text": "Barn doors and boots. The valley gets itself ready; I just " +
					"follow along behind.",
			},
			{
				"id": &"winter", "season": WorldTime.Season.WINTER,
				"text": "Good winter for sitting next to something I already fixed.",
			},
			{
				"id": &"friend_2", "min_hearts": 2,
				"text": "You don't rush me. That's rarer than you'd think.",
			},
			{
				"id": &"friend_4", "min_hearts": 4,
				"text": "You're the one who says thank you and means the wait was " +
					"worth it.",
			},
			{
				"id": &"story_1", "once": true, "needs": &"met_sable",
				"text": "I was asked to mend something I shouldn't have.",
				"choices": [
					{"text": "What was it?", "next": &"story_2"},
					{"text": "Your business, then.", "flags": [&"sable_door_dodged"]},
				],
			},
			{
				"id": &"story_2", "once": true, "needs": &"met_sable",
				"hearts": 1, "flags": [&"sable_old_door"],
				"text": "A door out past the lake. It doesn't open. It never needed " +
					"mending. I still think about it.",
			},
		],
	},
]


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		var err := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUTPUT_DIR)
		)
		if err != OK:
			printerr("[generate_dialogue_data] cannot create %s: %d" % [OUTPUT_DIR, err])
			quit(1)
			return

	var written := 0
	var exit_code := 0
	var total_entries := 0

	for spec: Dictionary in TREES:
		var tree := _build(spec)
		total_entries += tree.entries.size()
		var problem := tree.is_valid()
		if not problem.is_empty():
			printerr("[generate_dialogue_data] %s: %s" % [tree.npc_id, problem])
			exit_code = 1
			continue
		var path := "%s%s.tres" % [OUTPUT_DIR, tree.npc_id]
		if ResourceSaver.save(tree, path) != OK:
			printerr("[generate_dialogue_data] failed to write %s" % path)
			exit_code = 1
			continue
		written += 1

	print("[generate_dialogue_data] wrote %d trees (%d entries) to %s" % [
		written, total_entries, OUTPUT_DIR,
	])
	quit(exit_code)


## Turns one authored dictionary into a validated [DialogueTree].
##
## Unknown keys are a hard failure rather than a ignored typo: a misspelled
## `"hearts"` would silently become a line with no effect, and the content test
## that asks "does every story beat grant its heart" would be reading a table
## that never carried one.
func _build(spec: Dictionary) -> DialogueTree:
	var tree := DialogueTree.new()
	tree.npc_id = spec["npc"]
	for entry_spec: Dictionary in spec["entries"]:
		tree.entries.append(_build_entry(tree.npc_id, entry_spec))
	return tree


func _build_entry(npc_id: StringName, spec: Dictionary) -> DialogueEntry:
	var e := DialogueEntry.new()
	e.id = spec.get("id", &"")
	e.text = spec.get("text", "")
	if spec.has("season"):
		e.season = int(spec["season"])
	if spec.has("weather"):
		e.weather = int(spec["weather"])
	if spec.has("from"):
		e.hour_from = int(spec["from"])
	if spec.has("to"):
		e.hour_to = int(spec["to"])
	if spec.has("min_hearts"):
		e.min_hearts = int(spec["min_hearts"])
	if spec.has("max_hearts"):
		e.max_hearts = int(spec["max_hearts"])
	if spec.has("needs"):
		e.requires_flag = spec["needs"]
	if spec.has("without"):
		e.excludes_flag = spec["without"]
	if spec.has("once"):
		e.once = bool(spec["once"])
	if spec.has("hearts"):
		e.hearts = int(spec["hearts"])
	if spec.has("flags"):
		for flag: Variant in spec["flags"]:
			e.set_flags.append(flag)
	if spec.has("next"):
		e.next = spec["next"]
	for choice_spec: Dictionary in spec.get("choices", []):
		var choice := DialogueChoice.new()
		choice.text = String(choice_spec.get("text", ""))
		if choice_spec.has("next"):
			choice.next = choice_spec["next"]
		if choice_spec.has("hearts"):
			choice.hearts = int(choice_spec["hearts"])
		if choice_spec.has("flags"):
			for flag: Variant in choice_spec["flags"]:
				choice.set_flags.append(flag)
		e.choices.append(choice)
	_check_unknown_keys(npc_id, spec, [
		"id", "text", "season", "weather", "from", "to", "min_hearts",
		"max_hearts", "needs", "without", "once", "hearts", "flags", "next",
		"choices",
	])
	return e


func _check_unknown_keys(npc_id: StringName, spec: Dictionary, known: Array) -> void:
	for key: Variant in spec.keys():
		if not known.has(key):
			printerr("[generate_dialogue_data] %s entry '%s' has unknown key '%s'" % [
				npc_id, spec.get("id", "?"), key,
			])
			quit(1)
