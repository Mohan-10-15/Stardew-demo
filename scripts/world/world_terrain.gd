class_name WorldTerrain
extends RefCounted
## The shape of the valley's ground: what height is where, and why.
##
## ## Why this is separate from [WorldBuilder]
##
## [method WorldBuilder.terrain_height] was where this lived, and it was fine until
## content data needed it. [LocationData] wants the ground height so a villager sent to
## the pond shore stands on the slope instead of in the water, and reaching for
## [WorldBuilder] to get it dragged the entire world-building chain — houses, props, the
## interaction system, [EventBus], [Log] — into the compile of every content tool that
## touches a location. That is how `tools/generate_npc_schedules.gd` ended up unable to
## compile on a project with nothing wrong with it.
##
## The height function is pure and depends on three numbers. Those three numbers and the
## function are here, [WorldBuilder] delegates to them, and content data can ask the
## terrain a question without asking the world builder to build a world.
##
## Nothing here is authored twice. [WorldBuilder]'s constants are aliases of these, not
## copies, so moving the pond moves both.

## Extent of the generated ground, as a square centred on the origin.
const GROUND_SIZE := 220.0

## Ground is generated as a grid of this many cells per side.
const GROUND_CELLS := 44

## Size of the pond basin, as a radius in metres.
const POND_RADIUS := 17.0

## Depth of the basin at its centre, below the surrounding ground.
const POND_FLOOR_DEPTH := -2.2

## Flat ground height everywhere outside the pond basin.
const GROUND_LEVEL := 0.0

## Where the pond basin is centred, as XZ.
const REGION_POND := Vector2(-14, 44)

## Ground is flat at [constant GROUND_LEVEL] for every point at least
## [constant POND_RADIUS] from [constant REGION_POND].
##
## This is the same function the render mesh and its concave collision shape are both
## built from, which is the only reason a villager standing on [method ground_height] is
## guaranteed to be standing on the ground rather than near it.
static func terrain_height(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(REGION_POND)
	if d >= POND_RADIUS:
		return GROUND_LEVEL
	# Smoothstep from the rim down to the basin floor, so the shoreline is a slope
	# rather than a cliff and the water plane meets land naturally.
	var t := 1.0 - d / POND_RADIUS
	return lerpf(GROUND_LEVEL, POND_FLOOR_DEPTH, t * t * (3.0 - 2.0 * t))


## The ground height at an XZ point, as a full position with the feet on it.
##
## The convenience form for the three callers that all ended up writing the same three
## lines and mis-spelling `Vector2.y`-is-the-world's-Z at least once.
static func ground_height_at(xz: Vector2) -> float:
	return terrain_height(xz.x, xz.y)


## Whether a point is inside the pond basin rather than on the shore.
static func is_in_water(x: float, z: float) -> bool:
	return terrain_height(x, z) < WATER_LEVEL


## Water surface height. Negative so the pond reads as a basin below the surrounding
## valley rather than a sheet of water laid on top of the grass.
const WATER_LEVEL := -0.8

## Radius of the visible water plane, slightly inside the basin so the slope shows
## through at the shoreline.
const POND_WATER_RADIUS := 16.0