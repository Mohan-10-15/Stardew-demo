extends TestSuite
## W5.4: every feel effect has a real off-switch. A disabled player gets zero
## added motion, not a smaller amount.

func get_cases() -> Array[StringName]:
	return [&"shake_respects_zero_intensity", &"hit_stop_respects_the_switch",
		&"bob_and_view_sway_can_be_disabled", &"fov_kick_is_bounded"]


func _run(case: StringName) -> Dictionary:
	match case:
		&"shake_respects_zero_intensity":
			if Juice.shake_from_trauma(1.0, 0.0) != 0.0:
				return fail(case, "0 % shake still produced motion")
			if Juice.shake_from_trauma(0.5, 1.0) <= 0.0:
				return fail(case, "shake never fires at full intensity")
			if Juice.decay_trauma(1.0, 1.0) != 0.0:
				return fail(case, "trauma did not decay to zero")
			return succeeded(case, "0 % shake is exactly zero")
		&"hit_stop_respects_the_switch":
			var off := Juice.hit_stop_seconds(1.0, false)
			var on := Juice.hit_stop_seconds(1.0, true)
			if off != 0.0 or on < 0.06 or on > 0.09:
				return fail(case, "hit-stop off=%f on=%f" % [off, on])
			return succeeded(case, "off is zero, on is 60-90 ms")
		&"bob_and_view_sway_can_be_disabled":
			if Juice.bob_offset(1.0, false) != 0.0:
				return fail(case, "head bob still moves when disabled")
			if Juice.bob_offset(PI / 2.0, true) <= 0.0:
				return fail(case, "enabled bob never moves")
			if Juice.view_sway(Vector2(1, 1), Vector2(5, 5), false, 1.0) != Vector2.ZERO:
				return fail(case, "view sway still moves when disabled")
			return succeeded(case, "bob and sway both off at zero")
		&"fov_kick_is_bounded":
			var base := 78.0
			if not is_equal_approx(Juice.sprint_fov(base, 0.0), base):
				return fail(case, "idle sprint changed FOV")
			var kick := Juice.sprint_fov(base, 1.0) - base
			if kick <= 0.0 or kick > 8.0:
				return fail(case, "kick %f is out of range" % kick)
			return succeeded(case, "bounded +%.1f deg kick" % kick)
	return fail(case, "no case implementation for %s" % case)
