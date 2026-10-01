class_name MovementConfig
extends Resource
## Tunable locomotion parameters for [PlayerController].
##
## Every number that affects how the player feels lives here, so balancing is a
## data change rather than a code change. Values are read once at `_ready` into
## the controller's runtime state; editing at runtime is possible but not
## persisted until Group 26 (Save/Load).

@export_group("Speeds")
## Units/second when walking.
@export var walk_speed: float = 4.0
## Units/second while sprinting.
@export var sprint_speed: float = 7.5
## Units/second while crouching.
@export var crouch_speed: float = 2.0
## Speed used when airborne (0 = no air control).
@export var air_speed: float = 1.2

@export_group("Acceleration")
## Units/second^2 applied while accelerating on the ground.
@export var ground_acceleration: float = 45.0
## Units/second^2 applied while decelerating on the ground.
@export var ground_deceleration: float = 60.0
## Units/second^2 applied in the air. Lower feels heavier.
@export var air_acceleration: float = 12.0

@export_group("Jumping")
## Upward impulse for a jump.
@export var jump_velocity: float = 8.0
## Fraction of `jump_velocity` applied while still holding jump.
@export var jump_hold_factor: float = 0.55
## Gravity multiplier while ascending with jump held.
@export var jump_hold_gravity_scale: float = 0.55
## Gravity multiplier when falling.
@export var fall_gravity_scale: float = 1.35
## Minimum downward speed, prevents slow floaty falls.
@export var terminal_velocity: float = 55.0

@export_group("Look")
## Radians of yaw/pitch per pixel of mouse movement. Overridden by
## `Config.settings.mouse_sensitivity` when that is non-zero.
@export var mouse_sensitivity: float = 0.003
## Gamepad look speed in radians/second.
@export var gamepad_sensitivity: float = 2.6
## Exponential smoothing factor for gamepad look, 0 = instant.
@export var gamepad_look_smoothing: float = 0.15
## Downward pitch clamp, degrees.
@export var min_pitch_degrees: float = -89.0
## Upward pitch clamp, degrees.
@export var max_pitch_degrees: float = 89.0

@export_group("Body")
## Collision capsule radius.
@export var capsule_radius: float = 0.4
## Collision capsule height (total, including the two hemispheres).
@export var capsule_height: float = 1.8
## Eye/head height used by the first-person camera.
@export var eye_height: float = 1.62
## Crouch eye height.
@export var crouch_eye_height: float = 0.95

@export_group("Safety")
## Downward speed below which a body is treated as grounded.
@export var snap_to_ground_speed: float = 1.0
## Extra distance probed when snapping to ground, prevents bouncing down slopes.
@export var ground_snap_distance: float = 0.4


## Returns a copy so callers cannot mutate the shared resource.
func clone() -> MovementConfig:
	return duplicate(true) as MovementConfig