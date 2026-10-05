extends SceneTree
## Headless tool: writes the villager `.tres` definitions into `resources/npc/npcs/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_npc_data.gd
##
## Generated rather than hand-authored for the same reason as [generate_gathering_data]:
## the balance numbers live in one readable table in source control, and the `.tres`
## files stay the runtime format [NpcRegistry] loads.
##
## A villager naming a model that will not load, or an item id nothing defines, is a
## silent empty square rather than an error, so both are checked here and fail the
## generator instead.

const OUTPUT_DIR := "res://resources/npc/npcs/"
const MODEL_DIR := "res://assets/models/kaykit/Characters/"

## One entry per villager. The keys map one-to-one onto [NpcData]'s fields.
##
## ## The cast, and why it is six people
##
## The GDD asks for a dozen eventually and group 14 is the foundation, not the
## roster: six proves that five shared bodies and six distinct personalities are
## survivable, which is the risk worth retiring early. Widening the cast later is a
## table edit.
##
## ## Why five models and six villagers
##
## The CC0 character pack ships five bodies. Tinting is what makes the sixth
## possible without the sixth looking like a copy-paste error, and
## [method NpcRegistry.count_per_appearance] exists so a content test can say out loud
## how much costume sharing the cast is doing rather than leaving it to be noticed.
##
## ## Gift lists
##
## Every list is three real item ids, and no item appears in two of them across one
## villager — [method NpcData.is_valid] refuses that, so a typo here fails the
## generator rather than becoming a silent precedence rule. Preferences are drawn from
## things the player can actually have: forage, crops, stone, wood and ore. Tools are
## absent by design, because [method NpcData.is_giftable] refuses them on principle.
##
## ## The birthdays
##
## Spread across all four seasons and across the plausible range of days, so the
## calendar has something to say and a content test can assert they are not all the
## same week of Spring.
## ## The homes
##
## Each was authored as `house_centre + (1.5, 1.5)` in **world** axes, which put four
## of the six inside the house they were standing in and Mira inside the VillageWell as
## well. The houses are yawed and the doors are on the local -Z face, so the offset has
## to be along the door's outward normal, not along world axes.
##
## These are the doorstep step-points from `world_builder.gd`'s own house table, each one
## at least a metre clear of its own collider. They are the same values the cottage
## locations are generated from, so a villager's spawn point and the place a schedule
## sends them home cannot drift apart.
const VILLAGERS: Array[Dictionary] = [
	{
		"id": &"mira", "display_name": "Mira", "model": "Knight.fbx",
		"description": "Keeps the kitchen garden behind the shop. Will trade advice for a parsnip.",
		"tint": Color(0.82, 0.36, 0.32, 1.0), "target_height": 1.78,
		# House 1's front step, on the door normal. Was (30.5, 3.5): inside the house,
		# and 0.71 m from the middle of the well.
		"home": Vector2(29.7, -1.8), "wander_radius": 7.0, "walk_speed": 1.7,
		"birthday_season": 1, "birthday_day": 12,
		"loved": [&"wild_berry", &"parsnip"], "liked": [&"spring_onion", &"potato"],
		"disliked": [&"stone"],
	},
	{
		"id": &"bram", "display_name": "Bram", "model": "Barbarian.fbx",
		"description": "Big, quiet, and always building something that will not fall down.",
		"tint": Color(0.55, 0.38, 0.24, 1.0), "target_height": 1.92,
		# House 2's front step. Was (45.5, 1.5): inside the house.
		"home": Vector2(44.4, -3.8), "wander_radius": 5.0, "walk_speed": 1.5,
		"birthday_season": 2, "birthday_day": 28,
		"loved": [&"iron_ore", &"copper_ore"], "liked": [&"wood", &"stone"],
		"disliked": [&"spring_onion"],
	},
	{
		"id": &"odette", "display_name": "Odette", "model": "Mage.fbx",
		"description": "Reads the weather off the water and is right more often than is comfortable.",
		"tint": Color(0.44, 0.36, 0.72, 1.0), "target_height": 1.74,
		# House 3's front step. Was (49.5, 14.5): inside the house.
		"home": Vector2(47.3, 9.3), "wander_radius": 8.0, "walk_speed": 1.6,
		"birthday_season": 3, "birthday_day": 5,
		"loved": [&"cauliflower", &"melon"], "liked": [&"yam", &"tomato"],
		"disliked": [&"wood"],
	},
	{
		"id": &"fen", "display_name": "Fen", "model": "Rogue.fbx",
		"description": "Comes and goes. Knows where the good berries are and will not say.",
		"tint": Color(0.35, 0.62, 0.45, 1.0), "target_height": 1.7,
		# House 4's front step. Was (35.5, 17.5): inside the house.
		"home": Vector2(34.2, 12.2), "wander_radius": 11.0, "walk_speed": 2.1,
		"birthday_season": 1, "birthday_day": 24,
		"loved": [&"wild_horseradish", &"wild_berry"], "liked": [&"corn", &"pumpkin"],
		"disliked": [&"iron_ore"],
	},
	{
		"id": &"halda", "display_name": "Halda", "model": "RogueHooded.fbx",
		"description": "Grows one thing, remarkably well, and guards the rest of the valley from it.",
		"tint": Color(0.72, 0.6, 0.3, 1.0), "target_height": 1.76,
		# There are five houses and six villagers, so two of them live on the square
		# rather than in a cottage. Moved off the exact middle of the village disc,
		# where a villager standing in the centre of everything is nowhere in particular.
		"home": Vector2(31.0, 9.6), "wander_radius": 6.5, "walk_speed": 1.75,
		"birthday_season": 2, "birthday_day": 9,
		"loved": [&"pumpkin", &"corn"], "liked": [&"cauliflower", &"wood"],
		"disliked": [&"wild_berry"],
	},
	{
		# The deliberate duplicate body: a Knight again, recoloured. If a content test
		# ever complains about it, the answer is in `count_per_appearance`.
		"id": &"sable", "display_name": "Sable", "model": "Knight.fbx",
		"description": "Mends things. Was asked to mend the fence, and did, eventually.",
		"tint": Color(0.3, 0.32, 0.4, 1.0), "target_height": 1.8,
		# The other square resident, on the far side of the well from Halda.
		"home": Vector2(27.6, 8.6), "wander_radius": 9.0, "walk_speed": 1.65,
		"birthday_season": 3, "birthday_day": 19,
		"loved": [&"parsnip", &"potato"], "liked": [&"copper_ore", &"wood"],
		"disliked": [&"melon"],
	},
]


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		var err := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUTPUT_DIR)
		)
		if err != OK:
			printerr("[generate_npc_data] cannot create %s: %d" % [OUTPUT_DIR, err])
			quit(1)
			return

	var known_items := _existing_item_ids()
	var written := 0
	var exit_code := 0

	for spec: Dictionary in VILLAGERS:
		var npc := NpcData.new()
		npc.id = spec["id"]
		npc.display_name = spec["display_name"]
		npc.description = spec["description"]
		npc.model = MODEL_DIR + String(spec["model"])
		npc.model_tint = spec["tint"]
		npc.target_height = spec["target_height"]
		npc.home = spec["home"]
		npc.wander_radius = spec["wander_radius"]
		npc.walk_speed = spec["walk_speed"]
		npc.birthday_season = spec["birthday_season"]
		npc.birthday_day = spec["birthday_day"]
		for id_in: StringName in spec["loved"]:
			npc.loved_gifts.append(id_in)
		for id_in: StringName in spec["liked"]:
			npc.liked_gifts.append(id_in)
		for id_in: StringName in spec["disliked"]:
			npc.disliked_gifts.append(id_in)

		if not npc.is_valid():
			printerr("[generate_npc_data] villager %s is invalid" % npc.id)
			exit_code = 1
			continue
		# A gift naming an item nothing defines is a present the player can never give,
		# and the only symptom is a villager who seems to like nothing.
		for list: Array[StringName] in [npc.loved_gifts, npc.liked_gifts, npc.disliked_gifts]:
			for item_id: StringName in list:
				if not known_items.has(item_id):
					printerr("[generate_npc_data] %s wants unknown item '%s'" % [
						npc.id, item_id,
					])
					exit_code = 1
		# An NPC definition with no body is a collider the player aims at and cannot
		# place, so the model is checked here rather than at boot.
		if not ModelArt.can_load(npc.model):
			printerr("[generate_npc_data] %s cannot load %s" % [npc.id, npc.model])
			exit_code = 1
			continue

		var path := "%s%s.tres" % [OUTPUT_DIR, npc.id]
		if ResourceSaver.save(npc, path) != OK:
			printerr("[generate_npc_data] failed to write %s" % path)
			exit_code = 1
			continue
		written += 1

	print("[generate_npc_data] wrote %d villagers to %s" % [written, OUTPUT_DIR])
	quit(exit_code)


