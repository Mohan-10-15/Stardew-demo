extends Control
## Draws the aiming crosshair: a plus, always.
##
## Drawn in code rather than sampled from a texture so it stays crisp at any resolution
## and can react to the interaction state.
##
## ## Always a plus
##
## The first version drew a bare dot and grew arms only when something was focused, on
## the theory that the arms were clutter over an empty field. In a real window that reads
## as a dot that sometimes grows, not as a crosshair: the marker's shape is what tells the
## player where the interaction ray starts, and a shape that changes means the player never
## learns where "here" is. A plus is a plus in every situation, so what changes is only
## how brightly it is drawn.
##
## The brightness still carries the one bit of information worth carrying: a dim plus is
## aimed at nothing, a bright plus is aimed at something you can interact with.

## Half-length of each arm, measured out from the gap.
const ARM_LENGTH := 7.0
## Half the empty space at the centre. Non-zero, so the middle of the crosshair is not
## solid black over a bright sky.
const GAP := 2.0
const THICKNESS := 2.0

@export var color: Color = Color(0.95, 0.95, 0.92, 0.85)
@export var outline_color: Color = Color(0, 0, 0, 0.6)
## Drawn dimmed when nothing is focused.
@export var idle_color: Color = Color(0.86, 0.86, 0.84, 0.45)
## Radius of the centre dot that closes the gap on the plus.
@export var dot_radius: float = 1.5

var _focused: bool = false


func _ready() -> void:
	set_process(true)


func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	queue_redraw()


## The plus, as four segments with a gap at the middle.
##
## `add_theme` nothing: an outline is drawn as a second, thicker polyline underneath,
## which is what keeps it readable against both a bright sky and dark soil.
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
	draw_polyline(arms, color if _focused else idle_color, THICKNESS)
	draw_circle(centre, dot_radius, color if _focused else idle_color)