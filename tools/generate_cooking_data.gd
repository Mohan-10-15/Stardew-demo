extends SceneTree
const OUT := "res://resources/cooking/recipes/"
const SCRIPT := "res://resources/cooking/cooking_recipe.gd"

const RECIPES: Array[Dictionary] = [
	{"id": &"berry_jam", "name": "Berry Jam", "in": {&"wild_berry": 2}, "out": &"fish_smilte"},
	{"id": &"onion_soup", "name": "Onion Soup", "in": {&"spring_onion": 2, &"wood": 1}, "out": &"fish_trout"},
	{"id": &"egg_omelette", "name": "Egg Omelette", "in": {&"egg": 1, &"spring_onion": 1}, "out": &"egg"},
	{"id": &"milk_tea", "name": "Milk Tea", "in": {&"milk": 1, &"wild_berry": 1}, "out": &"milk"},
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	if script == null:
		printerr("[generate_cooking_data] script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in RECIPES:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("ingredients", spec["in"])
		data.set("output_id", spec["out"])
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_cooking_data] wrote %d dishes" % RECIPES.size())
	quit(1 if errors > 0 else 0)
