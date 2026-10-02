class_name FarmGrid
extends Node3D
## The tillable plot: a fixed grid of [SoilTile]s laid over the farm's soil area.
##
## Purely a container plus coordinate maths. All the rules live on [SoilTile], so
## this class has exactly one interesting job: turning a grid position into a
## world position and back, consistently. Getting that wrong is how farming games
## end up watering the plot next door, so it is the single source of truth for
## the mapping and the tests pin both directions.
##
## ## How a tile becomes aimable
##
## Each tile gets an invisible `AimVolume` body carrying the interaction
## component. It sits on [constant PhysicsLayers.INTERACTABLE] rather than
## [constant PhysicsLayers.WORLD], which is the whole reason that layer exists:
## the volume has to be tall enough for a crosshair at eye height to hit a patch
## of ground a metre away, and if it were solid the player would be shoving an
## invisible box around the farm. On the interaction layer the probe's ray finds
## it and the player's capsule walks straight through.

## How many tiles along +X. Column index is `tile_index.x`.
@export var columns: int = 7
## How many tiles along +Z. Row index is `tile_index.y`.
@export var rows: int = 5
## Edge length of one tile in metres. The farm soil plane is 22x16, so 7x5 tiles
## at 2m leaves a walkable border inside the fence rather than butting against it.
@export var tile_size: float = 2.0

## Height of the invisible aim volume above the soil.
##
## Kept low on purpose. A tall volume is easier to hit from a standing crosshair,
## but it also stands *between* the player and anything on the farm behind it —
## at 1.4m the plot swallowed the mailbox, the sign and every other prop, and the
## interaction probe could no longer reach any of them. At 0.4m the volume still
## catches a crosshair looking down at the ground, which is the only time soil
## should be aimable, and clears everything standing on it.
@export var aim_height: float = 0.4

## Bumped whenever the tile payload shape changes. Read back by a future
## migration to decide whether the fields it wants are present.
const SAVE_VERSION := 1

var _tiles: Dictionary = {}  # Vector2i -> SoilTile


func _ready() -> void:
	_build()


## Total tile count, for tests and for a "your farm is full" message.
func tile_count() -> int:
	return _tiles.size()


func has_tile(index: Vector2i) -> bool:
	return _tiles.has(index)


## The tile at [param index], or null when out of bounds.
##
## Null rather than a fallback tile: a lookup that silently returned tile 0 would
## let a watering can reach across the farm.
func get_tile(index: Vector2i) -> SoilTile:
	return _tiles.get(index) as SoilTile


func get_tiles() -> Array[SoilTile]:
	var out: Array[SoilTile] = []
	for key: Vector2i in _tiles.keys():
		var tile: Variant = _tiles[key]
		if tile is SoilTile:
			out.append(tile)
	# Stable order, so anything that reports on the farm (a save, a summary, a
	# test) sees the same sequence every time.
	out.sort_custom(func(a: SoilTile, b: SoilTile) -> bool:
		return a.tile_index.y == b.tile_index.y if a.tile_index.y == b.tile_index.y \
			else a.tile_index.x < b.tile_index.x
	)
	return out


## Centre of a tile, in this node's local space.
##
## Centred on (0,0) rather than hung off the first tile. An off-the-corner grid
## puts tile (0,0) at the grid's own origin, which means a 7x5 plot at 2m spans
## +12m in X and +8m in Z from where you asked for it — the far half of the plot
## lands on the road and the near half is behind the player. Centring means
## `position` *is* the middle of the field, which is what every caller assumes.
func tile_to_local(index: Vector2i) -> Vector3:
	return Vector3(
		(index.x - (columns - 1) * 0.5) * tile_size,
		0.0,
		(index.y - (rows - 1) * 0.5) * tile_size
	)


## Centre of a tile in world space.
func tile_to_world(index: Vector2i) -> Vector3:
	return global_transform * tile_to_local(index)


## Which tile contains a world XZ position.
##
## Converts to local space first, so the answer does not depend on where the grid
## happens to be placed in the world — the farm can move without the mapping
## quietly going stale.
##
## Floors rather than rounds. Rounding puts the seam between two tiles in the
## wrong place, so a player standing exactly on a boundary would aim at whichever
## neighbour they were already standing next to. The returned index may be out of
## bounds; callers check with [method has_tile].
func world_to_tile(world: Vector3) -> Vector2i:
	var local := to_local(world)
	return Vector2i(
		int(floorf((local.x + columns * tile_size * 0.5) / tile_size)),
		int(floorf((local.z + rows * tile_size * 0.5) / tile_size))
	)


## World-space bounds of the whole plot, for tests and for camera framing.
func plot_extents() -> Vector2:
	return Vector2(columns * tile_size, rows * tile_size)


## The tile containing a world position, or null when that position is off the
## plot. The everyday entry point for gameplay.
func tile_at(world: Vector3) -> SoilTile:
	var index := world_to_tile(world)
	if not has_tile(index):
		return null
	return get_tile(index)


