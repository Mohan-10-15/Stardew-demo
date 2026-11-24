extends SceneTree
## Generates the default CC0-equivalent texture pack in code: a deterministic
## tiled atlas, one row per block, with a pack.json manifest. No external asset
## licence is incurred because every pixel is generated here.
##   Godot --headless --path . --script res://tools/generate_block_atlas.gd

const PACK := "res://assets/voxel/packs/hollowbrook_detailed/"
const TILE := 32
const COLS := 4


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACK))
	var blocks := BlockRegistry.all_blocks()
	if blocks.is_empty():
		printerr("[generate_block_atlas] no blocks")
		quit(1)
		return
	var rows: int = ceili(float(blocks.size()) / float(COLS))
	var image := Image.create(TILE * COLS, TILE * rows, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	var manifest := PackedStringArray()
	for i: int in range(blocks.size()):
		var block: BlockData = blocks[i]
		var tile_x: int = i % COLS
		var tile_y: int = i / COLS
		var base := _color_for(block)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(hash(String(block.id)) & 0x7FFFFFFF)
		for px: int in range(TILE):
			for py: int in range(TILE):
				var jitter := rng.randf_range(-0.06, 0.06)
				var grain := 1.0 if (px + py) % 4 == 0 else 0.94
				var c := Color(
					clampf(base.r + jitter, 0.0, 1.0) * grain,
					clampf(base.g + jitter, 0.0, 1.0) * grain,
					clampf(base.b + jitter, 0.0, 1.0) * grain, 1.0
				)
				image.set_pixel(tile_x * TILE + px, tile_y * TILE + py, c)
		manifest.append("\"%s\": [%d, %d]" % [String(block.id), tile_x, tile_y])
	var err := image.save_png(ProjectSettings.globalize_path(PACK + "atlas.png"))
	if err != OK:
		printerr("[generate_block_atlas] save failed: %d" % err)
		quit(1)
		return
	var json := "{\n  \"name\": \"Hollowbrook Detailed\",\n  \"author\": \"Generated in tools/generate_block_atlas.gd\",\n  \"licence\": \"CC0-1.0 (original procedural output)\",\n  \"tile_px\": %d,\n  \"filter\": \"nearest\",\n  \"tiles\": {\n    %s\n  }\n}\n" % [
		TILE, ",\n    ".join(manifest),
	]
	var file := FileAccess.open(PACK + "pack.json", FileAccess.WRITE)
	file.store_string(json)
	file.close()
	print("[generate_block_atlas] wrote %dx%d atlas for %d blocks" % [
		TILE * COLS, TILE * rows, blocks.size(),
	])
	quit(0)


func _color_for(block: BlockData) -> Color:
	var id := String(block.id)
	if id.contains("grass"):
		return Color(0.32, 0.58, 0.26)
	if id.contains("soil") or id.contains("sand") or id.contains("clay"):
		return Color(0.56, 0.42, 0.28)
	if id.contains("stone") or id.contains("cobble") or id.contains("gravel"):
		return Color(0.48, 0.49, 0.52)
	if id.contains("copper"):
		return Color(0.72, 0.42, 0.26)
	if id.contains("iron"):
		return Color(0.72, 0.72, 0.74)
	if id.contains("gold"):
		return Color(0.88, 0.74, 0.26)
	if id.contains("ember"):
		return Color(0.95, 0.62, 0.28)
	if id.contains("water"):
		return Color(0.26, 0.48, 0.70)
	if id.contains("log") or id.contains("planks") or id.contains("wood") or id.contains("fence"):
		return Color(0.46, 0.32, 0.20)
	if id.contains("glass"):
		return Color(0.72, 0.86, 0.94)
	if id.contains("torch") or id.contains("lantern"):
		return Color(0.98, 0.84, 0.42)
	if id.contains("snow"):
		return Color(0.94, 0.96, 0.98)
	return Color(0.6, 0.58, 0.55)
