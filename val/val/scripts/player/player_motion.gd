class_name PlayerMotion
extends RefCounted
## Pure locomotion math for [PlayerController].
##
## Extracted from the controller so the maths can be unit-tested headlessly,
## with no scene tree and no physics server. [PlayerController] is a thin shell
## that feeds this class real input and applies the result to the body.

enum MoveMode { WALK, SPRINT, CROUCH, AIR }


static func target_speed_for(mode: MoveMode, cfg: MovementConfig) -> float:
	match mode:
		MoveMode.SPRINT:
			return cfg.sprint_speed
		MoveMode.CROUCH:
			return cfg.crouch_speed
		MoveMode.AIR:
			return cfg.air_speed
		_:
			return cfg.walk_speed


## Builds a world-space wish direction from a 2D input vector.
## `y` maps to -Z so "forward" is the direction the body faces (-Z).
static func wish_direction(input_vector: Vector2, body_basis: Basis) -> Vector3:
	if input_vector.length_squared() < 0.000001:
		return Vector3.ZERO
	var flat := Vector3(input_vector.x, 0.0, input_vector.y)
	if flat.length_squared() > 1.0:
		flat = flat.normalized()
	return body_basis * flat


## Moves `velocity` toward `desired_direction * speed`, using separate
## acceleration and deceleration rates. This is what produces smooth
## start/stop rather than instant snapping.
static func accelerate(
	velocity: Vector3,
	desired_direction: Vector3,
	speed: float,
	acceleration: float,
	deceleration: float,
	delta: float
) -> Vector3:
	# Only the horizontal plane is integrated; gravity owns Y.
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var target := desired_direction * speed

	if desired_direction.length_squared() > 0.000001:
		flat_velocity = flat_velocity.move_toward(target, acceleration * delta)
	else:
		flat_velocity = flat_velocity.move_toward(Vector3.ZERO, deceleration * delta)

	return Vector3(flat_velocity.x, velocity.y, flat_velocity.z)


## Applies variable gravity. Holding jump near the apex extends the jump; a
## faster fall scale keeps the arc from feeling floaty.
static func apply_gravity(
	velocity: Vector3,
	cfg: MovementConfig,
	gravity: float,
	delta: float,
	jump_held: bool
) -> Vector3:
	var scale := cfg.fall_gravity_scale
	if velocity.y > 0.0:
		scale = cfg.jump_hold_gravity_scale if jump_held else 1.0

	var y := velocity.y - gravity * scale * delta
	return Vector3(velocity.x, maxf(y, -cfg.terminal_velocity), velocity.z)


## Clamps and smooths a pitch value in radians.
static func apply_pitch(current_pitch: float, delta_yaw: float, cfg: MovementConfig) -> float:
	var min_pitch := deg_to_rad(cfg.min_pitch_degrees)
	var max_pitch := deg_to_rad(cfg.max_pitch_degrees)
	return clampf(current_pitch + delta_yaw, min_pitch, max_pitch)


## Frame-rate independent exponential smoothing.
## `speed` is roughly "how many e-folds per second"; higher is snappier.
static func damp(current: float, target: float, speed: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-speed * delta))


## Shortest-arc exponential damping of an angle in radians. Interpolating a raw
## angle linearly is wrong across the ±PI seam, which shows up as a camera
## snapping the long way round when you turn past due north.
static func damp_angle(current: float, target: float, speed: float, delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	return wrapf(current + diff * (1.0 - exp(-speed * delta)), -PI, PI)