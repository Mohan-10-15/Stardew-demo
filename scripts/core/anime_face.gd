class_name AnimeFace
extends RefCounted
## Original, procedurally drawn anime faces for the CC0 villagers.
##
## ## Why procedural and not a downloaded pack
##
## The repo only ships KayKit and Quaternius art, and a CC0 anime pack could not
## be sourced in this environment. These faces are original art generated from a
## handful of shapes and cached per villager and mood: no new licence, no new
## dependency, and a palette that can be tuned in source control. They overlay
## the existing rig's head bone, so all the gameplay, gear and walking stay
## untouched.
##
## Bright-shonen conventions: large almond eyes with a two-tone iris and a hard
## white catchlight, thick lashes, bold angled brows, a tiny nose and a
## confident mouth. Five moods let the face answer a gift the way the dialogue
## and the EventBus already do — happy for a liked present, sad for a disliked
## one, angry for a refusal, and a blink every few seconds so a still villager
## reads as alive.

const SIZE := 128
const INK := Color(0.07, 0.06, 0.09, 1.0)
const WHITE := Color(1.0, 0.99, 0.96, 1.0)
const BLUSH := Color(1.0, 0.42, 0.48, 0.32)

const MOOD_NEUTRAL: StringName = &"neutral"
const MOOD_HAPPY: StringName = &"happy"
const MOOD_SAD: StringName = &"sad"
const MOOD_ANGRY: StringName = &"angry"
const MOOD_BLINK: StringName = &"blink"
const MOODS: Array[StringName] = [
	MOOD_NEUTRAL, MOOD_HAPPY, MOOD_SAD, MOOD_ANGRY, MOOD_BLINK,
]

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


## The transparent face texture for [param npc_id] in [param mood], cached.
static func texture_for(npc_id: StringName,
		mood: StringName = MOOD_NEUTRAL) -> ImageTexture:
	var key := "%s:%s" % [npc_id, mood]
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var eyes: Color = EYE_COLORS.get(npc_id, Color(0.25, 0.70, 0.95))

	if mood == MOOD_NEUTRAL or mood == MOOD_HAPPY or mood == MOOD_SAD \
			or mood == MOOD_ANGRY:
		_draw_open_eyes(image, eyes, mood)
	else:
		_draw_closed_eyes(image)
	_draw_brows(image, mood)

	# Small nose, then a mouth whose shape carries the mood.
	ellipse(image, 64, 81, 2, 2, Color(0.35, 0.24, 0.20, 0.85))
	match mood:
		MOOD_HAPPY:
			_line(image, 50, 98, 64, 106, 3, INK)
			_line(image, 64, 106, 79, 97, 3, INK)
			ellipse(image, 27, 86, 9, 5, BLUSH)
			ellipse(image, 101, 86, 9, 5, BLUSH)
		MOOD_SAD:
			_line(image, 53, 104, 64, 99, 2, INK)
			_line(image, 64, 99, 76, 104, 2, INK)
		MOOD_ANGRY:
			_line(image, 54, 101, 75, 101, 3, INK)
		_:
			_line(image, 54, 99, 64, 103, 2, INK)
			_line(image, 64, 103, 75, 97, 2, INK)

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Large eyes with a dark outline, white sclera, two-tone iris, pupil, hard
## catchlight and a lash flick at the outer corner.
static func _draw_open_eyes(image: Image, eyes: Color, mood: StringName) -> void:
	var squash := 1.0 if mood != MOOD_SAD else 0.82
	for cx: int in [40, 88]:
		ellipse(image, cx, 55, 19, int(24 * squash), INK)
		ellipse(image, cx, 56, 17, int(22 * squash), WHITE)
		ellipse(image, cx, 59, 10, int(14 * squash), eyes)
		ellipse(image, cx, 66, 9, int(6 * squash), eyes.darkened(0.35))
		ellipse(image, cx, 60, 4, 7, INK)
		ellipse(image, cx - 5, 51, 5, 6, WHITE)
		ellipse(image, cx + 6, 66, 2, 2, Color(1, 1, 1, 0.7))
		# Lash flick: a few shrinking ellipses angling out from the top corner.
		var outer := cx - 17 if cx < 64 else cx + 17
		for i: int in range(4):
			ellipse(image, outer + (i if cx < 64 else -i), 40 - i, 3 - i / 2, 2, INK)


## Closed lids for a blink: two dark arcs with a hint of lash.
static func _draw_closed_eyes(image: Image) -> void:
	for cx: int in [40, 88]:
		_line(image, cx - 16, 56, cx - 7, 60, 2, INK)
		_line(image, cx - 7, 60, cx + 3, 61, 2, INK)
		_line(image, cx + 3, 61, cx + 15, 56, 2, INK)
		ellipse(image, cx - 15, 55, 2, 2, INK)
		ellipse(image, cx + 14, 54, 2, 2, INK)


static func _draw_brows(image: Image, mood: StringName) -> void:
	match mood:
		MOOD_SAD:
			_line(image, 24, 24, 53, 30, 3, INK)
			_line(image, 75, 30, 104, 24, 3, INK)
		MOOD_ANGRY:
			_line(image, 24, 18, 54, 29, 4, INK)
			_line(image, 74, 29, 104, 18, 4, INK)
		MOOD_HAPPY:
			_line(image, 25, 24, 54, 21, 3, INK)
			_line(image, 74, 21, 103, 24, 3, INK)
		_:
			_line(image, 25, 26, 54, 22, 3, INK)
			_line(image, 74, 22, 103, 26, 3, INK)


## Fills an axis-aligned ellipse, one pixel at a time. 128x128 is small enough
## that a per-pixel loop costs less than the complexity of a drawing API.
static func ellipse(image: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for y: int in range(maxi(0, cy - ry), mini(SIZE, cy + ry + 1)):
		for x: int in range(maxi(0, cx - rx), mini(SIZE, cx + rx + 1)):
			var nx := float(x - cx) / float(maxi(rx, 1))
			var ny := float(y - cy) / float(maxi(ry, 1))
			if nx * nx + ny * ny <= 1.0:
				image.set_pixel(x, y, color)


## A thick raster line, used for lashes, brows and mouths.
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
