class_name SeasonVisuals
extends Node
## Seasons change the world, not just the calendar. One listener that retints
## the shared grass material and the sky, and restores nothing on exit because
## the material belongs to the world being unloaded.

const GRASS_COLORS: Array[Color] = [
	Color(0.30, 0.56, 0.25),  # spring
	Color(0.24, 0.50, 0.20),  # summer
	Color(0.55, 0.48, 0.22),  # fall
	Color(0.72, 0.76, 0.78),  # winter
]
const SKY_TOP: Array[Color] = [
	Color(0.30, 0.53, 0.78),
	Color(0.26, 0.50, 0.80),
	Color(0.42, 0.48, 0.66),
	Color(0.62, 0.70, 0.82),
]
## Multipliers over the ground's authored vertex colours. The ground material
## uses vertex colour as albedo, so changing its albedo_color is invisible —
## the vertex colours themselves have to be retinted for a season to show.
const GROUND_TINT: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.78, 0.92, 0.72),
	Color(1.15, 0.95, 0.62),
	Color(1.35, 1.38, 1.42),
]

var _original_colors: PackedColorArray = PackedColorArray()
var _ground: MeshInstance3D = null


func _ready() -> void:
	EventBus.season_changed.connect(_on_season)
	var clock := TimeService.find_in_tree()
	if clock != null:
		_apply(int(clock.time.season))


func _exit_tree() -> void:
	if EventBus.season_changed.is_connected(_on_season):
		EventBus.season_changed.disconnect(_on_season)


func _on_season(season: int) -> void:
	_apply(season)


func _apply(season: int) -> void:
	var index := clampi(season, 0, 3)
	var grass := WorldMaterials.surface(&"grass")
	if grass != null:
		grass.albedo_color = GRASS_COLORS[index]
	_tint_ground(index)
	var world := _find_named(get_tree().get_root(), "WorldEnvironment")
	if world == null:
		return
	var environment: Environment = world.get("environment") as Environment
	if environment == null or environment.sky == null:
		return
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material != null:
		sky_material.sky_top_color = SKY_TOP[index]


func _tint_ground(index: int) -> void:
	if _ground == null:
		_ground = _find_named(get_tree().get_root(), "GroundMesh") as MeshInstance3D
	if _ground == null or not (_ground.mesh is ArrayMesh):
		return
	var mesh := _ground.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_COLOR or not (arrays[Mesh.ARRAY_COLOR] is PackedColorArray):
		return
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if _original_colors.is_empty():
		_original_colors = colors.duplicate()
	var tint := GROUND_TINT[index]
	var tinted := PackedColorArray()
	for i: int in range(_original_colors.size()):
		var base := _original_colors[i]
		tinted.append(Color(
			clampf(base.r * tint.r, 0.0, 2.0),
			clampf(base.g * tint.g, 0.0, 2.0),
			clampf(base.b * tint.b, 0.0, 2.0), base.a
		))
	arrays[Mesh.ARRAY_COLOR] = tinted
	# ArrayMesh has no in-place surface setter: rebuild from the same arrays,
	# including the index buffer. The MeshInstance keeps its material_override.
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
