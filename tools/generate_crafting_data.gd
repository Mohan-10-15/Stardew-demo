extends SceneTree
const OUT := "res://resources/crafting/recipes/"
const SCRIPT := "res://resources/crafting/recipe.gd"

const RECIPES: Array[Dictionary] = [
	{"id": &"parsnip_seeds", "name": "Parsnip Seeds", "in": {&"parsnip": 1},
	 "out": &"parsnip_seeds", "count": 2},
	{"id": &"stone_brick", "name": "Stone Bricks", "in": {&"stone": 3},
	 "out": &"stone", "count": 2},
	{"id": &"plank", "name": "Planks", "in": {&"wood": 2},
	 "out": &"wood", "count": 3},
	{"id": &"fish_stew", "name": "Fish Stew", "in": {&"fish_smilte": 1, &"spring_onion": 1},
	 "out": &"fish_trout", "count": 1},
	{"id": &"trail_mix", "name": "Trail Mix", "in": {&"wild_berry": 2, &"wood": 1},
	 "out": &"wild_horseradish", "count": 1},
	{"id": &"ore_flux", "name": "Ore Flux", "in": {&"copper_ore": 2, &"stone": 1},
	 "out": &"iron_ore", "count": 1},
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	if script == null:
		printerr("[generate_crafting_data] script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in RECIPES:
		var recipe: Object = script.new()
		recipe.set("id", spec["id"])
		recipe.set("display_name", spec["name"])
		recipe.set("ingredients", spec["in"])
		recipe.set("output_id", spec["out"])
		recipe.set("output_count", int(spec["count"]))
		if not bool(recipe.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(recipe, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_crafting_data] wrote %d recipes" % RECIPES.size())
	quit(1 if errors > 0 else 0)
