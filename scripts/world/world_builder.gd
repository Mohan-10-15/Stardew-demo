class_name WorldBuilder
extends RefCounted
## Procedural construction of the starting valley.
##
## Deliberately small and hand-tuned rather than infinite: the brief asks for a
## polished test area first. All geometry is built from Godot primitives so the
## game has zero external art dependencies at this stage.
##
## Collision is created alongside visuals for anything the player can walk into.

const GROUND_SIZE := 220.0
## Ground is generated as a grid of this many cells per side.
const GROUND_CELLS := 44
## Size of the pond, measured as its radius in metres. The basin is generated
## out to this distance; the visible water plane is slightly smaller.
const POND_RADIUS := 17.0
const POND_WATER_RADIUS := 16.0
## Water surface height. Negative so the pond reads as a basin below the
## surrounding valley rather than a sheet of water laid on top of the grass.
const WATER_LEVEL := -0.8
## Depth of the basin at its centre, below the water surface so the water has
## somewhere to sit.
const POND_FLOOR_DEPTH := -2.2
## Ground is flat at this height everywhere except inside the pond basin.
const GROUND_LEVEL := 0.0
## Interactable props pad their collider up to this height so a crosshair at
## eye level can actually hit them.
const INTERACTION_COLLIDER_MIN_HEIGHT := 2.4

const COL_GRASS := Color(0.36, 0.62, 0.31)
const COL_DIRT := Color(0.45, 0.33, 0.22)
const COL_PATH := Color(0.62, 0.55, 0.42)
const COL_WATER := Color(0.24, 0.48, 0.66, 0.75)
const COL_WOOD := Color(0.38, 0.26, 0.16)
const COL_ROCK := Color(0.52, 0.52, 0.55)
const COL_WALL := Color(0.78, 0.72, 0.62)
const COL_ROOF := Color(0.62, 0.31, 0.28)
const COL_FENCE := Color(0.52, 0.38, 0.24)

## Region centres, kept in one place so later groups (world expansion, minimap,
## area transitions) can reference them by name.
const REGION_FARM := Vector2(0, -20)
const REGION_VILLAGE := Vector2(38, 8)
const REGION_FOREST := Vector2(-42, 26)
const REGION_POND := Vector2(-14, 44)


## Builds the whole scene and returns the populated root node.
static func build(root: Node3D, seed_value: int = 12345) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	_build_ground(root)
	_build_water(root)
	_build_paths(root)
	_build_farm(root)
	_build_shop(root)
	_build_village(root, rng)
	_build_resources(root, rng)
	_build_interactables(root)


## Height of the terrain at a world XZ position.
##
## Flat across the valley, except for a smooth basin over the pond so the water
## sits *in* the ground. Pure and deterministic: the visual mesh and the
## collision mesh are both generated from this function, so they cannot disagree
## the way an independently-authored collider can.
static func terrain_height(x: float, z: float) -> float:
	var centre := Vector2(REGION_POND.x, REGION_POND.y)
	var d := Vector2(x, z).distance_to(centre)
	if d >= POND_RADIUS:
		return GROUND_LEVEL
	# Smoothstep from the rim down to the basin floor, so the shoreline is a
	# slope rather than a cliff and the water plane meets land naturally.
	var t := 1.0 - d / POND_RADIUS
	var s := t * t * (3.0 - 2.0 * t)
	return lerpf(GROUND_LEVEL, POND_FLOOR_DEPTH, s)


