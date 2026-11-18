extends SceneTree
const OUT := "res://resources/machines/"
const SCRIPT := "res://resources/machines/machine_data.gd"

const MACHINES: Array[Dictionary] = [
	{"id": &"furnace", "name": "Ore Furnace", "in": &"copper_ore", "out": &"iron_ore",
	 "amount": 1, "days": 2, "price": 350, "tint": Color(0.72, 0.36, 0.26)},
	{"id": &"jam_jar", "name": "Berry Press", "in": &"wild_berry", "out": &"fish_trout",
	 "amount": 1, "days": 1, "price": 180, "tint": Color(0.78, 0.36, 0.58)},
	{"id": &"smoker", "name": "Fish Smoker", "in": &"fish_smilte", "out": &"fish_trout",
	 "amount": 2, "days": 1, "price": 260, "tint": Color(0.48, 0.40, 0.30)},
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	if script == null:
		printerr("[generate_machine_data] script missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in MACHINES:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("input_id", spec["in"])
		data.set("output_id", spec["out"])
		data.set("output_amount", int(spec["amount"]))
		data.set("process_days", int(spec["days"]))
		data.set("price", int(spec["price"]))
		data.set("tint", spec["tint"])
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_machine_data] wrote %d machines" % MACHINES.size())
	quit(1 if errors > 0 else 0)
