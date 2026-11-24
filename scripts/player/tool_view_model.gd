class_name ToolViewModel
extends Node3D
## Draws the held tool in front of the camera and swings it on every tool swing.
##
## The game is first-person by default, and until this existed a swing had an
## audio cue and a state change but nothing moving in the player's hands. The
## view model is deliberately a child of Camera3D: it inherits both pitch and
## yaw for free, so it stays put in view no matter where the player looks.
##
## Every tool is *data* elsewhere; this node only knows how to draw a given id.
## An unknown id draws nothing rather than a wrong tool, and a missing player
## state simply leaves the hands empty — art can never break gameplay here.

const REST_POSITION := Vector3(0.46, -0.40, -0.98)
const REST_ROTATION := Vector3(-0.18, -0.10, -0.22)

var _model: Node3D = null
var _current_id: StringName = &""
var _tween: Tween = null
var _sway: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	# W5.4: inertial sway from player motion. A player who disables juice gets
	# exactly zero sway, not a smaller one.
	if not Config.settings.head_bob:
		_sway = Vector2.ZERO
		return
	var player := _find_named(get_tree().get_root(), "Player")
	var target := Vector2.ZERO
	if player is CharacterBody3D:
		var v := (player as CharacterBody3D).velocity
		target = Vector2(clampf(v.x * 0.012, -0.05, 0.05),
			clampf(v.z * 0.012, -0.05, 0.05))
	_sway = Juice.view_sway(_sway, target, true, delta)
	position = REST_POSITION + Vector3(_sway.x, _sway.y, 0.0)


func _ready() -> void:
	position = REST_POSITION
	rotation = REST_ROTATION
	var bus := _bus()
	if bus != null:
		bus.hotbar_selection_changed.connect(_refresh)
		# The starter loadout is granted after the player scene is built, so the
		# first `_refresh()` sees an empty bag. Inventory changes are the other
		# moment the held item can appear without a slot being selected.
		bus.inventory_changed.connect(_refresh)
		bus.tool_swung.connect(_on_swing)
		bus.fishing_cast.connect(_on_cast)
		bus.camera_mode_changed.connect(_on_camera_mode)
	_refresh()
	# The rig may already be in third person before this node was built.
	var rig := get_parent()
	if rig != null and rig.has_method("is_first_person"):
		visible = bool(rig.call("is_first_person"))


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.hotbar_selection_changed.is_connected(_refresh):
		bus.hotbar_selection_changed.disconnect(_refresh)
	if bus.inventory_changed.is_connected(_refresh):
		bus.inventory_changed.disconnect(_refresh)
	if bus.tool_swung.is_connected(_on_swing):
		bus.tool_swung.disconnect(_on_swing)
	if bus.fishing_cast.is_connected(_on_cast):
		bus.fishing_cast.disconnect(_on_cast)
	if bus.camera_mode_changed.is_connected(_on_camera_mode):
		bus.camera_mode_changed.disconnect(_on_camera_mode)


func _on_camera_mode(mode: int) -> void:
	visible = mode == 0


func _on_cast() -> void:
	# Fishing needs no rod in the bag, so the rod is the one tool shown on
	# demand. It reverts to the held item on the next hotbar change or swing.
	_show(&"fishing_rod")
	_swing()


func _on_swing(item_id: StringName) -> void:
	var held := _held_id()
	var shown := item_id if item_id != &"" else held
	if shown != &"" and shown != _current_id:
		_show(shown)
	_swing()


func _refresh(_slot: int = 0) -> void:
	_show(_held_id())


func _held_id() -> StringName:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	if state == null:
		return &""
	var held: Dictionary = state.call("held_item_id")
	return StringName(held.get("id", &""))


func _show(id: StringName) -> void:
	if id == _current_id and _model != null:
		return
	if _model != null:
		_model.free()
		_model = null
	_current_id = id
	var model := _build_model(id)
	if model == null:
		return
	model.name = "HeldTool"
	model.scale = Vector3.ONE * 0.36
	_model = model
	add_child(model)


func _swing() -> void:
	if _model == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# The model is a child of this node, which already carries the rest pose.
	# Its own offsets therefore start and end at zero — returning it to the
	# parent's REST_ROTATION would tilt the tool twice and leave it skewed.
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_model, "rotation", Vector3(-0.85, 0.25, 0.55), 0.09)
	_tween.tween_property(_model, "position", Vector3(0, -0.14, 0.08), 0.09)
	_tween.tween_property(_model, "rotation", Vector3.ZERO, 0.20)
	_tween.tween_property(_model, "position", Vector3.ZERO, 0.20)


## A purpose-built mesh for each tool. Shapes are composed rather than a single
## primitive so a hoe reads as a hoe even without a held-prop model pack.
func _build_model(id: StringName) -> Node3D:
	var root := Node3D.new()
	var color := _color_for(id)
	match id:
		&"hoe":
			_part(root, "Handle", _cylinder(0.035, 0.9), Vector3(0, -0.08, 0), _wood())
			_part(root, "Blade", _box(Vector3(0.34, 0.10, 0.16)), Vector3(0.10, 0.36, 0), color)
		&"watering_can":
			_part(root, "Can", _cylinder(0.18, 0.34), Vector3(0, 0.05, 0), color)
			_part(root, "Spout", _cylinder(0.055, 0.46), Vector3(-0.24, 0.14, 0), color,
				Vector3(0, 0, 1.05))
			_part(root, "Handle", _cylinder(0.03, 0.3), Vector3(0.16, 0.32, 0), _wood())
		&"axe":
			_part(root, "Handle", _cylinder(0.04, 0.86), Vector3(0, -0.06, 0), _wood())
			_part(root, "Head", _box(Vector3(0.28, 0.20, 0.07)), Vector3(0.10, 0.34, 0), color)
		&"pickaxe":
			_part(root, "Handle", _cylinder(0.04, 0.86), Vector3(0, -0.06, 0), _wood())
			_part(root, "TipA", _box(Vector3(0.30, 0.06, 0.06)), Vector3(0.08, 0.34, 0), color,
				Vector3(0, 0, 0.28))
			_part(root, "TipB", _box(Vector3(0.30, 0.06, 0.06)), Vector3(0.08, 0.34, 0), color,
				Vector3(0, 0, -0.28))
		&"scythe":
			_part(root, "Handle", _cylinder(0.035, 1.0), Vector3(0, -0.1, 0), _wood())
			_part(root, "Blade", _box(Vector3(0.52, 0.06, 0.12)), Vector3(0.24, 0.38, 0), color,
				Vector3(0, 0, -0.18))
		&"fishing_rod":
			_part(root, "Rod", _cylinder(0.018, 1.25), Vector3(0, 0.05, 0), _wood())
			_part(root, "Reel", _cylinder(0.07, 0.08), Vector3(0, -0.06, 0.08), color)
			_part(root, "Line", _cylinder(0.004, 0.8), Vector3(0.02, -0.45, 0), Color(0.9, 0.9, 0.95))
		_:
			root.free()
			return null
	root.rotation = Vector3.ZERO
	return root


func _part(root: Node3D, name: String, mesh: Mesh, at: Vector3, color: Color,
		angles: Vector3 = Vector3.ZERO) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position = at
	node.rotation = angles
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	node.material_override = mat
	root.add_child(node)


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


func _wood() -> Color:
	return Color(0.46, 0.31, 0.18)


func _color_for(id: StringName) -> Color:
	var definition := ItemRegistry.get_item(id)
	if definition != null and definition.icon_color.a > 0.0:
		return definition.icon_color
	return Color(0.66, 0.68, 0.72)


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


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
