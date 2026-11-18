extends SceneTree
const OUT := "res://resources/fishing/fish/"
const SCRIPT := "res://resources/fishing/fish_data.gd"
const ITEM_SCRIPT := "res://scripts/items/item_definition.gd"
const ITEM_DIR := "res://resources/farming/items/"

const FISH: Array[Dictionary] = [
	{"id": &"pond_smilte", "name": "Pond Smilte", "item": &"fish_smilte",
	 "seasons": [0, 1, 2], "weathers": [0, 1, 2], "from": 6, "to": 20, "min": 1.4, "max": 3.0},
	{"id": &"brook_trout", "name": "Brook Trout", "item": &"fish_trout",
	 "seasons": [0, 2], "weathers": [0, 2], "from": 6, "to": 18, "min": 2.0, "max": 4.5},
	{"id": &"rain_darter", "name": "Rain Darter", "item": &"fish_darter",
	 "seasons": [0, 1, 2, 3], "weathers": [2, 3], "from": 0, "to": 23, "min": 1.0, "max": 2.4},
	{"id": &"ice_pike", "name": "Ice Pike", "item": &"fish_pike",
	 "seasons": [3], "weathers": [4], "from": 6, "to": 18, "min": 2.6, "max": 5.0},
	{"id": &"sunfin", "name": "Sunfin", "item": &"fish_sunfin",
	 "seasons": [1], "weathers": [0], "from": 8, "to": 16, "min": 1.8, "max": 3.6},
	{"id": &"moon_eel", "name": "Moon Eel", "item": &"fish_eel",
	 "seasons": [0, 1, 2, 3], "weathers": [0, 1, 2, 3, 4], "from": 20, "to": 2, "min": 2.4, "max": 4.8},
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	if script == null:
		printerr("[generate_fishing_data] script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in FISH:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("item_id", spec["item"])
		var seasons: Array[int] = []
		for s: int in spec["seasons"]:
			seasons.append(s)
		data.set("seasons", seasons)
		var weathers: Array[int] = []
		for w: int in spec["weathers"]:
			weathers.append(w)
		data.set("weathers", weathers)
		data.set("hour_from", int(spec["from"]))
		data.set("hour_to", int(spec["to"]))
		data.set("wait_min", float(spec["min"]))
		data.set("wait_max", float(spec["max"]))
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
		var item_script := load(ITEM_SCRIPT) as GDScript
		if item_script != null:
			var item: Object = item_script.new()
			item.set("id", spec["item"])
			item.set("display_name", spec["name"])
			item.set("category", 3)  # FOOD
			item.set("sell_price", 45 + int(spec["max"]) * 10)
			item.set("icon_color", Color(0.35, 0.72, 0.85))
			if ResourceSaver.save(item, "%s%s.tres" % [ITEM_DIR, spec["item"]]) != OK:
				errors += 1
	print("[generate_fishing_data] wrote %d fish" % FISH.size())
	quit(1 if errors > 0 else 0)
