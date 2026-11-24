extends SceneTree
## W4.9: visual evidence that the five procedural moods are actually distinct,
## rendered from the same AnimeFace textures the villagers use in game.
##     Godot --headless --path . --script res://tools/playtest_face_moods.gd

const OUT := "res://art_review_face_moods.png"
const IDS: Array[StringName] = [&"mira", &"bram", &"sable"]


func _initialize() -> void:
	var moods: Array[StringName] = [
		AnimeFace.MOOD_NEUTRAL, AnimeFace.MOOD_HAPPY, AnimeFace.MOOD_SAD,
		AnimeFace.MOOD_ANGRY, AnimeFace.MOOD_BLINK,
	]
	var sheet := Image.create(128 * moods.size(), 128 * IDS.size(),
		false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.12, 1.0))
	for row: int in range(IDS.size()):
		for col: int in range(moods.size()):
			var img := AnimeFace.texture_for(IDS[row], moods[col]).get_image()
			for x: int in range(128):
				for y: int in range(128):
					sheet.set_pixel(col * 128 + x, row * 128 + y, img.get_pixel(x, y))
	var err := sheet.save_png(ProjectSettings.globalize_path(OUT))
	if err != OK:
		printerr("[faces] save failed: %d" % err)
		quit(1)
		return
	print("[faces] wrote %s — %d moods x %d villagers" % [
		OUT, moods.size(), IDS.size(),
	])
	quit(0)
