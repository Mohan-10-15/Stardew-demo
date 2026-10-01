extends TestSuite
## Group 1 — Player controller unit tests.
##
## [PlayerMotion] is deliberately free of node/physics dependencies so these
## run headlessly in milliseconds and pin down the exact behaviours that are
## easy to get subtly wrong: acceleration curves, fall speed, terminal velocity,
## angle wrap-around and input direction mapping.

var _cfg: MovementConfig


func setup() -> void:
	_cfg = MovementConfig.new()


func get_cases() -> Array[StringName]:
	return [
		&"speed_per_mode",
		&"sprint_is_faster_than_walk",
		&"crouch_is_slower_than_walk",
		&"air_is_slower_than_walk",
		&"zero_input_yields_zero_direction",
		&"forward_input_maps_to_minus_z",
		&"input_is_normalised_when_diagonal",
		&"yaw_rotates_the_wish_direction",
		&"acceleration_is_bounded_by_rate",
		&"acceleration_reaches_target_speed",
		&"deceleration_stops_the_body",
		&"deceleration_never_overshoots_into_reverse",
		&"gravity_increases_fall_speed",
		&"held_jump_reduces_gravity_while_rising",
		&"terminal_velocity_is_respected",
		&"pitch_is_clamped_to_configured_limits",
		&"damp_is_frame_rate_independent",
		&"damp_angle_takes_the_short_way",
		&"damp_angle_handles_the_seam",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"speed_per_mode":
			return check_equals(case,
				PlayerMotion.target_speed_for(PlayerMotion.MoveMode.WALK, _cfg),
				_cfg.walk_speed)
		&"sprint_is_faster_than_walk":
			return check_true(case,
				_cfg.sprint_speed > _cfg.walk_speed,
				"sprint %f should exceed walk %f" % [_cfg.sprint_speed, _cfg.walk_speed])
		&"crouch_is_slower_than_walk":
			return check_true(case, _cfg.crouch_speed < _cfg.walk_speed)
		&"air_is_slower_than_walk":
			return check_true(case, _cfg.air_speed < _cfg.walk_speed)
		&"zero_input_yields_zero_direction":
			return check_equals(case,
				PlayerMotion.wish_direction(Vector2.ZERO, Basis.IDENTITY), Vector3.ZERO)
		&"forward_input_maps_to_minus_z":
			# Input.get_vector(..., MOVE_FORWARD, MOVE_BACK) yields y = -1 for
			# forward, and forward must be -Z in Godot.
			var dir := PlayerMotion.wish_direction(Vector2(0, -1), Basis.IDENTITY)
			return check_true(case, dir.z < -0.99, "got %s" % str(dir))
		&"input_is_normalised_when_diagonal":
			var dir := PlayerMotion.wish_direction(Vector2(1, -1), Basis.IDENTITY)
			return check_approx(case, dir.length(), 1.0, 0.001)
		&"yaw_rotates_the_wish_direction":
			var yaw := deg_to_rad(90.0)
			var rotated := PlayerMotion.wish_direction(Vector2(0, -1), Basis.from_euler(Vector3(0, yaw, 0)))
			# Facing +Y yaw turns forward from -Z toward -X.
			return check_true(case, rotated.x < -0.99, "got %s" % str(rotated))
		&"acceleration_is_bounded_by_rate":
			var v := PlayerMotion.accelerate(
				Vector3.ZERO, Vector3.FORWARD, 10.0, 45.0, 60.0, 0.1)
			# 45 * 0.1 = 4.5 units of travel in one tick, no more.
			return check_approx(case, Vector2(v.x, v.z).length(), 4.5, 0.001)
		&"acceleration_reaches_target_speed":
			var v := Vector3.ZERO
			for _i: int in range(60):
				v = PlayerMotion.accelerate(v, Vector3.FORWARD, 4.0, 45.0, 60.0, 1.0 / 60.0)
			return check_approx(case, Vector2(v.x, v.z).length(), 4.0, 0.01)
		&"deceleration_stops_the_body":
			var v := Vector3(4.0, 0.0, 0.0)
			for _i: int in range(60):
				v = PlayerMotion.accelerate(v, Vector3.ZERO, 4.0, 45.0, 60.0, 1.0 / 60.0)
			return check_approx(case, Vector2(v.x, v.z).length(), 0.0, 0.001)
		&"deceleration_never_overshoots_into_reverse":
			# A naive lerp here is what produces the classic "body slides
			# backwards when you let go of the stick" bug.
			var v := Vector3(0.2, 0.0, 0.0)
			v = PlayerMotion.accelerate(v, Vector3.ZERO, 4.0, 45.0, 60.0, 1.0)
			return check_true(case, v.x >= 0.0, "velocity reversed to %f" % v.x)
		&"gravity_increases_fall_speed":
			var a := PlayerMotion.apply_gravity(Vector3(0, 0, 0), _cfg, 24.0, 0.1, false)
			var b := PlayerMotion.apply_gravity(Vector3(0, -1, 0), _cfg, 24.0, 0.1, false)
			return check_true(case, b.y < a.y, "gravity did not accelerate the fall")
		&"held_jump_reduces_gravity_while_rising":
			var released := PlayerMotion.apply_gravity(Vector3(0, 5, 0), _cfg, 24.0, 0.1, false)
			var held := PlayerMotion.apply_gravity(Vector3(0, 5, 0), _cfg, 24.0, 0.1, true)
			return check_true(case, held.y > released.y,
				"held=%f released=%f" % [held.y, released.y])
		&"terminal_velocity_is_respected":
			var v := Vector3(0, -1, 0)
			for _i: int in range(500):
				v = PlayerMotion.apply_gravity(v, _cfg, 24.0, 1.0 / 60.0, false)
			return check_approx(case, v.y, -_cfg.terminal_velocity, 0.001)
		&"pitch_is_clamped_to_configured_limits":
			var high := PlayerMotion.apply_pitch(0.0, 10.0, _cfg)
			var low := PlayerMotion.apply_pitch(0.0, -10.0, _cfg)
			return check_true(case,
				high <= deg_to_rad(_cfg.max_pitch_degrees) + 0.0001
					and low >= deg_to_rad(_cfg.min_pitch_degrees) - 0.0001,
				"high=%f low=%f" % [high, low])
		&"damp_is_frame_rate_independent":
			var half_step := PlayerMotion.damp(0.0, 1.0, 5.0, 1.0 / 120.0)
			var full_step := PlayerMotion.damp(0.0, 1.0, 5.0, 1.0 / 60.0)
			# Doubling the timestep must never fully complete the approach.
			return check_true(case, float(full_step) > float(half_step),
				"full=%f half=%f" % [full_step, half_step])
		&"damp_angle_takes_the_short_way":
			# From just under +PI to just over -PI is a small step, not a 2*PI spin.
			var start := 3.10
			var target := -3.10
			var out := PlayerMotion.damp_angle(start, target, 20.0, 1.0 / 60.0)
			var wrapped := wrapf(out - start, -PI, PI)
			return check_true(case, absf(wrapped) < 0.5,
				"moved %f rad the long way instead of ~%f" % [absf(wrapped), absf(target - start)])
		&"damp_angle_handles_the_seam":
			var out := PlayerMotion.damp_angle(3.14, -3.14, 20.0, 1.0 / 60.0)
			return check_in_range(case, out, -PI, PI)
	return fail(case, "unhandled case")