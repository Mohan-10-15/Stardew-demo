extends SceneTree
## W4.8: build a 12-portrait contact sheet from the same AnimeFace textures the
## game uses. Headless-safe: this is content evidence, not a rendered scene.
##     Godot --headless --path . --script res://tools/playtest_contact_sheet.gd

const OUT := "res://art_review_cast.png"
const IDS: Array[StringName] = [
	&"mira", &"bram", &"fen", &"odette", &"sable", &"aurel",
	&"lyra", &"cassia", &"elke", &"garrick", &"halda", &"dorian",
]


func _initialize() -> void:
	var sheet := Image.create(128 * 4, 128 * 3, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.12, 1.0))
	for i: int in range(IDS.size()):
		var face := AnimeFace.texture_for(IDS[i])
		var img := face.get_image()
		var ox: int = (i % 4) * 128
		var oy: int = (i / 4) * 128
		for x: int in range(128):
			for y: int in range(128):
				sheet.set_pixel(ox + x, oy + y, img.get_pixel(x, y))
	var err := sheet.save_png(ProjectSettings.globalize_path(OUT))
	if err != OK:
		printerr("[cast] save failed: %d" % err)
		quit(1)
		return
	print("[cast] wrote %s — %d portraits" % [OUT, IDS.size()])
	quit(0)
