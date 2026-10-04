extends SceneTree
## Headless tool: writes the scenery `.tres` definitions into
## `resources/world/decoration/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_decoration_data.gd
##
## Generated for the same reason as `generate_gathering_data`: the balance lives in one
## readable table in source control, and the `.tres` stays the runtime format that
## [DecorationRegistry] loads.
##
## Every model here is one a gatherable node does **not** already own. That is checked,
## not assumed — a scenery definition sharing a model with a harvestable node is how the
## same tree ends up both decorative and choppable, and which of the two wins depends on
## which builder runs second.

const OUTPUT_DIR := "res://resources/world/decoration/"
const MODEL_DIR := "res://assets/models/quaternius/NaturePack/"

## Spelled out rather than taken from [ResourceNodeRegistry].
##
## Naming a const on a `class_name` script forces GDScript to compile that whole script
## into this tool, and the registry calls `Log.info` — an autoload, which does not exist
## in a `--script` run. So the reference does not fail, it fails to *compile*, with an
## error pointing at a line of a script the author of this tool never wrote. Two string
## constants are a fair price.
const HARVESTABLE_DIR := "res://resources/gathering/nodes/"
const HARVESTABLE_EXTENSION := ".tres"

## One entry per kind of scenery.
##
## The density reasoning, because "add more stuff" stops being an improvement quickly:
##
## - **Ground cover** (grass, flowers, small plants) is batched and non-colliding, and
##   carries the most instances. It is what stops open field reading as a green plane,
##   and it is the only thing here that must be cheap.
## - **Mid shrubs** collide, because a player expects to walk into a bush and be
##   stopped. Sparse — they are landmarks, not filler.
## - **Dead wood** (logs, stumps) is sparse and collides. Two or three of these do more
##   for a place than twenty flowers, because they are the detail nobody expects.
##
## `scale_jitter` is the difference between "scattered" and "sprinkled". Every instance
## at exactly the same size and angle is the giveaway.
const DECORATIONS: Array[Dictionary] = [
	# --- Ground cover: batched, no collider, no shadow ------------------------
	{
		"id": &"grass_tuft", "display_name": "Grass",
		"model": "Grass_Short.fbx", "tint": Color(0.92, 1.06, 0.82),
		"region": Vector2.ZERO, "spawn_radius": 96.0, "spawn_count": 260, "spawn_spacing": 0.0,
		"scale_jitter": 1.35, "batched": true, "collides": false, "casts_shadow": false,
	},
	{
		"id": &"wildflower", "display_name": "Wildflowers",
		"model": "Flowers.fbx", "tint": Color(1.05, 0.98, 1.0),
		"region": Vector2.ZERO, "spawn_radius": 92.0, "spawn_count": 120, "spawn_spacing": 0.0,
		"scale_jitter": 1.4, "batched": true, "collides": false, "casts_shadow": false,
	},
	{
		"id": &"low_plant", "display_name": "Low Plant",
		"model": "Plant_3.fbx", "tint": Color(0.95, 1.05, 0.85),
		"region": Vector2.ZERO, "spawn_radius": 90.0, "spawn_count": 90, "spawn_spacing": 0.0,
		"scale_jitter": 1.3, "batched": true, "collides": false, "casts_shadow": false,
	},
	{
		"id": &"meadow_plant", "display_name": "Meadow Plant",
		"model": "Plant_4.fbx", "tint": Color(1.0, 1.0, 0.92),
		"region": Vector2.ZERO, "spawn_radius": 90.0, "spawn_count": 80, "spawn_spacing": 0.0,
		"scale_jitter": 1.3, "batched": true, "collides": false, "casts_shadow": false,
	},
	{
		# An annulus, because the pond basin and a shoreline margin are both keep-out.
		# A disc centred on the pond could only ever put reeds out in the field.
		"id": &"reed_plant", "display_name": "Reed",
		"model": "Plant_5.fbx", "tint": Color(0.9, 1.05, 0.88),
		"region": Vector2(-14, 44), "spawn_inner_radius": 18.5, "spawn_radius": 26.0,
		"spawn_count": 70, "spawn_spacing": 0.0,
		"scale_jitter": 1.45, "batched": true, "collides": false, "casts_shadow": false,
	},
	{
		"id": &"field_grass", "display_name": "Field Grass",
		"model": "Wheat.fbx", "tint": Color(1.06, 1.0, 0.78),
		"region": Vector2(0, -20), "spawn_radius": 30.0, "spawn_count": 70, "spawn_spacing": 0.0,
		"scale_jitter": 1.25, "batched": true, "collides": false, "casts_shadow": false,
	},
	# --- Mid shrubs: collide, sparse ------------------------------------------
	{
		"id": &"thicket", "display_name": "Thicket",
		"model": "Bush_1.fbx", "tint": Color(0.9, 1.0, 0.84),
		"region": Vector2.ZERO, "spawn_radius": 94.0, "spawn_count": 34, "spawn_spacing": 4.0,
		"scale_jitter": 1.3, "collides": true, "collider_radius_scale": 0.4,
	},
	{
		"id": &"berry_bramble", "display_name": "Bramble",
		"model": "BushBerries_2.fbx", "tint": Color(0.95, 0.98, 0.9),
		"region": Vector2.ZERO, "spawn_radius": 88.0, "spawn_count": 18, "spawn_spacing": 6.0,
		"scale_jitter": 1.25, "collides": true, "collider_radius_scale": 0.42,
	},
	{
		"id": &"young_birch", "display_name": "Young Birch",
		"model": "BirchTree_2.fbx", "tint": Color(0.98, 1.02, 0.94),
		"region": Vector2(-42, 26), "spawn_radius": 40.0, "spawn_count": 12, "spawn_spacing": 5.0,
		"scale_jitter": 1.2, "collides": true, "collider_radius_scale": 0.2,
	},
	{
		"id": &"young_pine", "display_name": "Young Pine",
		"model": "PineTree_2.fbx", "tint": Color(0.94, 1.0, 0.98),
		# Wider than the pine gatherable's own 20m patch. Sharing that exact region
		# meant the saplings had nowhere left to go: the gatherables are placed first
		# and their 4.5m spacing filled it, so this placed 0 of 10.
		"region": Vector2(-48, 18), "spawn_radius": 30.0, "spawn_count": 10, "spawn_spacing": 5.0,
		"scale_jitter": 1.2, "collides": true, "collider_radius_scale": 0.2,
	},
	{
		# Also an annulus: willows stand on a pond's bank, not in the middle of it.
		"id": &"willow", "display_name": "Willow",
		"model": "Willow_1.fbx", "tint": Color(1.0, 1.0, 0.92),
		"region": Vector2(-14, 44), "spawn_inner_radius": 24.0, "spawn_radius": 38.0,
		"spawn_count": 6, "spawn_spacing": 8.0,
		"scale_jitter": 1.15, "collides": true, "collider_radius_scale": 0.22,
	},
	{
		"id": &"sapling_oak", "display_name": "Oak Sapling",
		"model": "CommonTree_1.fbx", "tint": Color(0.96, 1.04, 0.9),
		"region": Vector2(-42, 26), "spawn_radius": 46.0, "spawn_count": 14, "spawn_spacing": 4.5,
		"scale_jitter": 1.25, "collides": true, "collider_radius_scale": 0.18,
	},
	# --- Dead wood: sparse, collides, and the detail nobody expects ------------
	#
	# There is deliberately no stump here. `TreeStump.fbx` is the *depleted* art of every
	# felled tree, and the generator refuses any scenery that shares a model with a
	# gatherable. That is not pedantry: a permanent stump standing in the wood looks
	# exactly like a tree somebody already cut, and a player who walks into it expecting
	# four swings of wood and gets nothing has been told a lie by the art. Fallen logs
	# do not have that problem — nobody expects a log to be a tree.
	{
		"id": &"fallen_log", "display_name": "Fallen Log",
		"model": "WoodLog.fbx", "tint": Color(1.0, 0.98, 0.94),
		"region": Vector2(-42, 26), "spawn_radius": 48.0, "spawn_count": 9, "spawn_spacing": 7.0,
		"scale_jitter": 1.3, "collides": true, "collider_radius_scale": 0.55,
	},
	{
		"id": &"corn_clump", "display_name": "Corn Clump",
		"model": "Corn_1.fbx", "tint": Color(1.0, 1.0, 0.9),
		"region": Vector2(0, -20), "spawn_radius": 24.0, "spawn_count": 22, "spawn_spacing": 2.5,
		"scale_jitter": 1.2, "batched": true, "collides": false, "casts_shadow": false,
	},
	{
		"id": &"corn_clump_tall", "display_name": "Tall Corn Clump",
		"model": "Corn_2.fbx", "tint": Color(1.0, 1.0, 0.88),
		"region": Vector2(0, -20), "spawn_radius": 26.0, "spawn_count": 16, "spawn_spacing": 3.0,
		"scale_jitter": 1.2, "batched": true, "collides": false, "casts_shadow": false,
	},
]


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		if err != OK:
			printerr("[generate_decoration_data] cannot create %s: %d" % [OUTPUT_DIR, err])
			quit(1)
			return

	var harvestable := _harvestable_models()
	var exit_code := 0
	var written := 0
	var seen: Dictionary = {}

	for spec: Dictionary in DECORATIONS:
		var data := DecorationData.new()
		data.id = spec["id"]
		data.display_name = spec["display_name"]
		data.model = "%s%s" % [MODEL_DIR, spec["model"]]
		data.model_tint = spec.get("tint", Color(1, 1, 1, 1))
		data.scale_jitter = spec.get("scale_jitter", 1.0)
		data.spawn_region = spec["region"]
		data.spawn_radius = spec["spawn_radius"]
		data.spawn_inner_radius = spec.get("spawn_inner_radius", 0.0)
		data.spawn_count = spec["spawn_count"]
		data.spawn_spacing = spec.get("spawn_spacing", 0.0)
		data.batched = spec.get("batched", false)
		data.collides = spec.get("collides", true)
		data.collider_radius_scale = spec.get("collider_radius_scale", 0.3)
		data.casts_shadow = spec.get("casts_shadow", true)

		if not data.is_valid():
			printerr("[generate_decoration_data] %s is invalid" % data.id)
			exit_code = 1
			continue
		if seen.has(data.id):
			printerr("[generate_decoration_data] duplicate id '%s' in the table" % data.id)
			exit_code = 1
			continue
		seen[data.id] = true
		# A scenery definition pointing at a harvestable's model makes that model both
		# decorative and choppable, and which of the two a player gets depends on which
		# builder happens to run second.
		if harvestable.has(data.model):
			printerr("[generate_decoration_data] %s uses %s, which a gatherable already owns" % [
				data.id, data.model.get_file(),
			])
			exit_code = 1
			continue
		if not ModelArt.can_load(data.model):
			printerr("[generate_decoration_data] %s cannot load %s" % [data.id, data.model])
			exit_code = 1
			continue
		var path := "%s%s.tres" % [OUTPUT_DIR, data.id]
		if ResourceSaver.save(data, path) != OK:
			printerr("[generate_decoration_data] failed to write %s" % path)
			exit_code = 1
			continue
		written += 1

	# A batched prop with a collider would put a collider inside a MultiMesh, which
	# cannot have one. The pair is a contradiction, so it is an error rather than a
	# prop the player walks through with no explanation.
	for spec: Dictionary in DECORATIONS:
		if spec.get("batched", false) and spec.get("collides", true):
			printerr("[generate_decoration_data] '%s' is batched and collides; a MultiMesh cannot collide" % spec["id"])
			exit_code = 1
	# An inner radius outside the outer one is an inverted annulus, which places nothing
	# and reports "placed 0 of N" for a reason no reader can see in the table.
	for spec: Dictionary in DECORATIONS:
		var inner := float(spec.get("spawn_inner_radius", 0.0))
		if inner > 0.0 and inner >= float(spec["spawn_radius"]):
			printerr("[generate_decoration_data] '%s' has an inner radius of %.1f outside its outer radius of %.1f" % [
				spec["id"], inner, float(spec["spawn_radius"]),
			])
			exit_code = 1

	print("[generate_decoration_data] wrote %d of %d decorations to %s" % [
		written, DECORATIONS.size(), OUTPUT_DIR,
	])
	quit(exit_code)


## Model paths a gatherable node already draws, read from the `.tres` files rather than
## from [ResourceNodeRegistry]: the registry skips nodes it considers invalid, and this
## check is about the table in source, not about what loaded.
func _harvestable_models() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(HARVESTABLE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(HARVESTABLE_EXTENSION):
			var data := ResourceLoader.load(
				"%s%s" % [HARVESTABLE_DIR, entry]
			) as ResourceNodeData
			if data != null:
				out[data.model] = true
				out[data.depleted_model] = true
		entry = dir.get_next()
	dir.list_dir_end()
	return out