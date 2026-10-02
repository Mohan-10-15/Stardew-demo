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
const COL_LEAF := Color(0.22, 0.47, 0.24)
const COL_LEAF_AUTUMN := Color(0.72, 0.44, 0.18)
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
	_build_forest(root, rng)
	_build_rocks(root, rng)
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
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	_build_grid(vertices, normals, uvs, indices, faces)

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
	arrays[Mesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.material_override = material(COL_GRASS, 0.95)
	body.add_child(mesh)

	_finish(body, root)


## Fills a flat XZ grid of GROUND_CELLS cells, sampling [method terrain_height]
## for each vertex.
##
## Produces the vertex/normal/uv/index arrays for the visual mesh and a separate
## three-vertices-per-face list for the collider, both from this one pass.
static func _build_grid(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	faces: PackedVector3Array
) -> void:
	var step := GROUND_SIZE / float(GROUND_CELLS)
	var half := GROUND_SIZE * 0.5

	for gz: int in range(GROUND_CELLS + 1):
		for gx: int in range(GROUND_CELLS + 1):
			var x := -half + gx * step
			var z := -half + gz * step
			vertices.append(Vector3(x, terrain_height(x, z), z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(gx / float(GROUND_CELLS), gz / float(GROUND_CELLS)))

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
	var m := material(COL_WATER, 0.08)
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
	_add_path_segment(root, REGION_VILLAGE, REGION_FARM, 3.4)
	_add_path_segment(root, REGION_FARM, REGION_FOREST, 2.8)
	_add_path_segment(root, REGION_FARM, Vector2(REGION_FARM.x, REGION_POND.y - 12), 2.4)


static func _add_path_segment(root: Node3D, from: Vector2, to: Vector2, width: float) -> void:
	var mid := (from + to) * 0.5
	var delta := to - from
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, delta.length())
	mesh.mesh = plane
	mesh.material_override = material(COL_PATH, 0.9)
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
	soil.material_override = material(COL_DIRT, 0.95)
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
	canopy.material_override = material(COL_ROOF, 0.85)
	stall.add_child(canopy)

	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var pole := BoxMesh.new()
		pole.size = Vector3(0.12, 2.1, 0.12)
		leg.mesh = pole
		leg.position = Vector3(side * 1.1, 1.05, 0)
		leg.material_override = material(COL_WOOD, 0.9)
		stall.add_child(leg)

	var counter := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(2.2, 0.9, 0.8)
	counter.mesh = top
	counter.position = Vector3(0, 0.45, 0)
	counter.material_override = material(COL_WALL, 0.9)
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
	mesh.material_override = material(COL_FENCE, 0.9)
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
	mesh.material_override = material(COL_FENCE, 0.9)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var col := BoxShape3D.new()
	col.size = box.size
	shape.shape = col
	body.add_child(shape)

	_finish(body, root)


## Deterministic tree placement, shared by the visual multimeshes and the
## colliders. Two independent `rng.randf()` loops produce *different* layouts,
## so the player walks through invisible trees - one generator, one sequence.
static func _forest_sites(rng: RandomNumberGenerator) -> Array[Vector2]:
	var sites: Array[Vector2] = []
	for _i: int in range(46):
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * 30.0
		var pos := REGION_FOREST + Vector2(cos(angle), sin(angle)) * radius
		# Keep the forest from overlapping the farm, pond or village.
		if pos.distance_to(REGION_FARM) < 20.0:
			continue
		if pos.distance_to(REGION_POND) < 18.0:
			continue
		if pos.distance_to(REGION_VILLAGE) < 22.0:
			continue
		sites.append(pos)
	return sites


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
	walls.material_override = material(COL_WALL, 0.9)
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
	roof.material_override = material(COL_ROOF, 0.85)
	body.add_child(roof)

	# Door and windows, purely visual but they make the village feel inhabited.
	var door := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.0, 1.9, 0.12)
	door.mesh = door_box
	door.position = Vector3(0, 0.95, -depth * 0.5 - 0.06)
	door.material_override = material(Color(0.32, 0.22, 0.15), 0.9)
	body.add_child(door)

	for side: float in [-1.0, 1.0]:
		var window := MeshInstance3D.new()
		var win_box := BoxMesh.new()
		win_box.size = Vector3(0.1, 0.9, 0.9)
		window.mesh = win_box
		window.position = Vector3(side * (width * 0.5 + 0.05), 1.7, 0)
		window.material_override = material(Color(0.55, 0.72, 0.85), 0.4)
		body.add_child(window)

	_finish(body, root)


