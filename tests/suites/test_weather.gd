extends TestSuite
## M9: winter ends crops, and seasons repaint the world. Rain/save/announce are
## covered in test_time.gd and not duplicated here.

const FARM_SCRIPT := "res://scripts/farming/farm_service.gd"
const GRID_SCRIPT := "res://scripts/farming/farm_grid.gd"
const TIME_SCRIPT := "res://scripts/time/time_service.gd"
const VISUALS_SCRIPT := "res://scripts/world/season_visuals.gd"

var _rig: Node3D = null
var _withered: Array[StringName] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [&"winter_withers_out_of_season_crops", &"the_seasons_repaint_the_world"]


func setup() -> void:
	_rig = null
	_withered = []


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"winter_withers_out_of_season_crops":
			return await _t_wither()
		&"the_seasons_repaint_the_world":
			return await _t_visuals()
	return fail(case, "no case implementation for %s" % case)


func _t_wither() -> Dictionary:
	var c := &"winter_withers_out_of_season_crops"
	await _build_farm()
	var clock: Node = _rig.get_node(^"TimeService")
	var grid: FarmGrid = _rig.get_node(^"Grid") as FarmGrid
	var farm: Node = _rig.get_node(^"Farm")
	var tile: SoilTile = grid.get_tile(Vector2i(0, 0))
	tile.till()
	if not tile.plant(&"parsnip"):
		return fail(c, "could not plant a parsnip for the setup")
	_watch()
	clock.time.season = WorldTime.Season.WINTER
	autoload(&"EventBus").emit_signal(&"day_started", 60)
	if _withered.size() != 1 or _withered[0] != &"parsnip":
		return fail(c, "%d wither events: %s" % [_withered.size(), str(_withered)])
	if not String(tile.crop_id).is_empty():
		return fail(c, "the dead crop is still in the ground")
	_stop_watch()
	return succeeded(c, "winter killed the parsnip with one distinct event")


func _t_visuals() -> Dictionary:
	var c := &"the_seasons_repaint_the_world"
	_reset_rig()
	var visuals_script := load(VISUALS_SCRIPT) as GDScript
	if visuals_script == null:
		return fail(c, "no season visuals script")
	_ensure_rig()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky.sky_material = sky_material
	environment.sky = sky
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = environment
	_rig.add_child(world_env)
	var visuals: Node = visuals_script.new()
	visuals.name = "SeasonVisuals"
	_rig.add_child(visuals)
	var spring := WorldMaterials.surface(&"grass").albedo_color
	var ground := _find_named(_rig, "GroundMesh") as MeshInstance3D
	var before_color := Color(0, 0, 0)
	if ground != null and ground.mesh is ArrayMesh:
		var arrays := (ground.mesh as ArrayMesh).surface_get_arrays(0)
		if arrays.size() > Mesh.ARRAY_COLOR:
			before_color = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	autoload(&"EventBus").emit_signal(&"season_changed", WorldTime.Season.WINTER)
	var winter := WorldMaterials.surface(&"grass").albedo_color
	var after_color := Color(0, 0, 0)
	if ground != null and ground.mesh is ArrayMesh:
		var arrays := (ground.mesh as ArrayMesh).surface_get_arrays(0)
		if arrays.size() > Mesh.ARRAY_COLOR:
			after_color = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	if spring.is_equal_approx(winter):
		return fail(c, "winter did not change the grass colour")
	if sky_material.sky_top_color.is_equal_approx(Color(0.30, 0.53, 0.78)):
		return fail(c, "winter did not change the sky")
	if ground != null and before_color.is_equal_approx(after_color):
		return fail(c, "winter did not retint the ground vertices")
	return succeeded(c, "season_changed repainted grass and sky")


func _build_farm() -> void:
	_reset_rig()
	var farm_script := load(FARM_SCRIPT) as GDScript
	var grid_script := load(GRID_SCRIPT) as GDScript
	var time_script := load(TIME_SCRIPT) as GDScript
	_ensure_rig()
	var clock: Node = time_script.new()
	clock.name = "TimeService"
	clock.running = false
	clock.time.season = WorldTime.Season.SPRING
	_rig.add_child(clock)
	var grid: Node = grid_script.new()
	grid.name = "Grid"
	grid.set("columns", 3)
	grid.set("rows", 3)
	_rig.add_child(grid)
	var farm: Node = farm_script.new()
	farm.name = "Farm"
	farm.set("grid", grid)
	_rig.add_child(farm)
	await _step(2)


func _watch() -> void:
	var bus := autoload(&"EventBus")
	bus.connect(&"crop_withered", _on_withered)
	_withered = []


func _on_withered(_tile: Vector2i, crop_id: StringName) -> void:
	_withered.append(crop_id)


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus != null and bus.is_connected(&"crop_withered", _on_withered):
		bus.disconnect(&"crop_withered", _on_withered)


func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "WeatherTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
