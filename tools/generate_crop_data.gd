extends SceneTree
## Headless tool: writes the crop `.tres` definitions into
## `resources/farming/crops/`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_crop_data.gd
##
## Generated rather than hand-authored so the balance numbers live in one
## readable table in source control (and in a diff), instead of spread across
## binary-ish resource files. The `.tres` files are still the runtime format:
## [CropRegistry] loads them, and a designer can edit one without re-running this
## tool.

const OUTPUT_DIR := "res://resources/farming/crops/"

## id, name, seasons, days_to_grow, min_yield, max_yield, regrows,
## regrow_days, seed_price, sell_price, ripe_color, sprout_color
##
## Seeds cost more than they sell for on purpose: the profit is in growing
## several of them, not in reselling one. Regrowers cost more to buy because
## they are worth keeping.
const CROPS: Array[Dictionary] = [
	{
		"id": &"parsnip",
		"display_name": "Parsnip",
		"seasons": [0],
		"days_to_grow": 4,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 20,
		"sell_price": 35,
		"ripe_color": Color(0.85, 0.76, 0.52),
		"sprout_color": Color(0.55, 0.72, 0.38),
	},
	{
		"id": &"potato",
		"display_name": "Potato",
		"seasons": [0, 3],
		"days_to_grow": 6,
		"min_yield": 1,
		"max_yield": 2,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 50,
		"sell_price": 80,
		"ripe_color": Color(0.72, 0.60, 0.38),
		"sprout_color": Color(0.44, 0.66, 0.34),
	},
	{
		"id": &"cauliflower",
		"display_name": "Cauliflower",
		"seasons": [0],
		"days_to_grow": 12,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 80,
		"sell_price": 175,
		"ripe_color": Color(0.94, 0.93, 0.86),
		"sprout_color": Color(0.50, 0.70, 0.36),
	},
	{
		"id": &"melon",
		"display_name": "Melon",
		"seasons": [1],
		"days_to_grow": 12,
		"min_yield": 1,
		"max_yield": 2,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 80,
		"sell_price": 250,
		"ripe_color": Color(0.30, 0.55, 0.26),
		"sprout_color": Color(0.46, 0.68, 0.32),
	},
	{
		"id": &"tomato",
		"display_name": "Tomato",
		"seasons": [1],
		"days_to_grow": 11,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": true,
		"regrow_days": 4,
		"seed_price": 50,
		"sell_price": 60,
		"ripe_color": Color(0.80, 0.24, 0.18),
		"sprout_color": Color(0.42, 0.64, 0.30),
	},
	{
		"id": &"corn",
		"display_name": "Corn",
		"seasons": [1, 2],
		"days_to_grow": 14,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": true,
		"regrow_days": 4,
		"seed_price": 150,
		"sell_price": 50,
		"ripe_color": Color(0.92, 0.78, 0.20),
		"sprout_color": Color(0.50, 0.70, 0.34),
	},
	{
		"id": &"pumpkin",
		"display_name": "Pumpkin",
		"seasons": [2],
		"days_to_grow": 13,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 100,
		"sell_price": 320,
		"ripe_color": Color(0.85, 0.45, 0.12),
		"sprout_color": Color(0.46, 0.64, 0.30),
	},
	{
		"id": &"yam",
		"display_name": "Yam",
		"seasons": [2],
		"days_to_grow": 10,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 60,
		"sell_price": 160,
		"ripe_color": Color(0.72, 0.32, 0.52),
		"sprout_color": Color(0.48, 0.68, 0.34),
	},
	{
		"id": &"winter_seeds",
		"display_name": "Winter Seeds",
		"seasons": [3],
		"days_to_grow": 7,
		"min_yield": 1,
		"max_yield": 1,
		"regrows": false,
		"regrow_days": 0,
		"seed_price": 30,
		"sell_price": 105,
		"ripe_color": Color(0.60, 0.78, 0.62),
		"sprout_color": Color(0.62, 0.76, 0.66),
	},
]


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		if err != OK:
			printerr("[generate_crop_data] cannot create %s: %d" % [OUTPUT_DIR, err])
			quit(1)
			return

	var written := 0
	for spec: Dictionary in CROPS:
		var crop := CropData.new()
		crop.id = spec["id"]
		crop.display_name = spec["display_name"]
		crop.seasons.assign(spec["seasons"])
		crop.days_to_grow = spec["days_to_grow"]
		crop.min_yield = spec["min_yield"]
		crop.max_yield = spec["max_yield"]
		crop.regrows = spec["regrows"]
		crop.regrow_days = spec["regrow_days"]
		crop.seed_price = spec["seed_price"]
		crop.sell_price = spec["sell_price"]
		crop.ripe_color = spec["ripe_color"]
		crop.sprout_color = spec["sprout_color"]

		if not crop.is_valid():
			printerr("[generate_crop_data] %s is invalid" % crop.id)
			quit(1)
			return

		var path := "%s%s.tres" % [OUTPUT_DIR, crop.id]
		if ResourceSaver.save(crop, path) != OK:
			printerr("[generate_crop_data] failed to write %s" % path)
			quit(1)
			return
		written += 1

	print("[generate_crop_data] wrote %d crops to %s" % [written, OUTPUT_DIR])
	quit(0)