## Every tile within [param radius] metres of a world position. Used by tool
## sweeps so a multi-tile action covers what the player can see.
##
## Ordered by distance from the centre so the nearest tile is always first,
## which is what a "water what I'm looking at" action should hit first when a
## radius catches more tiles than it should.
func tiles_in_radius(world: Vector3, radius: float) -> Array[SoilTile]:
	var out: Array[SoilTile] = []
	var span := int(ceilf(radius / maxf(tile_size, 0.001)))
	var centre := world_to_tile(world)
	for dz: int in range(-span, span + 1):
		for dx: int in range(-span, span + 1):
			var tile := get_tile(centre + Vector2i(dx, dz))
			if tile != null and tile.global_position.distance_to(world) <= radius:
				out.append(tile)
	out.sort_custom(func(a: SoilTile, b: SoilTile) -> bool:
		return a.global_position.distance_squared_to(world) \
			< b.global_position.distance_squared_to(world)
	)
	return out


func tilled_count() -> int:
	var n := 0
	for tile: SoilTile in get_tiles():
		if tile.is_tilled:
			n += 1
	return n


## How many tiles hold a crop.
func planted_count() -> int:
	var n := 0
	for tile: SoilTile in get_tiles():
		if tile.has_crop():
			n += 1
	return n


## How many tiles have a crop that is ready to pick.
func ripe_count() -> int:
	var n := 0
	for tile: SoilTile in get_tiles():
		if tile.is_ripe():
			n += 1
	return n


## Serialises every tile.
##
## Ordered by index so two saves of the same farm produce byte-identical files,
## which is what makes a save diff reviewable.
func to_dict() -> Dictionary:
	var entries: Array = []
	for tile: SoilTile in get_tiles():
		entries.append(tile.to_dict())
	return {
		"version": SAVE_VERSION,
		"columns": columns,
		"rows": rows,
		"tile_size": tile_size,
		"tiles": entries,
	}


## Restores every tile from [method to_dict].
##
## Copies onto the live tiles the grid already owns rather than rebuilding the
## grid, because rebuilding would recreate 35 nodes and their meshes to change 35
## sets of three fields. Tiles missing from the payload are left alone — a save
## from an older, smaller plot should not erase ground the player has since
## unlocked — and a payload tile with no matching slot is skipped rather than
## aborting the load.
func from_dict(data: Dictionary) -> void:
	var payload: Variant = data.get("tiles", [])
	if not payload is Array:
		Log.warn("FarmGrid", "save payload has no tile list; leaving the farm as-is")
		return
	var restored := 0
	var skipped := 0
	for entry: Variant in payload:
		if not entry is Dictionary:
			skipped += 1
			continue
		var saved := SoilTile.from_dict(entry)
		var existing := get_tile(saved.tile_index)
		if existing == null:
			skipped += 1
			# `from_dict` builds a bare [Node3D], and a node is not refcounted, so
			# letting this one go out of scope leaks it *and* its RNG. Every other
			# exit from this loop has to free it too.
			saved.free()
			continue
		existing.is_tilled = saved.is_tilled
		existing.is_watered = saved.is_watered
		existing.crop_id = saved.crop_id
		existing.growth_days = saved.growth_days
		existing.refresh_visual()
		restored += 1
		saved.free()
	if skipped > 0:
		Log.warn("FarmGrid", "skipped %d saved tiles with no slot here" % skipped)
	Log.info("FarmGrid", "Restored %d/%d tiles" % [restored, _tiles.size()])


func _build() -> void:
	# Rebuilding in the editor or on a hot reload would otherwise double the tile
	# count every time the node re-entered the tree.
	for child: Node in get_children():
		child.queue_free()
	_tiles.clear()

	for r: int in range(rows):
		for c: int in range(columns):
			var index := Vector2i(c, r)
			var tile := SoilTile.new()
			tile.name = "Tile_%d_%d" % [c, r]
			tile.tile_index = index
			add_child(tile)
			# Local position, before `build_visuals`, so the tile has a valid
			# transform by the time anything asks it where it is. Local rather
			# than world so moving the grid moves the plot.
			tile.position = tile_to_local(index)
			tile.build_visuals(tile_size)
			_add_aim_volume(tile)
			_tiles[index] = tile
	Log.info("FarmGrid", "%d tiles over %s m" % [
		_tiles.size(), str(plot_extents())
	])


## The invisible body the interaction probe's ray finds.
##
## Built here rather than in the tile because the grid owns the geometry: it knows
## the tile size and the aim height, and duplicating those numbers in the tile
## would be two places to keep in agreement.
func _add_aim_volume(tile: SoilTile) -> void:
	var body := StaticBody3D.new()
	body.name = "AimVolume"
	# Interaction-only layer: findable by a ray, never solid. See the class docs.
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	# Explicitly named: Godot's auto-generated names cannot be looked up with
	# `get_node_or_null`, which is how a "the collider is missing" bug hides.
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(tile_size * 0.98, aim_height, tile_size * 0.98)
	shape.shape = box
	shape.position = Vector3(0, aim_height * 0.5, 0)
	body.add_child(shape)

	var component := SoilTileInteractable.new()
	component.name = "Interactable"
	body.add_child(component)

	tile.add_child(body)