static func _build_ground(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	_build_grid(vertices, normals, uvs, colors, indices, faces)

	# Trimesh collision from the *same* vertices as the visual mesh, so what the
	# player walks on is exactly what they see. A box collider cannot represent
	# the pond basin, which is what previously let the player walk over the
	# water surface.
	#
	# `set_faces()` takes three vertices per face. The `data` property looks like
	# the obvious assignment and is wrong: it reinterprets a flat vertex array
	# as consecutive face triples, so a 3875-vertex grid becomes 1291 arbitrary
	# triangles plus two leftover vertices, and nothing collides. Verified by
	# probe: `data =` misses a downward ray, `set_faces()` hits it at y=0.
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var trimesh := ConcavePolygonShape3D.new()
	trimesh.set_faces(faces)
	shape.shape = trimesh
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	mesh.name = "GroundMesh"
	var array_mesh := ArrayMesh.new()
	mesh.mesh = array_mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.material_override = WorldMaterials.surface(&"grass")
	body.add_child(mesh)

	_finish(body, root)


## Fills a flat XZ grid of GROUND_CELLS cells, sampling [method terrain_height]
## for each vertex.
##
## Produces the vertex/normal/uv/color/index arrays for the visual mesh and a separate
## three-vertices-per-face list for the collider, both from this one pass.
static func _build_grid(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	faces: PackedVector3Array
) -> void:
	var step := GROUND_SIZE / float(GROUND_CELLS)
	var half := GROUND_SIZE * 0.5

	for gz: int in range(GROUND_CELLS + 1):
		for gx: int in range(GROUND_CELLS + 1):
			var x := -half + gx * step
			var z := -half + gz * step
			var height := terrain_height(x, z)
			vertices.append(Vector3(x, height, z))
			normals.append(Vector3.UP)
			# The ground's UVs run 0..1 across the whole 160m terrain, so anything
			# tiled on it has to be tiled again by `uv1_scale`. They are scaled here
			# rather than left 0..1 so that a per-metre tiling in the material means
			# the same thing on the ground as on a 2m fence post.
			uvs.append(Vector2(gx / float(GROUND_CELLS), gz / float(GROUND_CELLS)) * GROUND_SIZE)
			colors.append(ground_tint(x, z, height))

	# Two triangles per cell, wound counter-clockwise when seen from above so
	# the surface faces up.
	var stride := GROUND_CELLS + 1
	for gz: int in range(GROUND_CELLS):
		for gx: int in range(GROUND_CELLS):
			var a := gz * stride + gx
			var b := a + 1
			var c := a + stride
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])

	# Collision needs vertices rather than indices, so expand once here.
	# ~3900 faces becomes ~11600 Vector3s, which is fine for a static body.
	#
	# The winding is reversed relative to the render index buffer on purpose.
	# `ConcavePolygonShape3D` treats a clockwise face (viewed from above) as the
	# front, while the renderer's front face is counter-clockwise. Feeding it
	# the render winding produces a mesh that looks perfect and collides with
	# nothing: rays pass straight through and the player falls. Reversing here
	# keeps one source of truth for the geometry without flipping the visual
	# mesh inside out.
	for i: int in range(0, indices.size(), 3):
		faces.append(vertices[indices[i + 2]])
		faces.append(vertices[indices[i + 1]])
		faces.append(vertices[indices[i]])

	_compute_normals(vertices, normals, indices)


## Recomputes smooth vertex normals by area-weighted face accumulation.
##
## The grid is authored with flat `Vector3.UP` normals, which would light the
## basin walls as if they were horizontal - the pond slope would be invisible.
static func _compute_normals(
	vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array
) -> void:
	var accumulated := PackedVector3Array()
	accumulated.resize(vertices.size())

	var i: int = 0
	while i < indices.size():
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		# Not normalised: cross-product magnitude is twice the triangle area, so
		# summing unnormalised faces weights large triangles more heavily, which
		# is what we want for smooth shading.
		var face := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
		accumulated[ia] += face
		accumulated[ib] += face
		accumulated[ic] += face
		i += 3

	for v: int in range(vertices.size()):
		var n := accumulated[v]
		normals[v] = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP


