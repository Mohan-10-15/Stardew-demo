extends SceneTree
const OUT := "res://resources/animals/"
const SCRIPT := "res://resources/animals/animal_data.gd"
const ITEM_SCRIPT := "res://scripts/items/item_definition.gd"
const ITEM_DIR := "res://resources/farming/items/"

const ANIMALS: Array[Dictionary] = [
	{"id": &"hen", "name": "Bramble the Hen", "feed": &"spring_onion", "product": &"egg",
	 "amount": 1, "days": 1, "tint": Color(0.95, 0.82, 0.35)},
	{"id": &"goat", "name": "Nimbus the Goat", "feed": &"wild_berry", "product": &"milk",
	 "amount": 1, "days": 2, "tint": Color(0.92, 0.90, 0.86)},
]

const ITEMS: Array[Dictionary] = [
	{"id": &"egg", "name": "Egg", "price": 55},
	{"id": &"milk", "name": "Milk", "price": 90},
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	var item_script := load(ITEM_SCRIPT) as GDScript
	if script == null or item_script == null:
		printerr("[generate_animal_data] scripts missing")
		quit(1)
		return
	var errors := 0
	for spec: Dictionary in ANIMALS:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("feed_item", spec["feed"])
		data.set("product_item", spec["product"])
		data.set("product_amount", int(spec["amount"]))
		data.set("days_to_product", int(spec["days"]))
		data.set("tint", spec["tint"])
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	for spec: Dictionary in ITEMS:
		var item: Object = item_script.new()
		item.set("id", spec["id"])
		item.set("display_name", spec["name"])
		item.set("category", 3)
		item.set("sell_price", int(spec["price"]))
		item.set("icon_color", Color(0.95, 0.90, 0.78))
		if ResourceSaver.save(item, "%s%s.tres" % [ITEM_DIR, spec["id"]]) != OK:
			errors += 1
	print("[generate_animal_data] wrote %d animals and %d products" % [
		ANIMALS.size(), ITEMS.size(),
	])
	quit(1 if errors > 0 else 0)
