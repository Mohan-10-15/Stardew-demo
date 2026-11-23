extends SceneTree
## Writes the voxel block definitions (W3.2). Run:
##   Godot --headless --path . --script res://tools/generate_block_data.gd

const OUT := "res://resources/voxel/blocks/"
const SCRIPT := "res://resources/voxel/block_data.gd"

const BLOCKS: Array[Dictionary] = [
	{"id": &"hollowbrook_stone", "name": "Hollow Stone", "hard": 1.5, "tool": &"pickaxe", "tier": 1, "drop": &"stone", "sound": &"stone"},
	{"id": &"hollowbrook_soil", "name": "Hollow Soil", "hard": 0.6, "tool": &"hoe", "tier": 0, "drop": &"stone", "sound": &"dirt"},
	{"id": &"hollowbrook_grass", "name": "Hollow Turf", "hard": 0.5, "tool": &"hoe", "tier": 0, "drop": &"stone", "sound": &"grass"},
	{"id": &"fence_block", "name": "Fence Rail", "hard": 0.8, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"copper_vein_block", "name": "Copper Vein", "hard": 2.0, "tool": &"pickaxe", "tier": 1, "drop": &"copper_ore", "sound": &"stone"},
	{"id": &"iron_vein_block", "name": "Iron Vein", "hard": 3.0, "tool": &"pickaxe", "tier": 2, "drop": &"iron_ore", "sound": &"stone"},
	{"id": &"gold_vein_block", "name": "Gold Vein", "hard": 3.6, "tool": &"pickaxe", "tier": 3, "drop": &"iron_ore", "sound": &"stone"},
	{"id": &"ember_crystal_block", "name": "Ember Crystal", "hard": 4.5, "tool": &"pickaxe", "tier": 4, "drop": &"wild_berry", "sound": &"glass", "light": 7},
	{"id": &"water_block", "name": "Still Water", "hard": 0.2, "tool": &"", "tier": 0, "sound": &"water", "collision": "water", "transparent": true},
	{"id": &"oak_log", "name": "Oak Log", "hard": 1.2, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"oak_planks", "name": "Oak Planks", "hard": 0.9, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"birch_log", "name": "Birch Log", "hard": 1.1, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"birch_planks", "name": "Birch Planks", "hard": 0.8, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"pine_log", "name": "Pine Log", "hard": 1.3, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"pine_planks", "name": "Pine Planks", "hard": 0.9, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"cobble_block", "name": "Cobblestone", "hard": 2.0, "tool": &"pickaxe", "tier": 1, "drop": &"stone", "sound": &"stone"},
	{"id": &"brick_block", "name": "Kiln Brick", "hard": 2.2, "tool": &"pickaxe", "tier": 1, "drop": &"stone", "sound": &"stone"},
	{"id": &"sandstone_block", "name": "Sandstone", "hard": 1.0, "tool": &"pickaxe", "tier": 1, "drop": &"stone", "sound": &"dirt"},
	{"id": &"obsidian_block", "name": "Obsidian", "hard": 6.0, "tool": &"pickaxe", "tier": 4, "drop": &"stone", "sound": &"stone"},
	{"id": &"glass_block", "name": "Clear Glass", "hard": 0.4, "tool": &"", "tier": 0, "sound": &"glass", "transparent": true},
	{"id": &"torch_block", "name": "Torch", "hard": 0.2, "tool": &"", "tier": 0, "sound": &"wood", "light": 12, "transparent": true},
	{"id": &"lantern_block", "name": "Lantern", "hard": 0.4, "tool": &"", "tier": 0, "sound": &"metal", "light": 14, "transparent": true},
	{"id": &"chest_block", "name": "Storage Chest", "hard": 1.0, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"workbench_block", "name": "Workbench", "hard": 1.0, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"furnace_block", "name": "Ore Furnace", "hard": 2.4, "tool": &"pickaxe", "tier": 1, "drop": &"stone", "sound": &"stone", "light": 5},
	{"id": &"jam_jar_block", "name": "Berry Press", "hard": 0.8, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"smoker_block", "name": "Fish Smoker", "hard": 1.1, "tool": &"axe", "tier": 1, "drop": &"wood", "sound": &"wood"},
	{"id": &"snow_block", "name": "Snow", "hard": 0.3, "tool": &"", "tier": 0, "drop": &"stone", "sound": &"dirt"},
	{"id": &"sand_block", "name": "Sand", "hard": 0.4, "tool": &"", "tier": 0, "drop": &"stone", "sound": &"dirt"},
	{"id": &"gravel_block", "name": "Gravel", "hard": 0.7, "tool": &"pickaxe", "tier": 1, "drop": &"stone", "sound": &"stone"},
	{"id": &"clay_block", "name": "Clay", "hard": 0.6, "tool": &"", "tier": 0, "drop": &"stone", "sound": &"dirt"},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in BLOCKS:
		var block: Object = script.new()
		block.set("id", spec["id"])
		block.set("display_name", spec["name"])
		block.set("tile_top", String(spec["id"]) + "_top")
		block.set("tile_side", String(spec["id"]) + "_side")
		block.set("tile_bottom", String(spec["id"]) + "_bottom")
		block.set("hardness", float(spec["hard"]))
		# BlockData records the *tool action* the game uses, not the item name:
		# hoe=till, pickaxe=mine, axe=chop (ItemRegistry.tool_action).
		var action_map := {&"hoe": &"till", &"pickaxe": &"mine", &"axe": &"chop"}
		var wanted := StringName(spec.get("tool", &""))
		block.set("tool_kind", action_map.get(wanted, wanted))
		block.set("minimum_tier", int(spec["tier"]))
		var drops: Array[StringName] = []
		if spec.has("drop"):
			drops.append(spec["drop"])
		block.set("drops", drops)
		block.set("place_item", spec.get("drop", &""))
		block.set("sound_set", StringName(spec.get("sound", &"stone")))
		block.set("transparent", bool(spec.get("transparent", false)))
		block.set("light_emission", int(spec.get("light", 0)))
		block.set("collision_kind", String(spec.get("collision", "solid")))
		if not bool(block.call("is_valid")):
			printerr("[generate_block_data] invalid %s" % spec["id"])
			errors += 1
			continue
		if ResourceSaver.save(block, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_block_data] wrote %d blocks" % BLOCKS.size())
	quit(1 if errors > 0 else 0)