## The water surface, sized to sit inside the basin so its rim is hidden by the
## shoreline rather than ending in mid-air over the grass.
static func _build_water(root: Node3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Pond"
	var plane := PlaneMesh.new()
	plane.size = Vector2(POND_WATER_RADIUS * 2.0, POND_WATER_RADIUS * 2.0)
	mesh.mesh = plane
	mesh.position = Vector3(REGION_POND.x, WATER_LEVEL, REGION_POND.y)
	var m := WorldMaterials.surface(&"water")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = m
	_finish(mesh, root)

	# A shallow invisible slab below the basin floor so nothing can fall through
	# the world at the deepest point of the pond.
	var body := StaticBody3D.new()
	body.name = "PondFloor"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(POND_WATER_RADIUS * 2.0, 0.5, POND_WATER_RADIUS * 2.0)
	shape.shape = box
	shape.position = Vector3(REGION_POND.x, POND_FLOOR_DEPTH - 0.9, REGION_POND.y)
	body.add_child(shape)
	_finish(body, root)


static func _build_paths(root: Node3D) -> void:
	# Village -> farm, the spine of the starting area.
	for segment: Array in PATH_SEGMENTS:
		_add_path_segment(root, segment[0], segment[1], segment[2])


## Every walkable path in the valley, as `[from, to, width]`.
##
## The single source for both the path meshes and the resource scatter's keep-out.
## They used to be separate knowledge — the meshes were built from literals in
## [method _build_paths] and the keep-out rule simply did not exist — and a tree
## could stand in the middle of the road because nothing that drew the road was
## asked where the road was.
const PATH_SEGMENTS: Array[Array] = [
	[REGION_VILLAGE, REGION_FARM, 3.4],
	[REGION_FARM, REGION_FOREST, 2.8],
	[REGION_FARM, Vector2(REGION_FARM.x, REGION_POND.y - 12), 2.4],
]


static func _add_path_segment(root: Node3D, from: Vector2, to: Vector2, width: float) -> void:
	var mid := (from + to) * 0.5
	var delta := to - from
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, delta.length())
	mesh.mesh = plane
	mesh.material_override = WorldMaterials.surface(&"path")
	mesh.position = Vector3(mid.x, 0.02, mid.y)
	# PlaneMesh lies in XZ; align its local Z with the segment direction.
	var angle := atan2(delta.x, delta.y)
	mesh.rotation.y = angle
	_finish(mesh, root)


static func _build_farm(root: Node3D) -> void:
	var soil := MeshInstance3D.new()
	soil.name = "FarmSoil"
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 16)
	soil.mesh = plane
	soil.position = Vector3(REGION_FARM.x, 0.03, REGION_FARM.y)
	soil.material_override = WorldMaterials.surface(&"dirt")
	_finish(soil, root)

	# Perimeter fence posts with rails, giving the farm a readable silhouette.
	var corners := [
		Vector3(REGION_FARM.x - 11, 0, REGION_FARM.y - 8),
		Vector3(REGION_FARM.x + 11, 0, REGION_FARM.y - 8),
		Vector3(REGION_FARM.x + 11, 0, REGION_FARM.y + 8),
		Vector3(REGION_FARM.x - 11, 0, REGION_FARM.y + 8),
	]
	for i: int in range(corners.size()):
		_add_post(root, corners[i])
		_add_rail(root, corners[i], corners[(i + 1) % corners.size()])


## Where the general store stands.
##
## Just outside the farm fence, on the +X side, at the farm's own Z so the walk
## from the middle of the plot is straight and short. Deliberately *not* on the
## spawn-to-village sightline at `x = 0`: `test_interaction`'s fixtures stand at
## `(0, 0.2, 12.5)` aiming down -Z, and the mailbox already had to move off that
## axis for exactly this reason. Two props fighting over one test corridor is not a
## thing to discover twice.
const SHOP_POSITION := Vector3(14.5, 0, REGION_FARM.y)


