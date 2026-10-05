class_name NpcNavigation
extends Node3D
## A walkability grid for the valley, built by probing the world's own colliders.
##
## ## Why not a NavMesh
##
## There is no [NavMesh] in the project and adding one means authoring a bake, keeping
## it in step with a world that is generated in code, and re-baking it whenever the
## terrain or a building moves. The world here is flat around every place that matters,
## the obstacles are boxes and cylinders, and the thing we need is "can a person walk
## from here to there without going through a wall". A grid over the collision answer
## answers that directly, with no bake step and no second source of truth about where
## the walls are.
##
## So the grid is **derived from the colliders rather than authored beside them**. There
## is no way for a house to be solid in the world and missing from the grid, because the
## grid is built by asking the physics server what is there. That is the whole reason to
## probe instead of hand-painting walkability.
##
## ## The two probes
##
## A cell is walkable only if both of these pass, and both are needed:
##
## - **Floor.** A ray straight down finds ground, and the ground has to be at roughly
##   foot height. This is what rejects the pond. The pond basin is 2.2 m below the rim
##   and has its own floor collider, so a walkability test that only asked "is there
##   something to stand on" would cheerfully send villagers swimming.
## - **Clearance.** A sphere the width of a villager's shoulders finds nothing at chest
##   height. This is what rejects house interiors, the shop counter, the well and every
##   tree trunk.
##
## The floor probe is what keeps the clearance sphere honest: the ground is a concave
## trimesh on [constant PhysicsLayers.WORLD], the same layer as the houses, so a
## clearance test cannot tell them apart by layer. Lifting the sphere clear of the floor
## lets the floor answer the first probe and the walls answer the second.

## Grid resolution in metres. One metre is finer than the gaps between village
## buildings and coarse enough to keep the probe count in the low thousands.
const CELL_SIZE := 1.0

## Where the grid starts, as XZ. Chosen to cover the village, the farm, the pond shore
## and the forest edge â€” every place a schedule sends a villager â€” while leaving the far
## corners of the 220 m ground unprobed, because nothing lives out there.
const ORIGIN := Vector2(-50.0, -32.0)

## Grid extent in cells.
const SIZE := Vector2i(112, 96)

## Radius of the clearance sphere, in metres.
##
## [constant Npc]'s capsule radius plus a margin. A villager who is 0.35 m wide does not
## need 0.35 m of clearance to their *own* front step to be reachable, but a path that
## shaves a corner at 0.3 m produces a villager visibly scraping along a wall, and the
## margin is what buys the diagonal that does not.
const CLEARANCE_RADIUS := 0.5

## How far above the floor the clearance sphere is centred. High enough that a sphere of
## [constant CLEARANCE_RADIUS] cannot touch the floor, low enough that it is still below
## the 2.4 m interaction volumes and inside a villager's 1.7 m body.
const CLEARANCE_HEIGHT := 1.0

## The playable ground band the floor probe accepts, in metres relative to `y = 0`.
##
## [constant WorldTerrain.GROUND_LEVEL] is 0 everywhere except the pond basin, so the
## upper bound only ever catches a cell that has somehow landed on a roof, and the lower
## bound is what excludes water.
const FLOOR_MIN_Y := -0.5
const FLOOR_MAX_Y := 0.6

## How far up the floor ray starts, and how far down it reaches.
const FLOOR_RAY_FROM := 4.0
const FLOOR_RAY_TO := -6.0

## The built grid. Null until [method build] has run.
var astar: AStarGrid2D = null

## Cells found walkable, and how many were rejected, for the boot log and for tests.
var walkable_cells: int = 0
var blocked_cells: int = 0


## Builds the grid. Must run after the world's colliders exist.
##
## Returns false and leaves [member astar] null if there is no physics world to ask, so
## a caller in a headless run with no scene gets a clear "no navigation" rather than a
## crash on the first path request.
func build() -> bool:
	astar = null
	walkable_cells = 0
	blocked_cells = 0
	var space := _direct_space()
	if space == null:
		Log.warn("NpcNav", "no physics space to probe; villagers will wander locally")
		return false

	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, SIZE.x, SIZE.y)
	grid.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	grid.offset = ORIGIN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

	for z: int in range(SIZE.y):
		for x: int in range(SIZE.x):
			var cell := Vector2i(x, z)
			if _is_walkable(cell, space):
				walkable_cells += 1
			else:
				grid.set_point_solid(cell)
				blocked_cells += 1

	astar = grid
	Log.info("NpcNav", "Grid built: %d walkable, %d blocked over %dx%d cells" % [
		walkable_cells, blocked_cells, SIZE.x, SIZE.y,
	])
	return true


