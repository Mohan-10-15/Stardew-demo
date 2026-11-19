class_name CloudField
extends Node3D
## A handful of soft, flattened cloud clusters that drift across the sky.
##
## Godot's ProceduralSkyMaterial paints a clean gradient but no clouds, and a
## clean gradient makes a bright stylised valley feel empty. These are ordinary
## primitive meshes on the shared material library — no new asset, no texture,
## and they inherit the library's detail map like every other primitive. They
## cast no shadows: a cloud shadow moving across the farm would read as a
## lighting bug rather than as weather.

const CLOUD_COUNT := 14
const AREA := 150.0
const HEIGHT_MIN := 28.0
const HEIGHT_MAX := 46.0
const DRIFT_SPEED := 0.55

var _clouds: Array[Node3D] = []


func build(seed_value: int) -> void:
	for child: Node in get_children():
		child.free()
	_clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in range(CLOUD_COUNT):
		var cluster := Node3D.new()
		cluster.name = "Cloud%d" % i
		cluster.position = Vector3(
			rng.randf_range(-AREA, AREA),
			rng.randf_range(HEIGHT_MIN, HEIGHT_MAX),
			rng.randf_range(-AREA, AREA)
		)
		var puffs := rng.randi_range(3, 5)
		for p: int in range(puffs):
			var mesh := MeshInstance3D.new()
			mesh.name = "Puff%d" % p
			var sphere := SphereMesh.new()
			var radius := rng.randf_range(2.2, 4.0)
			sphere.radius = radius
			sphere.height = radius * 0.85
			sphere.rings = 8
			sphere.radial_segments = 12
			mesh.mesh = sphere
			mesh.position = Vector3(
				rng.randf_range(-3.5, 3.5), rng.randf_range(-0.4, 0.4),
				rng.randf_range(-1.5, 1.5)
			)
			mesh.scale = Vector3(rng.randf_range(1.2, 1.8), 0.8, 1.0)
			mesh.material_override = WorldMaterials.surface(&"cloud")
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cluster.add_child(mesh)
		add_child(cluster)
		_clouds.append(cluster)


func _process(delta: float) -> void:
	for cloud: Node3D in _clouds:
		cloud.position.x += DRIFT_SPEED * delta
		if cloud.position.x > AREA:
			cloud.position.x = -AREA