static func _build_shop(root: Node3D) -> void:
	var shop := Shop.new()
	shop.name = "GeneralStore"
	# The definition is assigned *before* the node enters the tree, because
	# `_ready` validates it and would otherwise warn about a counter that was only
	# ever half-built. An ordinary property assignment on a parentless node is
	# harmless; only `position` is not (see `AGENTS.md`, "Two Godot-specific
	# traps").
	var definition := ShopRegistry.get_shop(&"general_store")
	if definition == null:
		Log.error(
			"WorldBuilder", "no 'general_store' definition; the counter will be inert"
		)
	else:
		shop.shop = definition
	root.add_child(shop)
	shop.position = SHOP_POSITION

	# The stall itself, as a child so the whole counter moves as one thing.
	var stall := StaticBody3D.new()
	stall.name = "Stall"
	stall.collision_layer = 1
	shop.add_child(stall)

	var canopy := MeshInstance3D.new()
	var roof := BoxMesh.new()
	roof.size = Vector3(2.4, 0.12, 1.6)
	canopy.mesh = roof
	canopy.position = Vector3(0, 2.1, 0)
	canopy.material_override = WorldMaterials.surface(&"roof")
	stall.add_child(canopy)

	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var pole := BoxMesh.new()
		pole.size = Vector3(0.12, 2.1, 0.12)
		leg.mesh = pole
		leg.position = Vector3(side * 1.1, 1.05, 0)
		leg.material_override = WorldMaterials.surface(&"wood")
		stall.add_child(leg)

	var counter := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(2.2, 0.9, 0.8)
	counter.mesh = top
	counter.position = Vector3(0, 0.45, 0)
	counter.material_override = WorldMaterials.surface(&"wall")
	stall.add_child(counter)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = top.size
	shape.shape = box
	shape.position = counter.position
	stall.add_child(shape)


static func _add_post(root: Node3D, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = at

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 1.0, 0.16)
	mesh.mesh = box
	mesh.position = Vector3(0, 0.5, 0)
	mesh.material_override = WorldMaterials.surface(&"fence")
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var col := BoxShape3D.new()
	col.size = box.size
	shape.shape = col
	shape.position = Vector3(0, 0.5, 0)
	body.add_child(shape)

	_finish(body, root)


static func _add_rail(root: Node3D, from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var delta := to - from
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = Vector3(mid.x, 0.62, mid.z)
	body.rotation.y = atan2(delta.x, delta.z)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.1, delta.length())
	mesh.mesh = box
	mesh.material_override = WorldMaterials.surface(&"fence")
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var col := BoxShape3D.new()
	col.size = box.size
	shape.shape = col
	body.add_child(shape)

	_finish(body, root)


## Where the player starts.
##
## The single source of truth for the spawn, and [member WorldRoot.spawn_point]
## defaults its own value from this constant rather than carrying a second copy.
##
## It was originally written here as `(0, 0, 0)` — a plausible-looking guess at the
## middle of the valley — while the player was actually starting at `(0, 1.2, 14)`.
## Nothing failed. The keep-out simply protected an empty patch of grass fourteen
## metres from the player and left the real spawn inside the resource scatter, which
## is a tree growing out of the player's head on some seeds and not others. Duplicating
## a constant is how that happens; `no_resource_is_spawned_where_the_player_stands`
## is the test that keeps it from happening again.
const SPAWN_POINT := Vector3(0, 0, 14)
## How much cleared ground the spawn wants, in metres.
const SPAWN_CLEARANCE := 6.0

static func _build_village(root: Node3D, rng: RandomNumberGenerator) -> void:
	var houses := [
		REGION_VILLAGE + Vector2(-9, -6),
		REGION_VILLAGE + Vector2(6, -8),
		REGION_VILLAGE + Vector2(10, 5),
		REGION_VILLAGE + Vector2(-4, 8),
	]
	for i: int in range(houses.size()):
		_add_house(root, houses[i], 5.0 + rng.randf_range(-0.6, 0.6), 4.5 + rng.randf_range(-0.5, 0.5))

	# The player's own house, a little larger and clearly the home base.
	_add_house(root, REGION_VILLAGE + Vector2(-16, 2), 7.0, 6.0)


