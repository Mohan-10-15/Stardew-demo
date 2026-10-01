class_name PlayerController
extends CharacterBody3D
## Player locomotion, look control, and camera-mode ownership.
##
## Structure: the *body* owns yaw (horizontal rotation) and the *camera rig*
## owns pitch. Splitting them this way means third-person yaw follows the
## character's facing instead of sliding sideways, which is the usual source of
## "camera feels wrong" in third-person games.
##
## All physics runs in `_physics_process`. Look smoothing runs in `_process`
## only for gamepad input, which is per-frame rather than per-tick.

signal jumped()
signal landed()
signal movement_mode_changed(mode: PlayerMotion.MoveMode)

const DEFAULT_MOVEMENT_CONFIG := "res://resources/config/movement_config.tres"

@export var movement_config: MovementConfig
@export var capture_mouse_on_ready: bool = true

## Assigned by the camera rig; exposed so tests and tools can drive the camera.
var camera_rig: CameraRig = null

var _yaw: float = 0.0
var _pitch: float = 0.0
var _move_mode: PlayerMotion.MoveMode = PlayerMotion.MoveMode.WALK
var _was_on_floor := false
var _gravity: float = 24.0
var _cursor_was_captured := false
var _sensitivity: float = 0.003


func _ready() -> void:
	if movement_config == null:
		movement_config = _load_default_config()
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)
	_was_on_floor = is_on_floor()


func _load_default_config() -> MovementConfig:
	if ResourceLoader.exists(DEFAULT_MOVEMENT_CONFIG):
		var res := load(DEFAULT_MOVEMENT_CONFIG) as MovementConfig
		if res != null:
			return res
	Log.warn("PlayerController", "No movement config resource; using built-in defaults")
	return MovementConfig.new()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_look(event.relative)


func _process(delta: float) -> void:
	_handle_gamepad_look(delta)


func _physics_process(delta: float) -> void:
	if get_multiplayer_authority() != 1:
		return

	_sensitivity = Config.get_mouse_sensitivity()
	if _sensitivity <= 0.0:
		_sensitivity = movement_config.mouse_sensitivity

	var input_vector := Input.get_vector(
		InputActions.MOVE_LEFT,
		InputActions.MOVE_RIGHT,
		InputActions.MOVE_FORWARD,
		InputActions.MOVE_BACK
	)

	var wish := PlayerMotion.wish_direction(input_vector, global_transform.basis)

	_move_mode = _resolve_move_mode(wish.length_squared() > 0.0)
	var speed := PlayerMotion.target_speed_for(_move_mode, movement_config)
	var accel := movement_config.ground_acceleration
	var decel := movement_config.ground_deceleration
	if not is_on_floor():
		accel = movement_config.air_acceleration
		decel = movement_config.air_acceleration

	# Rotate the body to the movement direction so third-person cameras trail
	# behind the character rather than orbiting a fixed heading.
	if wish.length_squared() > 0.000001:
		_face_direction(wish, delta)

	velocity = PlayerMotion.accelerate(velocity, wish, speed, accel, decel, delta)

	if Input.is_action_just_pressed(InputActions.JUMP) and is_on_floor():
		velocity.y = movement_config.jump_velocity
		jumped.emit()
	elif Input.is_action_just_released(InputActions.JUMP) and velocity.y > 0.0:
		# Cutting the jump short on release is what makes jumps feel responsive.
		velocity.y *= movement_config.jump_hold_factor

	velocity = PlayerMotion.apply_gravity(
		velocity, movement_config, _gravity, delta,
		Input.is_action_pressed(InputActions.JUMP)
	)

	move_and_slide()
	_handle_floor_transitions()


func _resolve_move_mode(is_moving: bool) -> PlayerMotion.MoveMode:
	if Input.is_action_pressed(InputActions.CROUCH):
		var mode := PlayerMotion.MoveMode.CROUCH
		if mode != _move_mode:
			_set_move_mode(mode)
		return mode
	if not is_on_floor():
		var mode := PlayerMotion.MoveMode.AIR
		if mode != _move_mode:
			_set_move_mode(mode)
		return mode
	if Input.is_action_pressed(InputActions.SPRINT) and is_moving:
		var mode := PlayerMotion.MoveMode.SPRINT
		if mode != _move_mode:
			_set_move_mode(mode)
		return mode
	if _move_mode != PlayerMotion.MoveMode.WALK:
		_set_move_mode(PlayerMotion.MoveMode.WALK)
	return PlayerMotion.MoveMode.WALK


func _set_move_mode(mode: PlayerMotion.MoveMode) -> void:
	_move_mode = mode
	movement_mode_changed.emit(mode)


func _handle_floor_transitions() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit()
	_was_on_floor = on_floor


func _face_direction(wish: Vector3, delta: float) -> void:
	var target_yaw := atan2(-wish.x, -wish.z)
	_yaw = PlayerMotion.damp_angle(_yaw, target_yaw, 14.0, delta)
	rotation.y = _yaw


func _handle_look(relative: Vector2) -> void:
	# Config sensitivity wins when set; it is the user-facing slider.
	var invert := 1.0 if Config.invert_vertical() else -1.0
	_yaw = wrapf(_yaw - relative.x * _sensitivity, -PI, PI)
	_pitch = PlayerMotion.apply_pitch(_pitch, relative.y * _sensitivity * invert, movement_config)
	_apply_rotation()


func _handle_gamepad_look(delta: float) -> void:
	# Gamepad sticks are analog, so they need a rate plus deadzone, not a
	# per-event delta. Reuses move_left/right and forward/back axes.
	var stick := Input.get_vector(
		InputActions.LOOK_LEFT, InputActions.LOOK_RIGHT,
		InputActions.LOOK_UP, InputActions.LOOK_DOWN
	)
	if stick.length_squared() < 0.0001:
		return
	var rate := movement_config.gamepad_sensitivity
	var smoothing := movement_config.gamepad_look_smoothing
	_yaw = wrapf(_yaw - stick.x * rate * delta * (1.0 - smoothing), -PI, PI)
	var invert := 1.0 if Config.invert_vertical() else -1.0
	_pitch = PlayerMotion.apply_pitch(_pitch, -stick.y * rate * delta * (1.0 - smoothing) * invert, movement_config)
	_apply_rotation()


func _apply_rotation() -> void:
	rotation.y = _yaw
	if camera_rig != null:
		camera_rig.set_pitch(_pitch)


func get_pitch() -> float:
	return _pitch


func get_yaw() -> float:
	return _yaw


func toggle_camera_mode() -> void:
	if camera_rig != null:
		camera_rig.toggle_mode()


func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	_cursor_was_captured = captured


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and capture_mouse_on_ready:
		set_mouse_captured(true)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE