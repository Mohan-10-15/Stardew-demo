extends SceneTree
## Headless tool: writes the item `.tres` definitions into
## `resources/farming/items/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_item_data.gd
##
## Crop *produce* is not defined here: a harvested crop is looked up by its crop
## id, so defining `parsnip` twice as both a crop and an item would give the shop
## and the farm two sources of truth for the same sell price. What is defined is
## everything the crop system does not already describe: seed packets, tools, and
## forage.
##
## Seed packet ids follow the crop they plant, with a `_seeds` suffix, and the
## mapping is written into each definition's `seed_id` rather than inferred.

const OUTPUT_DIR := "res://resources/farming/items/"

## crop_id, seed suffix, buy price, icon colour
const SEEDS: Array[Dictionary] = [
	{"id": &"parsnip_seeds", "seed_id": &"parsnip", "buy_price": 20, "color": Color(0.72, 0.62, 0.38)},
	{"id": &"potato_seeds", "seed_id": &"potato", "buy_price": 50, "color": Color(0.66, 0.58, 0.36)},
	{"id": &"cauliflower_seeds", "seed_id": &"cauliflower", "buy_price": 80, "color": Color(0.88, 0.86, 0.74)},
	{"id": &"melon_seeds", "seed_id": &"melon", "buy_price": 80, "color": Color(0.36, 0.58, 0.30)},
	{"id": &"tomato_seeds", "seed_id": &"tomato", "buy_price": 50, "color": Color(0.74, 0.28, 0.20)},
	{"id": &"corn_seeds", "seed_id": &"corn", "buy_price": 150, "color": Color(0.88, 0.74, 0.26)},
	{"id": &"pumpkin_seeds", "seed_id": &"pumpkin", "buy_price": 100, "color": Color(0.80, 0.46, 0.16)},
	{"id": &"yam_seeds", "seed_id": &"yam", "buy_price": 60, "color": Color(0.68, 0.36, 0.50)},
	{"id": &"winter_seeds", "seed_id": &"winter_seeds", "buy_price": 30, "color": Color(0.66, 0.80, 0.68)},
]

## id, display name, tool_action, durability, stamina_cost, sell_price, icon colour
const TOOLS: Array[Dictionary] = [
	{
		"id": &"hoe", "display_name": "Hoe", "tool_action": &"till",
		"durability": 0, "stamina_cost": 2, "sell_price": 0,
		"color": Color(0.62, 0.48, 0.30),
	},
	{
		"id": &"watering_can", "display_name": "Watering Can", "tool_action": &"water",
		# Durability so a player who never refills anything eventually has to
		# think about the can. Group 13 (economy) is where refilling arrives.
		"durability": 60, "stamina_cost": 1, "sell_price": 0,
		"color": Color(0.42, 0.58, 0.66),
	},
	{
		"id": &"scythe", "display_name": "Scythe", "tool_action": &"",
		# No action yet, so nothing charges for it. The cost is here anyway so the
		# day the scythe clears a row it does not also need a balance pass.
		"durability": 0, "stamina_cost": 1, "sell_price": 0,
		"color": Color(0.70, 0.72, 0.74),
	},
]

## id, display name, sell_price, category, colour, description
const OTHER: Array[Dictionary] = [
	{
		"id": &"wood", "display_name": "Wood", "sell_price": 4,
		"category": ItemDefinition.Category.MATERIAL,
		"color": Color(0.44, 0.31, 0.18),
		"description": "Split and stacked. Burns, or builds.",
	},
	{
		"id": &"stone", "display_name": "Stone", "sell_price": 3,
		"category": ItemDefinition.Category.MATERIAL,
		"color": Color(0.55, 0.55, 0.58),
		"description": "Heavy, dull, and everywhere.",
	},
	{
		"id": &"spring_onion", "display_name": "Spring Onion", "sell_price": 30,
		"category": ItemDefinition.Category.FORAGE,
		"color": Color(0.66, 0.82, 0.52),
		"description": "Pungent enough to clear your head on a long walk.",
	},
	{
		"id": &"wild_horseradish", "display_name": "Wild Horseradish", "sell_price": 50,
		"category": ItemDefinition.Category.FORAGE,
		"color": Color(0.74, 0.78, 0.40),
		"description": "Found in the spring clearing.",
	},
]


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		if err != OK:
			printerr("[generate_item_data] cannot create %s: %d" % [OUTPUT_DIR, err])
			quit(1)
			return

	var written := 0

	for spec: Dictionary in SEEDS:
		var crop := _load_crop(StringName(spec["seed_id"]))
		var crop_name := "Crop"
		if crop != null:
			crop_name = crop.display_name
		var seed := ItemDefinition.new()
		seed.id = spec["id"]
		seed.display_name = "%s Seeds" % crop_name
		seed.category = ItemDefinition.Category.SEED
		seed.seed_id = spec["seed_id"]
		seed.buy_price = spec["buy_price"]
		seed.icon_color = spec["color"]
		seed.description = "Plant in %s." % _season_phrase(String(spec["seed_id"]))
		if not _write(seed, written):
			quit(1)
			return
		written += 1

	for spec: Dictionary in TOOLS:
		var tool := ItemDefinition.new()
		tool.id = spec["id"]
		tool.display_name = spec["display_name"]
		tool.category = ItemDefinition.Category.TOOL
		tool.tool_action = spec["tool_action"]
		tool.durability = spec["durability"]
		tool.uses_durability = int(spec["durability"]) > 0
		tool.stamina_cost = spec["stamina_cost"]
		tool.sell_price = spec["sell_price"]
		tool.icon_color = spec["color"]
		if not _write(tool, written):
			quit(1)
			return
		written += 1

	for spec: Dictionary in OTHER:
		var item := ItemDefinition.new()
		item.id = spec["id"]
		item.display_name = spec["display_name"]
		item.category = spec["category"]
		item.sell_price = spec["sell_price"]
		item.icon_color = spec["color"]
		item.description = spec["description"]
		if not _write(item, written):
			quit(1)
			return
		written += 1

	print("[generate_item_data] wrote %d items to %s" % [written, OUTPUT_DIR])
	quit(0)


func _write(item: ItemDefinition, index: int) -> bool:
	if not item.is_valid():
		printerr("[generate_item_data] item %d is invalid" % index)
		return false
	var path := "%s%s.tres" % [OUTPUT_DIR, item.id]
	if ResourceSaver.save(item, path) != OK:
		printerr("[generate_item_data] failed to write %s" % path)
		return false
	return true


## Loads a crop definition straight off disk.
##
## Deliberately *not* [CropRegistry]. A `--script` run compiles this file before
## the autoloads are added to the tree, and `CropRegistry` logs through `Log`, so
## touching it from here is a compile error — see `AGENTS.md`, "Two Godot-specific
## traps". Loading the `.tres` directly needs nothing but [ResourceLoader], which
## is what makes this generator runnable before the game has ever booted.
func _load_crop(crop_id: StringName) -> CropData:
	var path := "res://resources/farming/crops/%s.tres" % crop_id
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	if res is CropData:
		return res as CropData
	return null


## "spring" / "summer" from a crop id, for a seed packet's description.
func _season_phrase(crop_id: String) -> String:
	var data := _load_crop(StringName(crop_id))
	if data == null or data.seasons.is_empty():
		return "any season"
	var names: Array[String] = []
	for season: int in data.seasons:
		names.append(Clock.season_name(season).to_lower())
	if names.size() == 1:
		return names[0]
	return " or ".join(names)