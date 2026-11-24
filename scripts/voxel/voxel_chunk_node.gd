class_name VoxelChunkNode
extends Node3D
## Draws one chunk from the pure mesher and gives it player-only-safe solid
## collision from the same triangles (D4's single-source-of-truth rule).
## Rebuilds are driven by VoxelService; nothing here decides gameplay.

@export var coord: Vector3i = Vector3i.ZERO
@export var texture_pack: String = "hollowbrook_detailed"

var _mesh: MeshInstance3D = null
var _body: StaticBody3D = null
var _shape: CollisionShape3D = null
var _material: StandardMaterial3D = null

static var _cache: Dictionary = {}


func setup(chunk_coord: Vector3i) -> void:
	coord = chunk_coord
	_material = _material_for(texture_pack)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.material_override = _material
	add_child(_mesh)
	_body = StaticBody3D.new()
	_body.name = "Solid"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	_shape = CollisionShape3D.new()
	_shape.name = "CollisionShape3D"
	_body.add_child(_shape)
	add_child(_body)


func set_texture_pack(pack: String) -> void:
	if pack == texture_pack:
		return
	texture_pack = pack
	if _mesh != null:
		_mesh.material_override = _material_for(pack)


func rebuild(grid: VoxelGrid) -> void:
	if _mesh == null:
		setup(coord)
	var report := VoxelMesher.build(grid, coord)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = report["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = report["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = report["uvs"]
	arrays[Mesh.ARRAY_COLOR] = report["colors"]
	arrays[Mesh.ARRAY_INDEX] = report["indices"]
	var mesh := ArrayMesh.new()
	if (report["vertices"] as PackedVector3Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = mesh
	# Concave collision wants triangles in the opposite winding (D4a).
	var faces := PackedVector3Array()
	var vertices: PackedVector3Array = report["vertices"]
	var indices: PackedInt32Array = report["indices"]
	for i: int in range(0, indices.size(), 3):
		faces.append(vertices[indices[i + 2]])
		faces.append(vertices[indices[i + 1]])
		faces.append(vertices[indices[i]])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	_shape.shape = shape


static func _material_for(pack: String) -> StandardMaterial3D:
	if _cache.has(pack):
		return _cache[pack]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	var path := "res://assets/voxel/packs/%s/atlas.png" % pack
	if FileAccess.file_exists(path):
		var texture := ResourceLoader.load(path) as Texture2D
		if texture != null:
			mat.albedo_texture = texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_cache[pack] = mat
	return mat
