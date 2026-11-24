extends TestSuite
## W5.3: deterministic drop and water rules. No physics server needed — the
## same pure functions drive both the game and these assertions.

func get_cases() -> Array[StringName]:
	return [&"drops_settle_and_magnet", &"drops_merge_and_evict",
		&"water_buoyancy_reaches_equilibrium", &"water_drag_and_swim"]


func _run(case: StringName) -> Dictionary:
	match case:
		&"drops_settle_and_magnet":
			if DropRules.should_sleep(0.1, 0.4):
				pass
			else:
				return fail(case, "a still drop did not settle")
			if DropRules.should_sleep(2.0, 1.0):
				return fail(case, "a fast drop settled")
			var pull := DropRules.magnet_velocity(Vector3.ZERO, Vector3(2, 0, 0), true)
			if pull.x <= 0.0:
				return fail(case, "no magnet pull toward the player")
			if DropRules.magnet_velocity(Vector3.ZERO, Vector3(9, 0, 0), true) != Vector3.ZERO:
				return fail(case, "magnet reached beyond 2.5 m")
			return succeeded(case, "settle, magnet and radius correct")
		&"drops_merge_and_evict":
			var entries: Array[Dictionary] = [
				{"item_id": &"wood", "position": Vector3.ZERO, "age": 1.0},
				{"item_id": &"wood", "position": Vector3(0.5, 0, 0), "age": 2.0},
				{"item_id": &"stone", "position": Vector3(0.1, 0, 0), "age": 3.0},
			]
			var groups := DropRules.merge_groups(entries)
			if groups.size() != 1 or (groups[0] as Array).size() != 2:
				return fail(case, "merge groups: %s" % str(groups))
			if DropRules.evict_index(entries) != -1:
				return fail(case, "evicted below the 128 cap")
			var many: Array[Dictionary] = []
			for i: int in range(DropRules.MAX_ACTIVE + 2):
				many.append({"age": float(i)})
			if DropRules.evict_index(many) != many.size() - 1:
				return fail(case, "the oldest drop was not evicted")
			return succeeded(case, "same-item merge and oldest eviction")
		&"water_buoyancy_reaches_equilibrium":
			var h := 1.8
			var at_surface := WaterPhysics.buoyancy(0.0, h)
			var shallow := WaterPhysics.buoyancy(0.4, h)
			var deep := WaterPhysics.buoyancy(0.9, h)
			var equilibrium := WaterPhysics.buoyancy(WaterPhysics.equilibrium_depth(h), h)
			if at_surface != 0.0 or deep <= shallow:
				return fail(case, "buoyancy did not grow with depth")
			if absf(equilibrium - 9.8) > 3.0:
				return fail(case, "equilibrium is %.1f, not near gravity" % equilibrium)
			return succeeded(case, "buoyancy rises and balances at %.2f m" % [
				WaterPhysics.equilibrium_depth(h),
			])
		&"water_drag_and_swim":
			var v := WaterPhysics.drag(Vector3(1, 0, 0), 0.1)
			if v.x >= 1.0 or v.x <= 0.0:
				return fail(case, "water drag did not slow the body")
			if WaterPhysics.can_swim(0.1, 1.8) or not WaterPhysics.can_swim(1.2, 1.8):
				return fail(case, "swim gate is wrong")
			return succeeded(case, "drag and swim depth gate correct")
	return fail(case, "no case implementation for %s" % case)
