class_name LocationData
extends Resource
## A named place in the valley that a villager can be sent to.
##
## ## Why this exists
##
## Schedules need to say "Mira is at the well from 08:00", not "Mira is at
## [code]Vector2(30, 4)[/code] from 08:00". A hard-coded coordinate in a schedule is
## invisible to the rest of the project: nothing can validate it, nothing can move it if
## the village moves, and a mistyped one produces a villager who walks into a wall or
## stands in the pond forever with no error anywhere. Naming the place makes the
## destination a thing that can be looked up, checked, and asserted on.
##
## This is the first named-place system in the project. The vocabulary it deliberately
## lines up with is [constant WorldBuilder.REGION_VILLAGE] and friends â€” those are
## region *centres* for scatter placement; these are individual *places* with ids,
## which is the granularity a schedule actually needs.
##
## ## Coordinates
##
## [member position] is a [Vector2] of XZ, not X/Y, because that is the convention
## [member NpcData.home] already uses and the two have to be comparable. [method XZ.y]
## being the world's Z is the single most bug-prone thing in this file, so it is
## spelled out at every use and [method ground_position] is the only place the
## conversion happens.

## Id looked up by [LocationRegistry]. The only required field.
@export var id: StringName = &""

## What a player would call the place. Shown in dialogue later; used in logs now.
@export var display_name: String = ""

## XZ position. `y` is the world's Z.
@export var position: Vector2 = Vector2.ZERO

## How the place is used, for authoring and for tests that want "every work location".
## Free-form on purpose: [constant KIND_HOME] and friends are the ones the game knows,
## but content is not allowed to invent a value the code cannot answer a question about.
@export var kind: StringName = &"place"

## Yaw an arriving villager should settle on, in radians. Zero faces -Z.
##
## Not decoration: a villager who arrives at the well with their back to it reads as
## having no idea where they are, and it is the difference between a person and a
## marker sliding along a rail. [constant FACING_UNSET] leaves the villager's own
## arrival heading alone.
@export var facing: float = 0.0

## Sentinel for [member facing] meaning "do not turn".
const FACING_UNSET := INF

const KIND_HOME := &"home"
const KIND_WORK := &"work"
const KIND_SOCIAL := &"social"
const KIND_NATURE := &"nature"
const KIND_FOOD := &"food"

## Every kind this file defines. A content test asserts that nothing else is used, so a
## typo becomes a failing test instead of a place nobody can find.
const KINDS: Array[StringName] = [
	KIND_HOME, KIND_WORK, KIND_SOCIAL, KIND_NATURE, KIND_FOOD,
]


func has_facing() -> bool:
	return not is_inf(facing)


## The world position with the ground height applied, feet on the terrain.
##
## [method WorldTerrain.terrain_height] is the same function the terrain mesh was built
## from, so a villager sent here stands on the ground rather than hovering or sinking.
## Near the pond this matters: the basin is 2.2 m deep, and an anchor on its edge sent
## to a flat Y would drop the villager into the water.
func ground_position() -> Vector3:
	return Vector3(
		position.x,
		WorldTerrain.terrain_height(position.x, position.y),
		position.y,
	)


func is_valid() -> bool:
	if id.is_empty():
		return false
	if display_name.strip_edges().is_empty():
		return false
	if not KINDS.has(kind):
		return false
	if not has_facing() and facing != FACING_UNSET:
		return false
	# Off the edge of the generated ground is a typo, not a destination.
	var limit := WorldTerrain.GROUND_SIZE * 0.5
	if absf(position.x) > limit or absf(position.y) > limit:
		return false
	return true


func describe() -> String:
	return "%s (%s) at %s" % [display_name, kind, str(position)]