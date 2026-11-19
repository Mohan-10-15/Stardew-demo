extends TestSuite
## M17: every tool has a first-person view model, interactables react without
## touching their colliders, CC0 building art loads, and a bad asset degrades
## to composed geometry instead of crashing the game.

const VIEW_SCRIPT := "res://scripts/player/tool_view_model.gd"
const INTERACTABLE_SCRIPT := "res://scripts/interaction/interactable.gd"

const TOOLS: Array[StringName] = [
	&"hoe", &"watering_can", &"scythe", &"axe", &"pickaxe", &"fishing_rod",
]

var _rig: Node3D = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"every_tool_has_a_view_model", &"unknown_tools_draw_nothing",
		&"building_art_loads", &"a_missing_asset_falls_back",
		&"interactables_react_without_scaling_their_collider",
	]


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"every_tool_has_a_view_model":
			return await _t_tools()
		&"unknown_tools_draw_nothing":
			return _t_unknown()
		&"building_art_loads":
			return _t_buildings()
		&"a_missing_asset_falls_back":
			return _t_fallback()
		&"interactables_react_without_scaling_their_collider":
			return await _t_reaction()
	return fail(case, "no case implementation for %s" % case)


func _t_tools() -> Dictionary:
	var c := &"every_tool_has_a_view_model"
	var view: Node3D = (load(VIEW_SCRIPT) as GDScript).new()
	for id: StringName in TOOLS:
		var model: Node3D = view.call("_build_model", id)
		if model == null:
			view.free()
			return fail(c, "%s has no view model" % id)
		if model.get_child_count() < 1:
			view.free()
			return fail(c, "%s has an empty view model" % id)
		model.free()
	view.free()
	return succeeded(c, "%d tools draw a view model" % TOOLS.size())


func _t_unknown() -> Dictionary:
	var c := &"unknown_tools_draw_nothing"
	var view: Node3D = (load(VIEW_SCRIPT) as GDScript).new()
	var model: Node3D = view.call("_build_model", &"not_a_tool")
	var wrong := model != null
	if model != null:
		model.free()
	view.free()
	if wrong:
		return fail(c, "an unknown id still drew a tool")
	return succeeded(c, "an unknown id draws nothing rather than a wrong tool")


func _t_buildings() -> Dictionary:
	var c := &"building_art_loads"
	var definitions := BuildingService.all_buildings()
	if definitions.is_empty():
		return fail(c, "no buildings authored")
	for data: BuildingData in definitions:
		if String(data.model_path).is_empty():
			return fail(c, "%s has no CC0 model path" % data.id)
		if not ModelArt.can_load(data.model_path):
			return fail(c, "%s names an asset that will not load" % data.id)
	return succeeded(c, "%d buildings draw real CC0 models" % definitions.size())


func _t_fallback() -> Dictionary:
	var c := &"a_missing_asset_falls_back"
	var data := BuildingData.new()
	data.id = &"broken"
	data.display_name = "Broken"
	data.price = 1
	data.upgrade_price = 1
	data.effect_value = 1
	data.model_path = "res://assets/models/no_such_model.fbx"
	var fallback := BuildingService._fallback_visual(data)
	if fallback == null or fallback.get_child_count() < 2:
		return fail(c, "a bad asset produced no fallback geometry")
	fallback.free()
	return succeeded(c, "a missing model degrades to a roofed box")


func _t_reaction() -> Dictionary:
	var c := &"interactables_react_without_scaling_their_collider"
	_ensure_rig()
	var body := StaticBody3D.new()
	body.name = "Prop"
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	mesh.mesh = box
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var component: Node = (load(INTERACTABLE_SCRIPT) as GDScript).new()
	component.name = "Interactable"
	body.add_child(component)
	_rig.add_child(body)
	await _step(2)
	if not bool(component.call("interact", null)):
		return fail(c, "the prop refused a plain interaction")
	var tween: Variant = component.get("_reaction_tween")
	if tween == null or not (tween as Tween).is_valid():
		return fail(c, "using the prop produced no reaction animation")
	if not mesh.scale.is_equal_approx(Vector3.ONE) and mesh.scale.x > 1.2:
		return fail(c, "the reaction scaled the visual far beyond a pop")
	if not (shape.shape as BoxShape3D).size.is_equal_approx(Vector3(1, 1, 1)):
		return fail(c, "the reaction changed the collider")
	return succeeded(c, "the prop pops and its collider is untouched")


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "ArtTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
