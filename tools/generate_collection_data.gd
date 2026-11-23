extends SceneTree
## Writes the six collection definitions. Run:
##   Godot --headless --path . --script res://tools/generate_collection_data.gd

const OUT := "res://resources/collections/"
const DATA_SCRIPT := "res://resources/collections/collection_data.gd"
const TIER_SCRIPT := "res://resources/collections/collection_tier.gd"

const COLLECTIONS: Array[Dictionary] = [
	{
		"id": &"fields", "name": "Fields", "ember": &"fields", "kind": "item",
		"entries": [&"parsnip", &"potato", &"cauliflower", &"corn", &"tomato",
			&"pumpkin", &"melon", &"yam"],
		"tiers": [[0.4, &"orchard_path"], [0.7, &"sprinkler_recipe"], [1.0, &"ember_fields"]],
	},
	{
		"id": &"waters", "name": "Waters", "ember": &"waters", "kind": "item",
		"entries": [&"fish_trout", &"fish_smilte", &"fish_darter", &"fish_eel",
			&"fish_pike", &"fish_sunfin"],
		"tiers": [[0.4, &"pond_pier"], [0.7, &"bait_recipe"], [1.0, &"ember_waters"]],
	},
	{
		"id": &"stone", "name": "Stone", "ember": &"stone", "kind": "item",
		"entries": [&"copper_ore", &"iron_ore", &"stone", &"stone_brick",
			&"ore_flux", &"plank"],
		"tiers": [[0.4, &"deep_mines_stairs"], [0.7, &"lantern_recipe"], [1.0, &"ember_stone"]],
	},
	{
		"id": &"table", "name": "Table", "ember": &"table", "kind": "item",
		"entries": [&"berry_jam", &"onion_soup", &"egg_omelette", &"milk_tea",
			&"fish_stew", &"trail_mix"],
		"tiers": [[0.4, &"advanced_recipes"], [0.7, &"festival_feast"], [1.0, &"ember_table"]],
	},
	{
		"id": &"wilds", "name": "Wilds", "ember": &"wilds", "kind": "item",
		"entries": [&"spring_onion", &"wild_berry", &"wild_horseradish", &"wood",
			&"egg", &"milk"],
		"tiers": [[0.4, &"forest_road"], [0.7, &"foraging_basket"], [1.0, &"ember_wilds"]],
	},
	{
		"id": &"hearts", "name": "Hearts", "ember": &"hearts", "kind": "npc",
		"entries": [&"mira", &"bram", &"fen", &"odette", &"sable", &"aurel",
			&"lyra", &"cassia", &"elke", &"garrick", &"halda", &"dorian"],
		"tiers": [[0.4, &"plinth_wakes"], [0.7, &"heart_event"], [1.0, &"ember_hearts"]],
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(DATA_SCRIPT) as GDScript
	var tier_script := load(TIER_SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in COLLECTIONS:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("ember", spec["ember"])
		data.set("kind", String(spec["kind"]))
		var entries: Array[StringName] = []
		for entry: StringName in (spec["entries"] as Array):
			entries.append(entry)
		data.set("entries", entries)
		var tiers: Array[CollectionTier] = []
		for row: Array in spec["tiers"]:
			var tier: Object = tier_script.new()
			tier.set("threshold", float(row[0]))
			tier.set("unlock", row[1])
			tier.set("ember", spec["ember"])
			tiers.append(tier)
		data.set("tiers", tiers)
		if not bool(data.call("is_valid")):
			printerr("[generate_collection_data] invalid %s (entries=%d tiers=%d kind=%s ember=%s)" % [
				spec["id"], (data.get("entries") as Array).size(),
				(data.get("tiers") as Array).size(), str(data.get("kind")),
				str(data.get("ember")),
			])
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_collection_data] wrote %d collections" % COLLECTIONS.size())
	quit(1 if errors > 0 else 0)
