class_name AnimeFace
extends RefCounted
## Original, procedurally drawn anime faces for the CC0 villagers.
##
## ## Why procedural and not a downloaded pack
##
## The repo only ships KayKit and Quaternius art, and a CC0 anime pack could not
## be sourced in this environment. These faces are original art generated from a
## handful of shapes and cached per villager: no new licence, no new dependency,
## and a palette that can be tuned in source control. They overlay the existing
## rig's head bone, so all the gameplay, gear and walking stay untouched.
##
## Bright-shonen conventions: large almond eyes with a coloured iris and a hard
## white catchlight, bold angled brows, a tiny nose and a confident mouth.

const SIZE := 128
const INK := Color(0.08, 0.07, 0.10, 1.0)
const WHITE := Color(1.0, 0.99, 0.96, 1.0)

## Per-villager eye colour, picked to complement (not copy) their hair tint.
const EYE_COLORS: Dictionary = {
	&"mira": Color(0.20, 0.72, 0.92),
	&"bram": Color(0.95, 0.66, 0.18),
	&"odette": Color(0.62, 0.36, 0.95),
	&"fen": Color(0.22, 0.86, 0.62),
	&"halda": Color(0.98, 0.82, 0.24),
	&"sable": Color(0.38, 0.68, 0.98),
}

static var _cache: Dictionary = {}


## The transparent face texture for [param npc_id], cached per id.
static func texture_for(npc_id: StringName) -> ImageTexture:
	if _cache.has(npc_id):
		return _cache[npc_id]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var eyes: Color = EYE_COLORS.get(npc_id, Color(0.25, 0.70, 0.95))

	# Eyes: dark outline, white sclera, coloured iris, pupil, catchlight.
	for cx: int in [40, 88]:
		ellipse(image, cx, 55, 19, 24, INK)
		ellipse(image, cx, 56, 17, 22, WHITE)
		ellipse(image, cx, 59, 10, 14, eyes)
		ellipse(image, cx, 60, 4, 7, INK)
		ellipse(image, cx - 5, 51, 5, 6, WHITE)
		ellipse(image, cx + 6, 66, 2, 2, Color(1, 1, 1, 0.7))

	# Bold, slightly slanted brows — the shonen "ready for anything" line.
	_line(image, 25, 26, 54, 22, 3, INK)
	_line(image, 74, 22, 103, 26, 3, INK)

	# Small nose and a confident, closed-mouth smile.
	ellipse(image, 64, 80, 2, 2, Color(0.35, 0.24, 0.20, 0.85))
	_line(image, 54, 99, 64, 103, 2, INK)
	_line(image, 64, 103, 75, 97, 2, INK)

	var texture := ImageTexture.create_from_image(image)
	_cache[npc_id] = texture
	return texture


## Fills an axis-aligned ellipse, one pixel at a time. 128x128 is small enough
## that a per-pixel loop costs less than the complexity of a drawing API.
static func ellipse(image: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for y: int in range(maxi(0, cy - ry), mini(SIZE, cy + ry + 1)):
		for x: int in range(maxi(0, cx - rx), mini(SIZE, cx + rx + 1)):
			var nx := float(x - cx) / float(maxi(rx, 1))
			var ny := float(y - cy) / float(maxi(ry, 1))
			if nx * nx + ny * ny <= 1.0:
				image.set_pixel(x, y, color)


## A thick raster line, used for brows and the mouth.
static func _line(image: Image, x0: int, y0: int, x1: int, y1: int,
		width: int, color: Color) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for i: int in range(steps + 1):
		var t := float(i) / float(maxi(steps, 1))
		var x := int(roundf(float(x0) + float(x1 - x0) * t))
		var y := int(roundf(float(y0) + float(y1 - y0) * t))
		ellipse(image, x, y, width, width, color)


## Drops the cached textures. For tests that rebuild content with new IDs.
static func clear_cache() -> void:
	_cache.clear()
