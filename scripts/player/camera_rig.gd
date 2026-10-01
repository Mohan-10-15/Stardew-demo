class_name CameraRig
extends Node3D
## Dual first/third-person camera rig.
##
## Design notes:
##   * The rig is a child of the player and handles **pitch only**. Yaw belongs
##     to the body (see [PlayerController]). This is what keeps a third-person
##     camera trailing behind the character instead of orbiting a fixed axis.
##   * Third-person uses an explicit ray query rather than SpringArm3D, so the
##     behaviour is deterministic and unit-testable without a live physics world.
##   * Switching modes never reparents or moves the player, so there is no
##     teleport and no frame of visual pop.
##
## `V` toggles the mode through [InputActions.TOGGLE_CAMERA_MODE].

enum Mode { FIRST_PERSON, THIRD_PERSON }

@export var mode: Mode = Mode.FIRST_PERSON
@export var fov: float = 78.0
@export var third_person_distance: float = 5.0
@export var min_third_person_distance: float = 0.6
## Distance kept between the camera and whatever it hits, so the near plane
## never clips through a wall.
@export var collision_padding: float = 0.35
## How quickly the camera pulls back in when something intrudes.
@export var occlusion_snap_speed: float = 30.0
## How slowly it eases back out when the path clears.
@export var occlusion_recover_speed: float = 6.0
## Reference height for the third-person pivot (roughly shoulder height).
@export var pivot_height: float = 1.55
## Camera height above the rig origin in first person (eye level).
@export var first_person_height: float = 1.62

var _pitch: float = 0.0
var _current_distance: float = 0.0
var _camera: Camera3D = null
var _player: PlayerController = null
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	_camera = get_node_or_null(^"Camera3D") as Camera3D
	_player = get_parent() as PlayerController

	if _camera == null:
		Log.error("CameraRig", "No child Camera3D found")
		return

	if _player != null:
		_player.camera_rig = self
		_discover_body_meshes()

	_apply_fov()
	# The rig is the single owner of the camera-mode toggle, so `main.gd` no
	# longer competes for the same action.
	EventBus.settings_applied.connect(_apply_fov)

	# Honour the player's saved preference rather than the scene default.
	mode = Mode.THIRD_PERSON if int(Config.settings.default_camera_mode) == 1 else Mode.FIRST_PERSON
	_apply_mode(mode, true)
	# Snap so the first frame is already correct rather than sliding in.
	_current_distance = third_person_distance
	_update_camera_transform(true)


func _unhandled_input(event: InputEvent) -> void:
	# Only discrete button presses may toggle. Accepting anything that merely
	# "is_action_pressed" lets axis drift or synthetic mouse motion at window
	# startup flip the camera on its own.
	if event.is_echo():
		return
	var is_button_press := event.is_pressed() and (
		event is InputEventKey
		or event is InputEventJoypadButton
		or event is InputEventMouseButton
	)
	if not is_button_press:
		return
	# Config lets the user rebind the switch key; default is `toggle_camera_mode`.
	if event.is_action_pressed(Config.settings.camera_switch_key_action):
		toggle_mode()
		get_viewport().set_input_as_handled()


func toggle_mode() -> void:
	set_mode(Mode.THIRD_PERSON if mode == Mode.FIRST_PERSON else Mode.FIRST_PERSON)


func set_mode(new_mode: Mode, instant: bool = false) -> void:
	if new_mode == mode and not instant:
		return
	mode = new_mode
	_apply_mode(mode, instant)
	EventBus.camera_mode_changed.emit(int(mode))
	Log.info("CameraRig", "Camera mode -> %s" % Mode.keys()[mode])


func get_mode() -> Mode:
	return mode


func is_first_person() -> bool:
	return mode == Mode.FIRST_PERSON


## Registers a mesh to hide while in first person, so the player does not see
## the inside of their own head. The body stays collidable either way.
func register_body_mesh(mesh: MeshInstance3D) -> void:
	if mesh != null and not _meshes.has(mesh):
		_meshes.append(mesh)


## Auto-discovers the player's visual meshes so the scene does not have to wire
## them up by hand. Anything under a node named `*_always_visible` is skipped.
func _discover_body_meshes() -> void:
	for child: Node in _player.get_children():
		if child is MeshInstance3D and not String(child.name).ends_with("_always_visible"):
			register_body_mesh(child as MeshInstance3D)


func set_pitch(value: float) -> void:
	_pitch = value
	rotation.x = _pitch


func get_camera() -> Camera3D:
	return _camera


func _apply_fov() -> void:
	if _camera == null:
		return
	var target := Config.get_fov() if Config.settings.fov > 0.0 else fov
	_camera.fov = target


func _apply_mode(_new_mode: Mode, instant: bool) -> void:
	if _camera == null:
		return
	var third_person := _new_mode == Mode.THIRD_PERSON
	_camera.current = true
	# The body is only visible in third person. Hiding it in first person avoids
	# the classic "camera inside a floating torso" artifact, and has no effect
	# on physics either way.
	for mesh: MeshInstance3D in _meshes:
		mesh.visible = third_person
	if instant:
		_current_distance = third_person_distance


func _physics_process(_delta: float) -> void:
	_update_camera_transform(false)


func _update_camera_transform(instant: bool) -> void:
	if _camera == null:
		return

	if mode == Mode.FIRST_PERSON:
		_current_distance = 0.0
		# Rig local space: the parent supplies yaw, the rig itself supplies
		# pitch, so the camera needs no rotation of its own.
		_camera.position = Vector3(0.0, first_person_height, 0.0)
		_camera.rotation = Vector3.ZERO
		return

	var pivot := global_position + Vector3.UP * pivot_height
	var forward := -global_transform.basis.z
	var unobstructed := _desired_distance(pivot, forward)

	var delta := maxf(get_physics_process_delta_time(), 0.0001)
	# Pull in immediately when blocked, ease back out when clear. The asymmetry
	# stops the camera drifting through a wall it failed to notice.
	var speed := occlusion_snap_speed if unobstructed < _current_distance else occlusion_recover_speed
	if instant:
		_current_distance = unobstructed
	else:
		_current_distance = PlayerMotion.damp(_current_distance, unobstructed, speed, delta)

	_current_distance = clampf(_current_distance, min_third_person_distance, third_person_distance)

	# Local +Z is behind the rig, which is where the camera belongs.
	_camera.position = Vector3(0.0, 0.0, _current_distance)
	_camera.rotation = Vector3.ZERO


## Casts a ray from the pivot along `-forward` and returns how far the camera
## may travel before it would hit something.
func _desired_distance(pivot: Vector3, forward: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return third_person_distance

	# Exclude the player's own body so the camera never collides with itself.
	var query := PhysicsRayQueryParameters3D.create(
		pivot, pivot - forward * (third_person_distance + collision_padding)
	)
	query.collision_mask = _world_mask()
	query.exclude = [_player_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return third_person_distance

	var travel: float = (pivot - hit["position"]).length()
	return maxf(travel - collision_padding, min_third_person_distance)


func _world_mask() -> int:
	# Layer 1 is "world" per the project's layer_names.
	return 1 << 0


func _player_rid() -> RID:
	return _player.get_rid() if _player != null else RID()