static func _add_house(root: Node3D, centre: Vector2, width: float, depth: float) -> void:
	var body := StaticBody3D.new()
	body.name = "House"
	body.collision_layer = 1
	body.position = Vector3(centre.x, 0, centre.y)
	body.rotation.y = rng_rotate(centre)

	var height := 3.0
	var walls := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	walls.mesh = box
	walls.position = Vector3(0, height * 0.5, 0)
	walls.material_override = WorldMaterials.surface(&"wall")
	body.add_child(walls)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var col := BoxShape3D.new()
	col.size = box.size
	shape.shape = col
	shape.position = walls.position
	body.add_child(shape)

	# Simple hipped roof from a scaled cone: readable silhouette, no custom mesh.
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(width * 1.18, 1.6, depth * 1.18)
	roof.mesh = prism
	roof.position = Vector3(0, height + 0.8, 0)
	roof.material_override = WorldMaterials.surface(&"roof")
	body.add_child(roof)

	# Door and windows, purely visual but they make the village feel inhabited.
	var door := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.0, 1.9, 0.12)
	door.mesh = door_box
	door.position = Vector3(0, 0.95, -depth * 0.5 - 0.06)
	door.material_override = WorldMaterials.surface(&"door")
	body.add_child(door)

	for side: float in [-1.0, 1.0]:
		var window := MeshInstance3D.new()
		var win_box := BoxMesh.new()
		win_box.size = Vector3(0.1, 0.9, 0.9)
		window.mesh = win_box
		window.position = Vector3(side * (width * 0.5 + 0.05), 1.7, 0)
		window.material_override = WorldMaterials.surface(&"glass")
		body.add_child(window)

	_finish(body, root)


static func rng_rotate(centre: Vector2) -> float:
	# Deterministic per-position jitter so houses do not all face the same way.
	return sin(centre.x * 0.37 + centre.y * 0.21) * 0.18


## Scatter every authored gatherable node into one [ResourceField].
##
## Replaces two earlier builders: `_build_forest` drew 46 cylinder-and-sphere trees
## that looked like the wood but could not be touched, and `_build_rocks` scattered
## 22 grey spheres that were scenery. Both were the same bug — the valley told the
## player where to look and had nothing to say when they got there — and both are
## gone rather than hidden, because a decorative tree next to a choppable one is the
## same bug wearing a different hat.
##
## Placement is here and not in [ResourceField] deliberately. The field owns nodes
## once they exist; *where* the valley's oak grove is, is a fact about the valley.
## Which keeps the scatter rules — keep off the paths, out of the pond, clear of the
## farm fence — in one function instead of one per node type.
static func _build_resources(root: Node3D, rng: RandomNumberGenerator) -> void:
	var field := ResourceField.new()
	field.name = "ResourceField"
	# `_finish` sets the owner, which is what lets a headless test walk the tree and
	# find the field by name rather than by guessing a path.
	_finish(field, root)

	# Sorted by id, so the same seed produces the same nodes in the same order on
	# every machine. That order is the save order (see `ResourceField.to_dict`), and
	# a world whose node 3 is a different tree depending on the filesystem's mood is a
	# world whose saves are a lottery.
	for data: ResourceNodeData in ResourceNodeRegistry.spawnable_nodes():
		_scatter(data, field, rng)