static func rng_rotate(centre: Vector2) -> float:
	# Deterministic per-position jitter so houses do not all face the same way.
	return sin(centre.x * 0.37 + centre.y * 0.21) * 0.18


static func _build_forest(root: Node3D, rng: RandomNumberGenerator) -> void:
	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []

	var sites := _forest_sites(rng)
	for pos: Vector2 in sites:
		trunks.append(_tree_transform(Vector3(pos.x, 0, pos.y), 1.0))
		canopies.append(_tree_transform(Vector3(pos.x, 0, pos.y), 1.0))

	_add_multimesh(root, "ForestTrunks", _trunk_mesh(), COL_WOOD, trunks)
	_add_multimesh(root, "ForestCanopies", _canopy_mesh(), COL_LEAF, canopies)
	# Canopies only; trunks get one StaticBody3D each further below.
	_add_tree_colliders(root, sites)
	# The positions actually used, so a test can verify the colliders sit on
	# the visible trees. MultiMesh instance transforms cannot be read back in a
	# headless run (the buffer lives on the GPU), so this is the only way to
	# assert visual/collision alignment without a renderer.
	root.set_meta(&"forest_sites", sites)


static func _tree_transform(at: Vector3, scale_v: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * scale_v), at)


static func _trunk_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.22
	m.bottom_radius = 0.32
	m.height = 2.6
	m.radial_segments = 6
	return m


static func _canopy_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.5
	m.height = 3.4
	m.radial_segments = 8
	m.rings = 4
	return m


## Colliders are placed from the *same* `sites` list the visual multimeshes use,
## so every visible tree is walkable-into and no invisible blocker exists.
static func _add_tree_colliders(root: Node3D, sites: Array[Vector2]) -> void:
	for pos: Vector2 in sites:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = Vector3(pos.x, 1.3, pos.y)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 2.6
		shape.shape = capsule
		body.add_child(shape)
		_finish(body, root)


static func _build_rocks(root: Node3D, rng: RandomNumberGenerator) -> void:
	for i: int in range(22):
		var pos := Vector2(
			rng.randf_range(-95.0, 95.0),
			rng.randf_range(-95.0, 95.0)
		)
		if pos.distance_to(REGION_FARM) < 16.0:
			continue
		if pos.distance_to(REGION_VILLAGE) < 18.0:
			continue

		var scale_v := rng.randf_range(0.4, 1.5)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = Vector3(pos.x, 0.0, pos.y)
		body.rotation.y = rng.randf() * TAU

		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.7 * scale_v
		sphere.height = 1.2 * scale_v
		sphere.radial_segments = 7
		sphere.rings = 4
		mesh.mesh = sphere
		mesh.position = Vector3(0, 0.5 * scale_v, 0)
		mesh.material_override = material(COL_ROCK, 0.9)
		body.add_child(mesh)

		var shape := CollisionShape3D.new()
		var col := SphereShape3D.new()
		col.radius = 0.7 * scale_v
		shape.shape = col
		shape.position = Vector3(0, 0.5 * scale_v, 0)
		body.add_child(shape)

		_finish(body, root)


static func _add_multimesh(
	root: Node3D, name: String, mesh: Mesh, color: Color, transforms: Array[Transform3D]
) -> void:
	if transforms.is_empty():
		return
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	mi.multimesh = mm
	mi.material_override = material(color, 0.9)
	_finish(mi, root)


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
	visual.material_override = material(spec["color"], 0.85)
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


static func material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	# Godot 4 renamed SpatialMaterial.specular to StandardMaterial3D.metallic_specular.
	m.metallic_specular = 0.2
	return m


## Parents a node and marks it for serialisation.
## `owner` must already be an ancestor, so add_child has to happen first.
static func _finish(node: Node, root: Node3D) -> void:
	root.add_child(node)
	node.owner = root