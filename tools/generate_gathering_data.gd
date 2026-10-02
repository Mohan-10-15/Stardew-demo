extends SceneTree
## Headless tool: writes the gathering `.tres` definitions into
## `resources/gathering/nodes/` and `resources/gathering/items/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_gathering_data.gd
##
## Generated rather than hand-authored for the same reason as [generate_crop_data]:
## the balance numbers live in one readable table in source control, and the `.tres`
## files stay the runtime format that [ResourceNodeRegistry] and [ItemRegistry] load.
##
## A `.tres` referencing a model that will not load, or an item id nothing defines,
## is a silent empty valley rather than an error, so both are checked here and fail
## the generator instead.

const NODE_OUTPUT_DIR := "res://resources/gathering/nodes/"
const ITEM_OUTPUT_DIR := "res://resources/gathering/items/"
const MODEL_DIR := "res://assets/models/quaternius/NaturePack/"

## One entry per gatherable thing. The keys map one-to-one onto
## [ResourceNodeData]'s fields; `yields` is a list of `[item_id, min, max]`.
##
## The balance reasoning, so the next retune is a decision rather than a guess:
##
## - **Trees** are the slow, valuable tier. Four swings and 8 stamina for a basic
##   oak is roughly a quarter of a morning's stamina for a handful of wood, which is
##   the point: wood is a *starting* resource, not an income. The ancient oak wants
##   nine logs for twice the effort and a two-day wait, so it is a goal rather than
##   a farm.
## - **Rocks** are the cheap tier. Two or three swings and 4 stamina for stone,
##   because stone is needed for building, not because it is scarce.
## - **Ore** is the gated tier, and the only thing that *refuses* a weak tool rather
##   than slowing it. Copper at tier 2 and iron at tier 3 mean the first two tools
##   the player is likely to find cannot touch them, so a mine upgrade is a real
##   decision. The nature pack has no ore, so these are tinted rocks — the tint is
##   what sells it, and [ResourceNode] multiplies the model's own albedo rather than
##   replacing it.
## - **Forage** is free, instant, and regrows in days. It is the safety net: a player
##   with no tools at all can still eat.
##
## `region` and `radius` place the patch; `count` is how many; `spacing` keeps them
## from growing inside one another. A zero `count` means "authored, not scattered".
const NODES: Array[Dictionary] = [
	# --- Trees ---------------------------------------------------------------
	{
		"id": &"oak", "display_name": "Oak", "category": 0,
		"tool_action": &"chop", "model": "CommonTree_2.fbx", "depleted_model": "TreeStump.fbx",
		"hit_points": 4, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.35, "respawn_days": 12,
		"collider_radius_scale": 0.22, "aim_radius_scale": 0.55,
		"region": Vector2(-42, 26), "spawn_radius": 30.0, "spawn_count": 22, "spawn_spacing": 4.5,
		"yields": [[&"wood", 3, 5]],
	},
	{
		"id": &"birch", "display_name": "Birch", "category": 0,
		"tool_action": &"chop", "model": "BirchTree_1.fbx", "depleted_model": "TreeStump.fbx",
		"hit_points": 3, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.3, "respawn_days": 10,
		"collider_radius_scale": 0.2, "aim_radius_scale": 0.5,
		"region": Vector2(-42, 26), "spawn_radius": 30.0, "spawn_count": 10, "spawn_spacing": 4.0,
		"yields": [[&"wood", 3, 4]],
	},
	{
		"id": &"pine", "display_name": "Pine", "category": 0,
		"tool_action": &"chop", "model": "PineTree_1.fbx", "depleted_model": "TreeStump.fbx",
		# A soft resistance: a basic axe is *allowed*, just at double the swings. The
		# player learns the upgrade exists without ever being told "no".
		"hit_points": 4, "resist_tier": 1, "weak_tool_multiplier": 2,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.35, "respawn_days": 14,
		"collider_radius_scale": 0.22, "aim_radius_scale": 0.5,
		"region": Vector2(-52, 14), "spawn_radius": 20.0, "spawn_count": 10, "spawn_spacing": 4.5,
		"yields": [[&"wood", 4, 6]],
	},
	{
		"id": &"ancient_oak", "display_name": "Ancient Oak", "category": 0,
		"tool_action": &"chop", "model": "CommonTree_3.fbx", "depleted_model": "TreeStump.fbx",
		"hit_points": 8, "resist_tier": 2, "weak_tool_multiplier": 2,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.5, "respawn_days": 21,
		"collider_radius_scale": 0.28, "aim_radius_scale": 0.6,
		"region": Vector2(-58, 36), "spawn_radius": 16.0, "spawn_count": 4, "spawn_spacing": 7.0,
		"yields": [[&"wood", 6, 9]],
	},
	# --- Rocks and ore -------------------------------------------------------
	{
		"id": &"rock", "display_name": "Rock", "category": 1,
		"tool_action": &"mine", "model": "Rock_1.fbx",
		"hit_points": 2, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.2, "respawn_days": 8,
		"collider_radius_scale": 0.7, "aim_radius_scale": 0.9,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 24, "spawn_spacing": 5.0,
		"yields": [[&"stone", 1, 2]],
	},
	{
		"id": &"boulder", "display_name": "Boulder", "category": 1,
		"tool_action": &"mine", "model": "Rock_3.fbx",
		"hit_points": 3, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.25, "respawn_days": 10,
		"collider_radius_scale": 0.8, "aim_radius_scale": 0.95,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 12, "spawn_spacing": 6.0,
		"yields": [[&"stone", 2, 3]],
	},
	{
		"id": &"mossy_rock", "display_name": "Mossy Rock", "category": 1,
		"tool_action": &"mine", "model": "Rock_Moss_1.fbx",
		"hit_points": 3, "resist_tier": 1, "weak_tool_multiplier": 2,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.25, "respawn_days": 10,
		"collider_radius_scale": 0.75, "aim_radius_scale": 0.9,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 10, "spawn_spacing": 6.0,
		"yields": [[&"stone", 1, 3]],
	},
	{
		"id": &"copper_vein", "display_name": "Copper Vein", "category": 1,
		"tool_action": &"mine", "model": "Rock_Moss_2.fbx",
		"model_tint": Color(0.78, 0.45, 0.25, 1.0),
		# Hard gate, not a soft one. Copper is the first thing in the game that says
		# "come back with a better tool", and a refusal is far clearer than a swing
		# that mysteriously does nothing.
		"hit_points": 4, "resist_tier": 2, "weak_tool_multiplier": 1,
		"blocks_weak_tools": true, "hit_hold_seconds": 0.3, "respawn_days": 14,
		"collider_radius_scale": 0.75, "aim_radius_scale": 0.9,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 6, "spawn_spacing": 8.0,
		"yields": [[&"copper_ore", 1, 2], [&"stone", 1, 1]],
	},
	{
		"id": &"iron_vein", "display_name": "Iron Vein", "category": 1,
		"tool_action": &"mine", "model": "Rock_2.fbx",
		"model_tint": Color(0.45, 0.44, 0.48, 1.0),
		"hit_points": 6, "resist_tier": 3, "weak_tool_multiplier": 1,
		"blocks_weak_tools": true, "hit_hold_seconds": 0.35, "respawn_days": 21,
		"collider_radius_scale": 0.75, "aim_radius_scale": 0.9,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 4, "spawn_spacing": 9.0,
		"yields": [[&"iron_ore", 1, 1], [&"stone", 1, 2]],
	},
	# --- Forage --------------------------------------------------------------
	{
		"id": &"spring_onion_patch", "display_name": "Spring Onion", "category": 2,
		"tool_action": &"", "model": "Plant_1.fbx",
		"hit_points": 1, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.0, "respawn_days": 3,
		"collider_radius_scale": 0.3, "aim_radius_scale": 0.7,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 14, "spawn_spacing": 3.5,
		"yields": [[&"spring_onion", 1, 2]],
	},
	{
		"id": &"horseradish_patch", "display_name": "Wild Horseradish", "category": 2,
		"tool_action": &"", "model": "Plant_2.fbx",
		"hit_points": 1, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.0, "respawn_days": 4,
		"collider_radius_scale": 0.3, "aim_radius_scale": 0.7,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 10, "spawn_spacing": 3.5,
		"yields": [[&"wild_horseradish", 1, 1]],
	},
	{
		"id": &"berry_bush", "display_name": "Berry Bush", "category": 2,
		"tool_action": &"", "model": "BushBerries_1.fbx",
		"hit_points": 1, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.0, "respawn_days": 4,
		"collider_radius_scale": 0.45, "aim_radius_scale": 0.85,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 12, "spawn_spacing": 4.0,
		"yields": [[&"wild_berry", 1, 3]],
	},
	{
		"id": &"flower_bush", "display_name": "Flowering Bush", "category": 2,
		"tool_action": &"", "model": "Bush_2.fbx",
		"hit_points": 1, "resist_tier": 0, "weak_tool_multiplier": 1,
		"blocks_weak_tools": false, "hit_hold_seconds": 0.0, "respawn_days": 5,
		"collider_radius_scale": 0.45, "aim_radius_scale": 0.85,
		"region": Vector2.ZERO, "spawn_radius": 70.0, "spawn_count": 10, "spawn_spacing": 4.0,
		"yields": [[&"wild_berry", 1, 1]],
	},
]

