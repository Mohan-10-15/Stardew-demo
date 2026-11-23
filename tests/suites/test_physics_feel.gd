extends TestSuite
## W5.2: fixed-step controller-feel rules as pure math. These do not depend on
## the physics engine, so they hold at 30, 60 or 144 Hz display rates.

func get_cases() -> Array[StringName]:
	return [
		&"jump_apex_clears_a_one_metre_block",
		&"coyote_time_allows_a_late_jump",
		&"jump_buffer_allows_an_early_press",
		&"step_up_respects_the_configured_height",
		&"gravity_is_identical_at_any_display_rate",
	]


func _cfg() -> MovementConfig:
	var cfg := MovementConfig.new()
	cfg.jump_velocity = 8.0
	cfg.coyote_time = 0.10
	cfg.jump_buffer = 0.12
	cfg.step_up_height = 0.35
	cfg.fall_gravity_scale = 1.35
	cfg.terminal_velocity = 55.0
	return cfg


func _run(case: StringName) -> Dictionary:
	var cfg := _cfg()
	match case:
		&"jump_apex_clears_a_one_metre_block":
			var apex := PlayerMotion.jump_apex(cfg, 24.0)
			if apex < 1.2:
				return fail(case, "apex %.2f m cannot clear a 1 m block" % apex)
			return succeeded(case, "apex %.2f m" % apex)
		&"coyote_time_allows_a_late_jump":
			if not PlayerMotion.can_jump(false, 0.05, 0.01, cfg):
				return fail(case, "a jump 50 ms after leaving ground was refused")
			if PlayerMotion.can_jump(false, 0.30, 0.01, cfg):
				return fail(case, "a jump 300 ms after leaving ground was allowed")
			return succeeded(case, "0.10 s coyote window")
		&"jump_buffer_allows_an_early_press":
			# A buffered press fires at the instant of touchdown (grounded=true).
			if not PlayerMotion.can_jump(true, 0.0, 0.10, cfg):
				return fail(case, "a buffered press 100 ms before landing was refused")
			if PlayerMotion.can_jump(true, 0.0, 0.30, cfg):
				return fail(case, "a press 300 ms early was not expired")
			return succeeded(case, "0.12 s jump buffer")
		&"step_up_respects_the_configured_height":
			if not PlayerMotion.can_step_up(0.30, cfg):
				return fail(case, "a 0.30 m ledge was refused")
			if PlayerMotion.can_step_up(0.50, cfg):
				return fail(case, "a 0.50 m ledge was allowed")
			return succeeded(case, "step-up limit 0.35 m")
		&"gravity_is_identical_at_any_display_rate":
			var v30 := Vector3.ZERO
			var v144 := Vector3.ZERO
			for _i: int in range(60):
				v30 = PlayerMotion.apply_gravity(v30, cfg, 24.0, 1.0 / 30.0, false)
			for _i: int in range(288):
				v144 = PlayerMotion.apply_gravity(v144, cfg, 24.0, 1.0 / 144.0, false)
			if absf(v30.y - v144.y) > 0.5:
				return fail(case, "2 s fall differs: %.2f vs %.2f" % [v30.y, v144.y])
			return succeeded(case, "2 s fall within 0.5 m/s across rates")
	return fail(case, "no case implementation for %s" % case)
