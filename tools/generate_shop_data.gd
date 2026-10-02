extends SceneTree
## Headless tool: writes the shop `.tres` definitions into
## `res://resources/economy/shops/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_shop_data.gd
##
## ## Why a generator and not hand-written files
##
## Because the stock list is derived from the item content rather than typed out
## again. The general store's stock is "every seed packet the game has", and
## writing that list here would make it a second inventory of the crops — one to
## forget to update when a new seed arrives, which is exactly the failure the
## generator exists to remove.
##
## Prices are *not* written here. `buy_price` and `sell_price` live on the item and
## crop definitions, so there is one price per thing in the whole game. See
## `ShopDefinition`.

const OUTPUT_DIR := "res://resources/economy/shops/"

## id, display name, description, and how the stock list is chosen
const SHOPS: Array[Dictionary] = [
	{
		"id": &"general_store",
		"display_name": "General Store",
		"description": "Seed, twine, and a man who remembers your name.",
		# Every seed packet, cheapest first so the shelf reads like a shop rather
		# than a database dump.
		"select": &"all_seeds",
		"sort": &"buy_price",
		"buys_from_player": true,
	},
]


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		var err := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUTPUT_DIR)
		)
		if err != OK:
			printerr("[generate_shop_data] cannot create %s: %d" % [OUTPUT_DIR, err])
			quit(1)
			return

	var written := 0
	for spec: Dictionary in SHOPS:
		var shop := ShopDefinition.new()
		shop.id = spec["id"]
		shop.display_name = spec["display_name"]
		shop.buys_from_player = int(spec["buys_from_player"])
		shop.stock = _stock_for(StringName(spec["select"]), StringName(spec["sort"]))

		if shop.stock.is_empty():
			printerr("[generate_shop_data] %s selected no stock" % shop.id)
			quit(1)
			return
		var path := "%s%s.tres" % [OUTPUT_DIR, shop.id]
		if ResourceSaver.save(shop, path) != OK:
			printerr("[generate_shop_data] failed to write %s" % path)
			quit(1)
			return
		print("[generate_shop_data] %s: %d items" % [shop.id, shop.stock.size()])
		written += 1

	print("[generate_shop_data] wrote %d shops to %s" % [written, OUTPUT_DIR])
	quit(0)


## The item ids a shop stocks.
##
## Reads the item `.tres` files straight off disk rather than going through
## [ItemRegistry], for the reason documented in `generate_item_data.gd`: a
## `--script` run compiles before the autoloads exist, so anything that logs
## through `Log` is a compile error from here.
func _stock_for(select: StringName, sort: StringName) -> Array[StringName]:
	var entries: Array[Dictionary] = []
	for path: String in _item_paths():
		var item := ResourceLoader.load(path) as ItemDefinition
		if item == null:
			continue
		if not _matches(item, select):
			continue
		entries.append({
			"id": item.id,
			"price": item.buy_price if sort == &"buy_price" else 0,
			"name": item.display_name,
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["price"]) != int(b["price"]):
			return int(a["price"]) < int(b["price"])
		return String(a["name"]) < String(b["name"])
	)

	var out: Array[StringName] = []
	for entry: Dictionary in entries:
		out.append(entry["id"] as StringName)
	return out


func _matches(item: ItemDefinition, select: StringName) -> bool:
	match select:
		&"all_seeds":
			# A seed is defined by the crop it plants, not by its category, so a
			# packet whose category was mislabelled still reaches the shelf.
			return not item.seed_id.is_empty() and item.buy_price > 0
		_:
			return false


func _item_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://resources/farming/items/")
	if dir == null:
		printerr("[generate_shop_data] cannot open the item directory")
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			out.append("res://resources/farming/items/%s" % entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return out