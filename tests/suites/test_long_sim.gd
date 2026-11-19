extends TestSuite
## M19: drive the real game scene through two full years. The C# sweep in
## `test_balance.gd` proves the crop economy; this proves the assembled game
## survives the same span with no crash, no soft-lock, no printed money and no
## resource that quietly grows without bound.

const MAIN := "res://scenes/core/main.tscn"
const DAYS := 224  # Clock.DAYS_PER_YEAR * BalanceReport.YEARS

var _main: Node = null


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"a_two_year_bot_completes_without_softlock",
		&"idling_two_years_prints_no_money",
		&"resources_stay_bounded_over_two_years",
	]


func setup() -> void:
	_main = null


func teardown() -> void:
	_reset()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"a_two_year_bot_completes_without_softlock":
			return await _t_bot()
		&"idling_two_years_prints_no_money":
			return await _t_idle()
		&"resources_stay_bounded_over_two_years":
			return await _t_bounded()
	return fail(case, "no case implementation for %s" % case)


func _t_bot() -> Dictionary:
	var c := &"a_two_year_bot_completes_without_softlock"
	var built := await _build()
	if built.is_empty():
		return fail(c, "the main scene did not boot")
	var before: int = _main.get_child_count()
	for day: int in range(DAYS):
		autoload(&"EventBus").emit_signal(&"day_started", day + 1)
		_bot_day(day)
		if day % 16 == 0:
			await tree.process_frame
	await _step(6)
	var after: int = _main.get_child_count()
	if after > before + 2:
		return fail(c, "main grew from %d to %d children" % [before, after])
	if autoload(&"GameState").phase == GameState.Phase.TITLE:
		return fail(c, "the game fell back to the title screen")
	return succeeded(c, "%d days, children %d -> %d, phase %d" % [
		DAYS, before, after, autoload(&"GameState").phase,
	])


func _t_idle() -> Dictionary:
	var c := &"idling_two_years_prints_no_money"
	var built := await _build()
	if built.is_empty():
		return fail(c, "the main scene did not boot")
	var wallet: Object = built["wallet"]
	var before: int = int(wallet.get("gold"))
	for day: int in range(DAYS):
		autoload(&"EventBus").emit_signal(&"day_started", day + 1)
		if day % 32 == 0:
			await tree.process_frame
	await _step(4)
	var after: int = int(wallet.get("gold"))
	if after != before:
		return fail(c, "gold drifted from %d to %d with no player actions" % [before, after])
	return succeeded(c, "%d idle days left %d gold untouched" % [DAYS, after])


func _t_bounded() -> Dictionary:
	var c := &"resources_stay_bounded_over_two_years"
	var built := await _build()
	if built.is_empty():
		return fail(c, "the main scene did not boot")
	var bag: Object = built["bag"]
	var animals: Node = built["animals"]
	var peak_items := 0
	for day: int in range(DAYS):
		autoload(&"EventBus").emit_signal(&"day_started", day + 1)
		_bot_day(day)
		peak_items = maxi(peak_items, _item_count(bag))
		if day % 16 == 0:
			await tree.process_frame
	await _step(4)
	# One hen product per day is legitimate production, not a leak: the bound is
	# "at most an item a day plus the starting loadout", which would catch a
	# compounding resource or a duplicate-on-collect bug.
	if peak_items > DAYS + 40:
		return fail(c, "the bag grew to %d items: %s" % [
			peak_items, str(_bag_summary(bag)),
		])
	if animals != null:
		for id: StringName in [&"hen", &"goat"]:
			var stored: int = int(animals.call("stored_of", id))
			if stored > 40:
				return fail(c, "%s stored %d products with no collection" % [id, stored])
	var gold: int = int(built["wallet"].get("gold"))
	if gold < 0:
		return fail(c, "gold went negative: %d" % gold)
	return succeeded(c, "%d days, peak bag %d items, gold %d" % [DAYS, peak_items, gold])


## One day of honest bot work: water the plot, feed the hen, collect and load
## machines. No dev cheats, no direct wallet edits — just the services.
func _bot_day(day: int) -> void:
	var state: Node = _main.get("player_state")
	var farm: Node = _main.get("farm_service")
	var machines: Node = _main.get("machine_service")
	var animals: Node = _main.get("animal_service")
	if state == null or state.get("inventory") == null:
		return
	var bag: Object = state.get("inventory")
	if farm != null and farm.get("grid") != null:
		var grid: Object = farm.get("grid")
		for tile: Object in grid.call("get_tiles"):
			if bool(tile.get("is_tilled")):
				tile.call("water")
			elif day % 7 == 0 and String(tile.get("crop_id")).is_empty():
				tile.call("till")
				tile.call("plant", &"parsnip")
	if animals != null:
		# Top up only when empty. Adding feed every day regardless of whether
		# the hen ate it would make the *bot* print onions, not the game leak.
		if int(bag.call("count", &"spring_onion")) == 0:
			bag.call("add", &"spring_onion", 1)
		animals.call("feed", &"hen")
		animals.call("collect", &"hen")
	if machines != null and not machines.placed.is_empty():
		for slot: int in range(machines.placed.size()):
			machines.call("collect", slot)


func _bag_slots(bag: Object) -> Array:
	var saved: Dictionary = bag.call("to_dict")
	var slots: Variant = saved.get("slots", [])
	return slots as Array if slots is Array else []


func _item_count(bag: Object) -> int:
	var total := 0
	for stack: Variant in _bag_slots(bag):
		if stack is Dictionary and (stack as Dictionary).has("amount"):
			total += int((stack as Dictionary)["amount"])
	return total


func _bag_summary(bag: Object) -> Dictionary:
	var counts := {}
	for stack: Variant in _bag_slots(bag):
		if stack is Dictionary:
			var id := String((stack as Dictionary).get("id", "?"))
			counts[id] = int(counts.get(id, 0)) + int((stack as Dictionary).get("amount", 0))
	return counts


func _build() -> Dictionary:
	_reset()
	var packed := load(MAIN) as PackedScene
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	root().add_child(_main)
	await _step(8)
	var state: Node = _main.get("player_state")
	if state == null:
		return {}
	return {
		"wallet": state.get("wallet"), "bag": state.get("inventory"),
		"animals": _main.get("animal_service"),
	}


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame


func _reset() -> void:
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null
