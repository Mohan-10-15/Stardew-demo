extends Control
## Draws the aiming crosshair.
##
## Drawn in code rather than sampled from a texture so it stays crisp at any
## resolution and can react to the interaction state later (for example
## highlighting when an interactable is focused).

const ARM_LENGTH := 7.0
const GAP := 3.0
const THICKNESS := 2.0

@export var color: Color = Color(0.95, 0.95, 0.92, 0.85)
@export var outline_color: Color = Color(0, 0, 0, 0.6)
## Radius of the centre dot.
@export var dot_radius: float = 1.5

var _focused: bool = false


func _ready() -> void:
	set_process(true)


func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var arms := PackedVector2Array([
		Vector2(centre.x - GAP - ARM_LENGTH, centre.y),
		Vector2(centre.x - GAP, centre.y),
		Vector2(centre.x + GAP, centre.y),
		Vector2(centre.x + GAP + ARM_LENGTH, centre.y),
		Vector2(centre.x, centre.y - GAP - ARM_LENGTH),
		Vector2(centre.x, centre.y - GAP),
		Vector2(centre.x, centre.y + GAP),
		Vector2(centre.x, centre.y + GAP + ARM_LENGTH),
	])
	draw_polyline(arms, outline_color, THICKNESS + 2.0)
	draw_circle(centre, dot_radius, outline_color)
	if _focused:
		draw_polyline(arms, color, THICKNESS)
		draw_circle(centre, dot_radius, color)
	else:
		# Unfocused: a dimmer dot only, so the arms do not clutter the screen.
		draw_circle(centre, dot_radius, color)