## Places [param count] of [param data] around its own region.
##
## One seeded generator for the whole field, consumed in a fixed order, so
## placement is deterministic — and the rejection loop is bounded rather than
## infinite, because a keep-out that covers the whole region would otherwise hang the
## boot. A node that cannot find room is skipped and logged, not forced into a spot
## on the path.
static func _scatter(data: ResourceNodeData, field: ResourceField, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var attempts := data.spawn_count * 12
	for _i: int in range(attempts):
		if placed >= data.spawn_count:
			break
		var angle := rng.randf() * TAU
		# Sqrt, not a uniform radius: a uniform draw clusters everything in the middle
		# of the region and leaves its edge bare, which reads as a ring of trees rather
		# than a wood.
		var radius := sqrt(rng.randf()) * data.spawn_radius
		var candidate := data.spawn_region + Vector2(cos(angle), sin(angle)) * radius
		if is_reserved(candidate):
			continue
		if _too_close(field, candidate, data.spawn_spacing):
			continue
		var node := field.add_node(data, Vector3(candidate.x, 0.0, candidate.y))
		if node == null:
			continue
		# A touch of rotation so a grove is not a grid of identically facing models.
		# Derived from the node's own site index rather than a second `rng` sequence,
		# so adding a node type cannot shift the rotation of every tree after it.
		node.rotation.y = rng.randf() * TAU
		placed += 1
	if placed < data.spawn_count:
		Log.info("WorldBuilder", "%s: placed %d of %d" % [
			data.id, placed, data.spawn_count,
		])


## Whether [param pos] is somewhere a gatherable must not stand.
##
## One list of rules rather than a rule per builder, so "the path stays walkable" is
## a single fact with a single implementation. The path check is the important one:
## a 1.2 m oak trunk across the farm-to-village path would wall the starting area in
## half, and it would look like a bug rather than like scenery.
##
## Public because [DecorationField] asks the same question. Two keep-out lists that
## drift apart produce a valley where a path is clear of trees and full of bushes.
static func is_reserved(pos: Vector2) -> bool:
	# Inside the pond basin, and the water plus a shoreline margin.
	if pos.distance_to(REGION_POND) < POND_RADIUS + 2.0:
		return true
	# The farm plot and its fence line.
	if pos.distance_to(REGION_FARM) < 15.0:
		return true
	# The village, including the player's house on its west side.
	if pos.distance_to(REGION_VILLAGE) < 17.0:
		return true
	# The general store's frontage.
	if Vector2(pos.x - SHOP_POSITION.x, pos.y - SHOP_POSITION.z).length() < 5.0:
		return true
	# The walkable width of every path, with a small margin for a canopy overhanging
	# it.
	for segment: Array in PATH_SEGMENTS:
		if _distance_to_segment(pos, segment[0], segment[1]) < segment[2] + 1.2:
			return true
	# The spawn point, so a new game never opens with a tree in the player's face.
	if pos.distance_to(Vector2(SPAWN_POINT.x, SPAWN_POINT.z)) < SPAWN_CLEARANCE:
		return true
	return false


## Shortest distance from [param pos] to the segment [param from]-[param to].
##
## Standard point-to-segment projection, clamped at the ends so a point beyond an
## endpoint measures to that endpoint rather than to the infinite line through it —
## which would let a tree stand on a path because it happened to be collinear with
## one.
static func _distance_to_segment(pos: Vector2, from: Vector2, to: Vector2) -> float:
	var delta := to - from
	var length_squared := delta.length_squared()
	if length_squared <= 0.0001:
		return pos.distance_to(from)
	var t := clampf((pos - from).dot(delta) / length_squared, 0.0, 1.0)
	return pos.distance_to(from + delta * t)


## Whether anything already placed is within [param spacing] of [param pos].
##
## Checked against every node rather than only same-kind ones, because two oaks
## overlapping is the same visual bug as an oak overlapping a boulder.
static func _too_close(field: ResourceField, pos: Vector2, spacing: float) -> bool:
	if spacing <= 0.0:
		return false
	for node: ResourceNode in field.nodes:
		var other := Vector2(node.position.x, node.position.z)
		if pos.distance_to(other) < spacing:
			return true
	return false


## Demo interactables.
##
## These exist to prove the reusable [Interactable] component works on unrelated
## props with no per-prop code: every row below is plain data consumed by the
## same helper. Real systems (crops, chests, NPCs, workstations) will attach
## their own subclasses instead.
static func _build_interactables(root: Node3D) -> void:
	var props: Array[Dictionary] = [
		# Placed on the spawn point's doorstep on purpose. The other three props
		# sit 26-44m away, which is fine as scenery but meant a new game opened
		# with nothing inside the 3.2m interaction range: no prompt, no
		# crosshair response, and nothing to indicate interaction worked at all.
		# The mailbox is the tutorial prop that makes the system visible.
		# Offset off the spawn's Z axis rather than dead ahead, so it never
		# blocks the straight-down-the-Z sightline the interaction fixtures
		# rely on.
		{
			"name": "FarmMailbox",
			"position": Vector3(1.8, 0, 12.0),
			"shape": "box",
			"size": Vector3(0.55, 1.1, 0.7),
			"color": COL_WOOD,
			"verb": "Check the mail",
			"description": "A bill from the seed merchant, and a hand-drawn map of the valley.",
			"hold_seconds": 0.0,
			"one_shot": false,
		},
		{
			"name": "VillageWell",
			"position": Vector3(30, 0, 4),
			"shape": "cylinder",
			"size": Vector3(1.1, 1.0, 1.1),
			"color": COL_ROCK,
			"verb": "Look into",
			"description": "The shaft goes down a long way. It is very cold down there.",
			"hold_seconds": 0.0,
			"one_shot": false,
		},
		{
			"name": "NoticeBoard",
			"position": Vector3(2, 0, -12),
			"shape": "box",
			"size": Vector3(1.3, 1.5, 0.14),
			"color": COL_WOOD,
			"verb": "Read",
			"description": "A hand-written note: 'Mind the pond after dark.'",
			"hold_seconds": 0.0,
			"one_shot": false,
		},
		{
			"name": "SupplyCrate",
			"position": Vector3(44, 0, 13),
			"shape": "box",
			"size": Vector3(1.0, 0.9, 1.0),
			"color": COL_FENCE,
			"verb": "Open",
			"description": "Straw, twine and a bent spade. Someone left it half-stocked.",
			# Held, not tapped: exercises the timed-interaction path.
			"hold_seconds": 0.8,
			"one_shot": true,
		},
	]
	for spec: Dictionary in props:
		_build_examine_prop(root, spec)


static func _build_examine_prop(root: Node3D, spec: Dictionary) -> void:
	var size: Vector3 = spec["size"]

	var body := StaticBody3D.new()
	body.name = spec["name"]
	body.position = spec["position"]
	body.collision_layer = 1

	var built := _prop_mesh_and_shape(spec["shape"], size)
	var mesh: Mesh = built[0]
	var shape: Shape3D = built[1]

	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	visual.material_override = WorldMaterials.for_color(spec["color"], 0.85)
	visual.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(visual)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	# The collider is deliberately taller than the mesh. A crosshair sits at
	# ~1.62m, so a genuinely short prop (a 0.9m crate) would be impossible to
	# aim at. Padding the height makes small props targetable at the cost of a
	# slightly larger blocking volume; a dedicated interaction-only collider on
	# its own layer is the cleaner long-term fix.
	var hit_height := maxf(size.y, INTERACTION_COLLIDER_MIN_HEIGHT)
	if shape is BoxShape3D:
		(shape as BoxShape3D).size = Vector3(size.x, hit_height, size.z)
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		cylinder.height = hit_height
	elif shape is SphereShape3D:
		var sphere := shape as SphereShape3D
		sphere.height = hit_height
		sphere.radius = hit_height * 0.5
	col.shape = shape
	col.position = Vector3(0, hit_height * 0.5, 0)
	body.add_child(col)

	# The component is a plain child of the body, so the probe's ray resolves
	# it by walking up from the collider it hit.
	var component := Interactable.new()
	component.name = "Interactable"
	component.set_script(load("res://scripts/interaction/examine_interactable.gd"))
	component.set("verb", spec["verb"])
	component.set("description", spec["description"])
	component.set("hold_seconds", spec["hold_seconds"])
	component.set("one_shot", spec["one_shot"])
	component.set("max_distance", 3.2)
	body.add_child(component)

	_finish(body, root)


## Builds a matching visual mesh and collision shape from one size description,
## so the two can never drift apart.
static func _prop_mesh_and_shape(kind: String, size: Vector3) -> Array:
	var mesh: Mesh
	var shape: Shape3D
	match kind:
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x
			cylinder.bottom_radius = size.x
			cylinder.height = size.y
			cylinder.radial_segments = 12
			var cylinder_shape := CylinderShape3D.new()
			cylinder_shape.radius = size.x
			cylinder_shape.height = size.y
			mesh = cylinder
			shape = cylinder_shape
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size.x
			sphere.height = size.y
			sphere.radial_segments = 10
			sphere.rings = 6
			var sphere_shape := SphereShape3D.new()
			sphere_shape.radius = size.x
			mesh = sphere
			shape = sphere_shape
		_:
			var box := BoxMesh.new()
			box.size = size
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			mesh = box
			shape = box_shape
	return [mesh, shape]


## Thin alias kept so the palette constants above remain the single source of truth
## for a colour, while the *surface* — its roughness, specular and detail tiling —
## comes from [WorldMaterials]. Call sites that care about the class ask for it by
## name; this is only for the ones that genuinely have an arbitrary colour.
static func material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	return WorldMaterials.for_color(color, roughness)


## The per-vertex tint for a point on the ground.
##
## ## Why this exists
##
## The ground is one flat mesh with one flat green, 220m across. Under any lighting
## that is a green table, and no amount of post-processing fixes it — SSAO finds edges
## that are not there, and bloom has nothing to bloom. Variation has to be in the
## surface data.
##
## Vertex colour rather than a second texture, because it costs nothing at runtime, has
## no resolution to choose, and cannot tile visibly.
##
## The tint multiplies the grass material's albedo, so it is authored as a *modulation*
## around white, not as a colour to replace it: white leaves the palette's grass alone,
## and the tints below only push it around.
##
## ## What it keys off, which is not "height"
##
## The first version ramped on elevation, because "dry grass up high, lush down low" is
## the reflex. [method terrain_height] is 0.0 everywhere outside [constant POND_RADIUS]
## and negative inside it, so that term evaluated to zero at all 2025 vertices: a
## gradient that exists in the code and cannot be seen in the world, which is worse than
## not writing it. The terrain has exactly one landform and the tint is now written
## against that one landform.
static func ground_tint(x: float, z: float, height: float) -> Color:
	var tint := Color(1, 1, 1)
	var pos := Vector2(x, z)
	var to_pond := pos.distance_to(REGION_POND)

	# The pond basin, below the waterline: dark silt. Above it, wet sand. The blend
	# runs over the 2m the slope actually spans, which is wide enough to read as a
	# beach rather than as a band.
	if to_pond < POND_RADIUS:
		var submerged := clampf(inverse_lerp(WATER_LEVEL, POND_FLOOR_DEPTH, height), 0.0, 1.0)
		tint = tint.lerp(Color(0.62, 0.56, 0.44), 0.55)
		tint = tint.lerp(Color(0.44, 0.42, 0.34), submerged * 0.6)
	else:
		# Damp margin just outside the rim, so the shoreline is a gradient into the
		# water rather than a hard green-to-blue edge.
		var damp := clampf(inverse_lerp(POND_RADIUS * 2.4, POND_RADIUS, to_pond), 0.0, 1.0)
		tint = tint.lerp(Color(0.74, 0.80, 0.66), damp * 0.6)

	# A broad, slow blotch so the field is not uniform even where nothing else reaches.
	# Two out-of-phase sines rather than a noise lookup: it is evaluated 2025 times at
	# world build and must not be the most expensive thing in it.
	var blotch := sin(x * 0.11) * cos(z * 0.09) + sin(x * 0.047 + z * 0.031) * 0.6
	tint = tint.lerp(Color(1.10, 1.12, 0.94), clampf(blotch * 0.16 + 0.16, 0.0, 0.34))

	# Trampled earth around the farm and the shop, where the player actually walks.
	tint = tint.lerp(Color(1.10, 0.98, 0.84), _worn_ground(pos) * 0.5)
	return tint


## How worn the ground is at a point: 1 at the middle of a path, 0 well away from one.
static func _worn_ground(pos: Vector2) -> float:
	var worst := 0.0
	for centre: Vector2 in [REGION_FARM, REGION_VILLAGE]:
		worst = maxf(worst, 1.0 - clampf(pos.distance_to(centre) / 16.0, 0.0, 1.0))
	# The road between the two.
	var road := REGION_VILLAGE - REGION_FARM
	var along := clampf((pos - REGION_FARM).dot(road) / road.length_squared(), 0.0, 1.0)
	worst = maxf(worst, 1.0 - clampf(pos.distance_to(REGION_FARM + road * along) / 7.0, 0.0, 1.0))
	return worst


## Parents a node and marks it for serialisation.
## `owner` must already be an ancestor, so add_child has to happen first.
static func _finish(node: Node, root: Node3D) -> void:
	root.add_child(node)
	node.owner = root