## Every item id already on disk, in either directory.
##
## Loaded directly rather than through [ItemRegistry] for the reason documented in
## `generate_gathering_data.gd`: a `--script` run has no autoloads, and naming the
## registry here would pull [Log] into this tool's compile.
func _existing_item_ids() -> Dictionary:
	var known: Dictionary = {}
	for directory: String in [
		"res://resources/farming/items/", "res://resources/gathering/items/",
	]:
		var dir := DirAccess.open(directory)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with(".") and entry.ends_with(".tres"):
				var definition := ResourceLoader.load("%s%s" % [directory, entry]) as ItemDefinition
				if definition != null:
					known[definition.id] = true
			entry = dir.get_next()
		dir.list_dir_end()
	# Crop produce is an item id too, and the harvest names a crop id, so the crops
	# are folded in. Without this every loved gift that is a parsnip would fail the
	# generator on a technicality, which is the kind of error that gets "fixed" by
	# deleting the gift.
	for directory: String in ["res://resources/farming/crops/"]:
		var dir := DirAccess.open(directory)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with(".") and entry.ends_with(".tres"):
				var crop := ResourceLoader.load("%s%s" % [directory, entry])
				if crop != null and crop.get("id") != null:
					known[StringName(crop.get("id"))] = true
			entry = dir.get_next()
		dir.list_dir_end()
	return known