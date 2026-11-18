extends SceneTree
const OUT := "res://resources/buildings/"
const SCRIPT := "res://resources/buildings/building_data.gd"

const BUILDINGS: Array[Dictionary] = [
	{"id": &"hen_coop", "name": "Hen Coop", "price": 500, "upgrade": 350,
	 "effect": &"product", "value": 1, "tint": Color(0.82, 0.58, 0.34)},
	{"id": &"dairy_barn", "name": "Dairy Barn", "price": 800, "upgrade": 550,
	 "effect": &"product", "value": 2, "tint": Color(0.72, 0.42, 0.32)},
	{"id": &"farm_well", "name": "Farm Well", "price": 450, "upgrade": 300,
	 "effect": &"water", "value": 2, "tint": Color(0.52, 0.58, 0.62)},
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	if script == null:
		printerr("[generate_building_data] script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in BUILDINGS:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("price", int(spec["price"]))
		data.set("upgrade_price", int(spec["upgrade"]))
		data.set("effect_kind", spec["effect"])
		data.set("effect_value", int(spec["value"]))
		data.set("tint", spec["tint"])
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_building_data] wrote %d buildings" % BUILDINGS.size())
	quit(1 if errors > 0 else 0)
