class_name PlayerController
extends CharacterBody3D
## Player locomotion, look control, and camera-mode ownership.
##
## Structure: **two** yaws, not one.
##
##   * [member _look_yaw] is the aim direction. Only mouse and gamepad input
##     ever write it.
##   * [member _facing_yaw] is which way the character's mesh points. Movement
##     turns it toward the direction of travel, and it relaxes back to the aim
##     direction when the player stops.
##
## The camera rig is a child of the body, so it counter-rotates by
## `look - facing` to keep the *camera* on the aim yaw regardless of which way
## the body is turned.
##
## Why two: with a single yaw the input basis and the rotation being written
## are the same value, which is a feedback loop. Moving right rotates the body
## right, which rotates the basis that interprets "right", which rotates the
## body further right. Holding W+D accelerated the spin to about 9 degrees per
## frame and the player circled forever, unable to walk in a straight line.
## Input is now read in the *aim* basis, which nothing but the mouse writes, so
## the loop cannot close.
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

## Aim yaw. Written only by [method _handle_look] and
## [method _handle_gamepad_look]; read by the movement basis and by
## [method get_yaw]. Never written from the movement code, which is what keeps
## the feedback loop closed.
var _look_yaw: float = 0.0
## Which way the body mesh points. Chased toward the direction of travel while
## moving, and eased back to [member _look_yaw] when idle.
var _facing_yaw: float = 0.0
var _pitch: float = 0.0
var _move_mode: PlayerMotion.MoveMode = PlayerMotion.MoveMode.WALK
var _was_on_floor := false
var _gravity: float = 24.0
var _cursor_was_captured := false
var _sensitivity: float = 0.003
## Radians per second the body turns toward its direction of travel.
const FACING_TURN_SPEED := 14.0
## Radians per second the body returns to the aim direction when idle. Slower
## than the turn, so a tap of A does not visibly snap the model back.
const FACING_RELAX_SPEED := 6.0


func _ready() -> void:
	# PAUSABLE, stated explicitly and not left at INHERIT.
	#
	# `Main` is PROCESS_MODE_ALWAYS so it can keep handling input while the game is
	# paused. Godot resolves INHERIT by walking up to the nearest ancestor that
	# sets a mode, so a player left on the default inherits ALWAYS — and the player
	# walks straight out of an open shop. The shop panel pauses the tree expecting
	# that to stop the body, and the tree pause changes nothing for anything under
	# an ALWAYS root.
	#
	# The spawn point cannot set this instead: the player is built by a generator
	# and instantiated, and a mode set in `_ready` is inherited by the probe, the
	# camera rig and every child the player will ever grow.
	process_mode = Node.PROCESS_MODE_PAUSABLE
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

	# Interpreted in the *aim* basis, not the body's. Using `global_transform`
	# here was the feedback loop: the basis carries the rotation that
	# `_update_facing` writes, so every frame re-read the input through a
	# heading that had already turned toward it.
	var wish := PlayerMotion.wish_direction(input_vector, _aim_basis())

	_move_mode = _resolve_move_mode(wish.length_squared() > 0.0)
	var speed := PlayerMotion.target_speed_for(_move_mode, movement_config)
	var accel := movement_config.ground_acceleration
	var decel := movement_config.ground_deceleration
	if not is_on_floor():
		accel = movement_config.air_acceleration
		decel = movement_config.air_acceleration

	_update_facing(wish, delta)

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


## Yaw-only basis for interpreting movement input.
##
## Deliberately not `global_transform.basis`: the body rotates toward its
## direction of travel, so feeding that rotation back into the input would make
## strafing steer the strafe.
func _aim_basis() -> Basis:
	return Basis(Vector3.UP, _look_yaw)


## Points the body mesh at the direction of travel, then relaxes back to the
## aim direction once the player stops.
##
## The mesh facing and the camera aim are deliberately allowed to differ: a
## character can back away from where they are looking, and in third person the
## rig counter-rotates so the view still follows the mouse.
func _update_facing(wish: Vector3, delta: float) -> void:
	if wish.length_squared() > 0.000001:
		# Forward is -Z, hence the negated components.
		var target := atan2(-wish.x, -wish.z)
		_facing_yaw = PlayerMotion.damp_angle(_facing_yaw, target, FACING_TURN_SPEED, delta)
	else:
		_facing_yaw = PlayerMotion.damp_angle(_facing_yaw, _look_yaw, FACING_RELAX_SPEED, delta)
	rotation.y = _facing_yaw
	if camera_rig != null:
		# Cancel the body's yaw so the camera inherits the aim heading.
		camera_rig.rotation.y = _look_yaw - _facing_yaw


func _handle_look(relative: Vector2) -> void:
	# Config sensitivity wins when set; it is the user-facing slider.
	var invert := 1.0 if Config.invert_vertical() else -1.0
	_look_yaw = wrapf(_look_yaw - relative.x * _sensitivity, -PI, PI)
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
	_look_yaw = wrapf(_look_yaw - stick.x * rate * delta * (1.0 - smoothing), -PI, PI)
	var invert := 1.0 if Config.invert_vertical() else -1.0
	_pitch = PlayerMotion.apply_pitch(_pitch, -stick.y * rate * delta * (1.0 - smoothing) * invert, movement_config)
	_apply_rotation()


func _apply_rotation() -> void:
	# Looking around turns the aim, and the body follows the aim only when the
	# player is not steering somewhere else. Written here rather than left to
	# `_update_facing` so a mouse move is reflected on the same frame, before the
	# next physics tick.
	if _facing_yaw == _look_yaw or wish_is_idle():
		_facing_yaw = _look_yaw
	rotation.y = _facing_yaw
	if camera_rig != null:
		camera_rig.rotation.y = _look_yaw - _facing_yaw
		camera_rig.set_pitch(_pitch)


## True when no movement key is held, used by [method _apply_rotation] to decide
## whether the body should be slaved to the aim yaw.
func wish_is_idle() -> bool:
	var still := not Input.is_action_pressed(InputActions.MOVE_FORWARD)
	still = still and not Input.is_action_pressed(InputActions.MOVE_BACK)
	still = still and not Input.is_action_pressed(InputActions.MOVE_LEFT)
	still = still and not Input.is_action_pressed(InputActions.MOVE_RIGHT)
	return still


func get_pitch() -> float:
	return _pitch


## Sets the aim yaw directly, snapping the body to match.
##
## Exists so tests and tools can aim the player without synthesising mouse
## motion. Writing `rotation.y` instead does not work: `_update_facing`
## overwrites it from [member _facing_yaw] on the next physics tick.
func set_yaw(value: float) -> void:
	_look_yaw = wrapf(value, -PI, PI)
	_facing_yaw = _look_yaw
	rotation.y = _facing_yaw
	if camera_rig != null:
		camera_rig.rotation.y = 0.0


## Aim yaw: the direction the player is looking. This is what the camera and
## the movement basis follow.
func get_yaw() -> float:
	return _look_yaw


## Body yaw: which way the character mesh points. Differs from [method get_yaw]
## while strafing or backing away.
func get_facing_yaw() -> float:
	return _facing_yaw


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