## Tool tiers and the materials they unlock, plus the raw ore.
##
## Durability roughly quadruples per tier and the stamina cost rises only at steel,
## so the first upgrade is a bargain and the last is a real commitment. That shape
## is deliberate: a player should replace the axe they start with within a week, and
## hesitate over the third one.
const ITEMS: Array[Dictionary] = [
	# --- Axes ----------------------------------------------------------------
	{
		"id": &"axe", "display_name": "Axe", "category": 2,
		"sell_price": 0, "buy_price": 350,
		"description": "Fells a softwood tree in four swings. Splits eventually.",
		"icon_color": Color(0.55, 0.38, 0.22, 1.0),
		"uses_durability": true, "durability": 40, "stamina_cost": 2,
		"tool_action": &"chop", "tool_tier": 1,
	},
	{
		"id": &"copper_axe", "display_name": "Copper Axe", "category": 2,
		"sell_price": 0, "buy_price": 800,
		"description": "Reaches the pines, and the ancient oak with patience.",
		"icon_color": Color(0.72, 0.45, 0.28, 1.0),
		"uses_durability": true, "durability": 70, "stamina_cost": 2,
		"tool_action": &"chop", "tool_tier": 2,
	},
	{
		"id": &"iron_axe", "display_name": "Iron Axe", "category": 2,
		"sell_price": 0, "buy_price": 1800,
		"description": "A tree-feller's axe. The wood stack pays for itself.",
		"icon_color": Color(0.62, 0.64, 0.68, 1.0),
		"uses_durability": true, "durability": 110, "stamina_cost": 2,
		"tool_action": &"chop", "tool_tier": 3,
	},
	{
		"id": &"steel_axe", "display_name": "Steel Axe", "category": 2,
		"sell_price": 0, "buy_price": 3600,
		"description": "Takes an ancient oak down before breakfast.",
		"icon_color": Color(0.78, 0.80, 0.84, 1.0),
		"uses_durability": true, "durability": 180, "stamina_cost": 3,
		"tool_action": &"chop", "tool_tier": 4,
	},
	# --- Pickaxes ------------------------------------------------------------
	{
		"id": &"pickaxe", "display_name": "Pickaxe", "category": 2,
		"sell_price": 0, "buy_price": 350,
		"description": "Breaks stone. Barely.",
		"icon_color": Color(0.48, 0.50, 0.54, 1.0),
		"uses_durability": true, "durability": 40, "stamina_cost": 2,
		"tool_action": &"mine", "tool_tier": 1,
	},
	{
		"id": &"copper_pickaxe", "display_name": "Copper Pickaxe", "category": 2,
		"sell_price": 0, "buy_price": 800,
		"description": "Opens a copper vein.",
		"icon_color": Color(0.72, 0.45, 0.28, 1.0),
		"uses_durability": true, "durability": 70, "stamina_cost": 2,
		"tool_action": &"mine", "tool_tier": 2,
	},
	{
		"id": &"iron_pickaxe", "display_name": "Iron Pickaxe", "category": 2,
		"sell_price": 0, "buy_price": 1800,
		"description": "Opens an iron vein, and mossy rock twice as fast.",
		"icon_color": Color(0.62, 0.64, 0.68, 1.0),
		"uses_durability": true, "durability": 110, "stamina_cost": 2,
		"tool_action": &"mine", "tool_tier": 3,
	},
	{
		"id": &"steel_pickaxe", "display_name": "Steel Pickaxe", "category": 2,
		"sell_price": 0, "buy_price": 3600,
		"description": "The only thing that earns its keep on an iron vein.",
		"icon_color": Color(0.78, 0.80, 0.84, 1.0),
		"uses_durability": true, "durability": 180, "stamina_cost": 3,
		"tool_action": &"mine", "tool_tier": 4,
	},
	# --- Materials and forage ------------------------------------------------
	{
		"id": &"copper_ore", "display_name": "Copper Ore", "category": 4,
		"sell_price": 12, "buy_price": 0,
		"description": "Raw, heavy, and the start of every upgrade.",
		"icon_color": Color(0.72, 0.45, 0.28, 1.0),
	},
	{
		"id": &"iron_ore", "display_name": "Iron Ore", "category": 4,
		"sell_price": 30, "buy_price": 0,
		"description": "Worth the walk back from the far rocks.",
		"icon_color": Color(0.52, 0.53, 0.58, 1.0),
	},
	{
		"id": &"wild_berry", "display_name": "Wild Berry", "category": 3,
		"sell_price": 20, "buy_price": 0,
		"description": "Free, instant, and grows back in days.",
		"icon_color": Color(0.62, 0.22, 0.32, 1.0),
	},
]


func _initialize() -> void:
	for directory: String in [NODE_OUTPUT_DIR, ITEM_OUTPUT_DIR]:
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			if err != OK:
				printerr("[generate_gathering_data] cannot create %s: %d" % [directory, err])
				quit(1)
				return

	var known_items := _existing_item_ids()
	var exit_code := 0

	# Items first, so a node's yields can be checked against a set that already
	# includes this run's new ores and berries.
	var written_items := 0
	for spec: Dictionary in ITEMS:
		var item := ItemDefinition.new()
		item.id = spec["id"]
		item.display_name = spec["display_name"]
		item.category = spec["category"]
		item.sell_price = spec["sell_price"]
		item.buy_price = spec["buy_price"]
		item.description = spec["description"]
		item.icon_color = spec["icon_color"]
		if spec.has("uses_durability"):
			item.uses_durability = spec["uses_durability"]
			item.durability = spec["durability"]
			item.stamina_cost = spec["stamina_cost"]
			item.tool_action = spec["tool_action"]
			item.tool_tier = spec["tool_tier"]
		if not item.is_valid():
			printerr("[generate_gathering_data] item %s is invalid" % item.id)
			exit_code = 1
			continue
		var path := "%s%s.tres" % [ITEM_OUTPUT_DIR, item.id]
		if ResourceSaver.save(item, path) != OK:
			printerr("[generate_gathering_data] failed to write %s" % path)
			exit_code = 1
			continue
		known_items[item.id] = true
		written_items += 1

	var written_nodes := 0
	for spec: Dictionary in NODES:
		var node := ResourceNodeData.new()
		node.id = spec["id"]
		node.display_name = spec["display_name"]
		node.category = spec["category"]
		node.tool_action = spec["tool_action"]
		node.model = MODEL_DIR + String(spec["model"])
		node.depleted_model = MODEL_DIR + String(spec["depleted_model"]) if spec.has("depleted_model") else ""
		if spec.has("model_tint"):
			node.model_tint = spec["model_tint"]
		node.hit_points = spec["hit_points"]
		node.resist_tier = spec["resist_tier"]
		node.weak_tool_multiplier = spec["weak_tool_multiplier"]
		node.blocks_weak_tools = spec["blocks_weak_tools"]
		node.hit_hold_seconds = spec["hit_hold_seconds"]
		node.respawn_days = spec["respawn_days"]
		node.collider_radius_scale = spec["collider_radius_scale"]
		node.aim_radius_scale = spec["aim_radius_scale"]
		node.spawn_region = spec["region"]
		node.spawn_radius = spec["spawn_radius"]
		node.spawn_count = spec["spawn_count"]
		node.spawn_spacing = spec["spawn_spacing"]

		for line: Array in spec["yields"]:
			var yield_resource := GatherYield.new()
			yield_resource.item_id = line[0]
			yield_resource.min_amount = line[1]
			yield_resource.max_amount = line[2]
			node.yields.append(yield_resource)

		if not node.is_valid():
			printerr("[generate_gathering_data] node %s is invalid" % node.id)
			exit_code = 1
			continue
		# A yield naming an item nothing defines drops nothing at all when the node
		# breaks, and the only symptom is an empty drop. Fail here instead.
		for line: GatherYield in node.yields:
			if not known_items.has(line.item_id):
				printerr("[generate_gathering_data] %s yields unknown item '%s'" % [
					node.id, line.item_id,
				])
				exit_code = 1
		for model_path: String in [node.model, node.depleted_model]:
			if not model_path.is_empty() and not ModelArt.can_load(model_path):
				printerr("[generate_gathering_data] %s cannot load %s" % [node.id, model_path])
				exit_code = 1
		var path := "%s%s.tres" % [NODE_OUTPUT_DIR, node.id]
		if ResourceSaver.save(node, path) != OK:
			printerr("[generate_gathering_data] failed to write %s" % path)
			exit_code = 1
			continue
		written_nodes += 1

	print("[generate_gathering_data] wrote %d items and %d nodes" % [
		written_items, written_nodes,
	])
	quit(exit_code)


## Every item id already on disk, in either directory.
##
## Read by loading the definitions directly rather than through [ItemRegistry]: a
## `--script` run has no autoloads, and naming the registry here would pull
## [Log] into this tool's compile — the exact trap `AGENTS.md` documents.
func _existing_item_ids() -> Dictionary:
	var known: Dictionary = {}
	for directory: String in [ITEM_OUTPUT_DIR, "res://resources/farming/items/"]:
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
	return known