## A path from one world point to another, or empty if there is none.
##
## Returns empty rather than null so the caller can write [code]if path.is_empty()[/code].
## Both ends are snapped to the nearest walkable cell: a villager standing a centimetre
## inside a blocked cell will not refuse to leave, and a destination that lands on an
## unwalkable spot degrades to "walk as close as you can" rather than sitting against a
## wall forever.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if astar == null:
		return PackedVector3Array()
	var start := _nearest_open(cell_of(from))
	var goal := _nearest_open(cell_of(to))
	if start.x < 0 or goal.x < 0:
		return PackedVector3Array()
	if start == goal:
		var single := PackedVector3Array()
		single.append(_point_of(goal))
		return single
	var cells := astar.get_id_path(start, goal)
	var out := PackedVector3Array()
	for cell: Vector2i in cells:
		out.append(_point_of(cell))
	return out


## Whether [param point] is on walkable ground, as the grid sees it.
func is_walkable(point: Vector3) -> bool:
	if astar == null:
		return false
	return not astar.is_point_solid(cell_of(point))


## The grid cell a world XZ point falls in.
static func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(
		floori((point.x - ORIGIN.x) / CELL_SIZE),
		floori((point.z - ORIGIN.y) / CELL_SIZE),
	)


## The world XZ centre of a grid cell.
static func _point_of(cell: Vector2i) -> Vector3:
	var x := ORIGIN.x + (float(cell.x) + 0.5) * CELL_SIZE
	var z := ORIGIN.y + (float(cell.y) + 0.5) * CELL_SIZE
	return Vector3(x, WorldTerrain.terrain_height(x, z), z)


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE.x and cell.y < SIZE.y


## The nearest cell to [param cell] that is not solid, searched in rings.
##
## Bounded so a request in a part of the world the grid does not cover returns "no
## path" rather than spinning through a whole region looking for somewhere legal.
const SNAP_RADIUS := 6

func _nearest_open(cell: Vector2i) -> Vector2i:
	if not _in_bounds(cell):
		return Vector2i(-1, -1)
	if not astar.is_point_solid(cell):
		return cell
	for radius: int in range(1, SNAP_RADIUS + 1):
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				# Only the ring, not the filled square, or this re-tests the interior
				# of the previous ring and the search becomes quadratic for nothing.
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var probe := cell + Vector2i(dx, dz)
				if _in_bounds(probe) and not astar.is_point_solid(probe):
					return probe
	return Vector2i(-1, -1)


## Whether one cell is ground a villager can stand on and walk across.
func _is_walkable(cell: Vector2i, space: PhysicsDirectSpaceState3D) -> bool:
	if not _in_bounds(cell):
		return false
	var xz := _point_of(cell)
	var floor_y := _floor_height(xz, space)
	if floor_y < FLOOR_MIN_Y or floor_y > FLOOR_MAX_Y:
		return false
	return not _is_blocked(Vector3(xz.x, floor_y + CLEARANCE_HEIGHT, xz.z), space)


func _floor_height(xz: Vector3, space: PhysicsDirectSpaceState3D) -> float:
	if space == null:
		return WorldTerrain.terrain_height(xz.x, xz.z)
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, FLOOR_RAY_FROM, xz.z),
		Vector3(xz.x, FLOOR_RAY_TO, xz.z),
		PhysicsLayers.WORLD,
	)
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return WorldTerrain.terrain_height(xz.x, xz.z)
	var pos: Vector3 = hit["position"]
	return pos.y


## Whether anything on [constant PhysicsLayers.WORLD] occupies chest height here.
func _is_blocked(at: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CLEARANCE_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = PhysicsLayers.WORLD
	# Aim volumes live on the interaction layer and are already excluded by the mask, but
	# an area-based collider on WORLD would be a trap for a later prop: they do not block
	# movement, so the grid must not treat them as if they did.
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_shape(query, 1).size() > 0


func _direct_space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	var world := get_world_3d()
	if world == null:
		return null
	return world.direct_space_state