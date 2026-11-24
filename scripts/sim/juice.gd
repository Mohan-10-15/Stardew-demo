class_name Juice
extends RefCounted
## W5.4: game feel as pure math, with an off-switch for every effect. Nothing
## here touches the scene tree, so a test can assert that a player who disables
## shake or bob gets exactly zero added motion.

const HIT_STOP_MIN := 0.06
const HIT_STOP_MAX := 0.09
const TRAUMA_DECAY := 1.8
const FOV_KICK := 6.0
const BOB_AMPLITUDE := 0.035
const SWAY_INERTIA := 0.12


static func shake_from_trauma(trauma: float, intensity: float) -> float:
	if intensity <= 0.0:
		return 0.0
	return trauma * trauma * intensity


static func decay_trauma(trauma: float, delta: float) -> float:
	return maxf(trauma - TRAUMA_DECAY * delta, 0.0)


static func hit_stop_seconds(strength: float, enabled: bool) -> float:
	if not enabled:
		return 0.0
	return lerpf(HIT_STOP_MIN, HIT_STOP_MAX, clampf(strength, 0.0, 1.0))


static func sprint_fov(base_fov: float, speed_ratio: float) -> float:
	return base_fov + FOV_KICK * clampf(speed_ratio, 0.0, 1.0)


static func bob_offset(phase: float, enabled: bool) -> float:
	if not enabled:
		return 0.0
	return sin(phase) * BOB_AMPLITUDE


static func view_sway(current: Vector2, target: Vector2, enabled: bool,
		delta: float) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var t := clampf(delta / maxf(SWAY_INERTIA, 0.001), 0.0, 1.0)
	return current.lerp(target, t)
