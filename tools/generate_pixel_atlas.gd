extends SceneTree
## W3.3: the optional 16×16 pixel pack. Procedural, CC0, no external asset.
##   Godot --headless --path . --script res://tools/generate_pixel_atlas.gd
## The default detailed pack stays the shipped look; this one is one setting
## away and is what the owner flips to for the pixel-block aesthetic.

const PACK := "res://assets/voxel/packs/pixel16/"
const TILE := 16
const COLS := 4


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACK))
	var blocks := BlockRegistry.all_blocks()
	if blocks.is_empty():
		printerr("[generate_pixel_atlas] no blocks")
		quit(1)
		return
	var rows: int = ceili(float(blocks.size()) / float(COLS))
	var image := Image.create(TILE * COLS, TILE * rows, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var manifest := PackedStringArray()
	for i: int in range(blocks.size()):
		var block: BlockData = blocks[i]
		var tx: int = i % COLS
		var ty: int = i / COLS
		var base := _color_for(block)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(hash(String(block.id) + "_pixel") & 0x7FFFFFFF)
		for px: int in range(TILE):
			for py: int in range(TILE):
				# Chunky 4px pixels and a dark outline read as a pixel tile.
				var cell := Vector2i(px / 4, py / 4)
				var shade := 1.0 - 0.12 * float(
					int(hash(str(cell) + String(block.id)) & 3))
				var edge := 0.6 if px == 0 or py == 0 or px == TILE - 1 or py == TILE - 1 else 1.0
				var c := Color(base.r * shade * edge, base.g * shade * edge,
					base.b * shade * edge, 1.0)
				image.set_pixel(tx * TILE + px, ty * TILE + py, c)
		manifest.append("\"%s\": [%d, %d]" % [String(block.id), tx, ty])
	var err := image.save_png(ProjectSettings.globalize_path(PACK + "atlas.png"))
	if err != OK:
		printerr("[generate_pixel_atlas] save failed: %d" % err)
		quit(1)
		return
	var json := "{\n  \"name\": \"Pixel Sixteen\",\n  \"author\": \"Generated in tools/generate_pixel_atlas.gd\",\n  \"licence\": \"CC0-1.0 (original procedural output)\",\n  \"tile_px\": %d,\n  \"filter\": \"nearest\",\n  \"tiles\": {\n    %s\n  }\n}\n" % [
		TILE, ",\n    ".join(manifest),
	]
	var file := FileAccess.open(PACK + "pack.json", FileAccess.WRITE)
	file.store_string(json)
	file.close()
	print("[generate_pixel_atlas] wrote 16px atlas for %d blocks" % blocks.size())
	quit(0)


func _color_for(block: BlockData) -> Color:
	var id := String(block.id)
	if id.contains("grass"):
		return Color(0.38, 0.68, 0.30)
	if id.contains("soil") or id.contains("sand") or id.contains("clay"):
		return Color(0.62, 0.46, 0.30)
	if id.contains("stone") or id.contains("cobble") or id.contains("gravel"):
		return Color(0.55, 0.56, 0.60)
	if id.contains("copper"):
		return Color(0.80, 0.46, 0.28)
	if id.contains("iron"):
		return Color(0.78, 0.78, 0.80)
	if id.contains("gold"):
		return Color(0.94, 0.80, 0.30)
	if id.contains("ember"):
		return Color(1.0, 0.68, 0.30)
	if id.contains("water"):
		return Color(0.30, 0.56, 0.78)
	if id.contains("log") or id.contains("planks") or id.contains("wood") or id.contains("fence"):
		return Color(0.52, 0.36, 0.22)
	if id.contains("glass"):
		return Color(0.78, 0.90, 0.96)
	if id.contains("torch") or id.contains("lantern"):
		return Color(1.0, 0.88, 0.50)
	if id.contains("snow"):
		return Color(0.98, 0.98, 1.0)
	return Color(0.66, 0.64, 0.60)
