extends TestSuite
## Festivals happen in the world: they defer every schedule, pay attendees and
## report a skip when the player never turned up.

const SERVICE_SCRIPT := "res://scripts/festivals/festival_service.gd"
const TIME_SCRIPT := "res://scripts/time/time_service.gd"
const MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _watchers: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"festivals_and_gathering_days_authored",
		&"a_festival_defers_the_whole_cast",
		&"attending_pays_once",
		&"skipping_reports_what_was_missed",
	]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"festivals_and_gathering_days_authored":
			return _t_content()
		&"a_festival_defers_the_whole_cast":
			return await _t_defer()
		&"attending_pays_once":
			return await _t_attend()
		&"skipping_reports_what_was_missed":
			return await _t_skip()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"festivals_and_gathering_days_authored"
	var all := FestivalRegistry.all()
	if all.size() < 3:
		return fail(c, "only %d festivals authored" % all.size())
	var seen: Dictionary = {}
	for festival: FestivalData in all:
		if not festival.is_valid():
			return fail(c, "%s is invalid" % festival.id)
		var key := "%d_%d" % [festival.season, festival.day_of_month]
		if seen.has(key):
			return fail(c, "two festivals on %s" % key)
		seen[key] = festival.id
	for data: NpcData in NpcRegistry.all_npcs():
		var id := StringName("%s_festival" % data.id)
		if ScheduleRegistry.schedule_for(id) == null:
			return fail(c, "%s has no gathering day" % data.id)
	return succeeded(c, "%d festivals, %d gathering days" % [
		all.size(), NpcRegistry.all_npcs().size(),
	])


func _t_defer() -> Dictionary:
	var c := &"a_festival_defers_the_whole_cast"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the festival rig")
	_watch()
	var festival: FestivalData = FestivalRegistry.all()[0]
	var clock: Node = built["clock"]
	clock.time.season = festival.season
	clock.time.day_of_month = festival.day_of_month
	var service: Node = built["festival"]
	service.call("_check_date")
	if StringName(service.get("current_id")) != festival.id:
		return fail(c, "the date did not start '%s'" % festival.id)
	if not bool(built["manager"].get("festival_active")):
		return fail(c, "the cast did not defer to the gathering day")
	if int(_events.get(&"festival_started", 0)) != 1:
		return fail(c, "no festival_started event")
	if root().get_node_or_null(^"FestivalDecor") == null:
		return fail(c, "no decorations appeared in the world")
	_stop_watch()
	return succeeded(c, "%s deferred every schedule and decorated the square" % festival.id)


func _t_attend() -> Dictionary:
	var c := &"attending_pays_once"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the festival rig")
	_watch()
	var festival: FestivalData = FestivalRegistry.all()[0]
	_start_festival(built, festival)
	var wallet: Object = built["state"].get("wallet")
	var before := int(wallet.get("gold"))
	built["player"].global_position = Vector3(38, 0.4, 8)
	await _step(3)
	await _step(3)  # one more frame: attendance must be idempotent
	if int(_events.get(&"festival_attended", 0)) != 1:
		return fail(c, "%d attendance events" % int(_events.get(&"festival_attended", 0)))
	if int(wallet.get("gold")) != before + festival.reward_gold:
		return fail(c, "gold went %d -> %d, expected +%d" % [
			before, int(wallet.get("gold")), festival.reward_gold,
		])
	_stop_watch()
	return succeeded(c, "attendance paid %dg exactly once" % festival.reward_gold)


func _t_skip() -> Dictionary:
	var c := &"skipping_reports_what_was_missed"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build the festival rig")
	_watch()
	var festival: FestivalData = FestivalRegistry.all()[0]
	_start_festival(built, festival)
	var clock: Node = built["clock"]
	clock.time.day_of_month = (festival.day_of_month % 28) + 1
	built["festival"].call("_check_date")
	if int(_events.get(&"festival_skipped", 0)) != 1:
		return fail(c, "skip was not reported")
	if int(_events.get(&"festival_ended", 0)) != 1:
		return fail(c, "the festival did not end")
	if bool(built["manager"].get("festival_active")):
		return fail(c, "the cast stayed on the gathering day")
	if root().get_node_or_null(^"FestivalDecor") != null:
		return fail(c, "decorations were left behind")
	_stop_watch()
	return succeeded(c, "a missed festival ends, reports and cleans up")


func _start_festival(built: Dictionary, festival: FestivalData) -> void:
	var clock: Node = built["clock"]
	clock.time.season = festival.season
	clock.time.day_of_month = festival.day_of_month
	built["festival"].call("_check_date")


func _build() -> Dictionary:
	_stop_watch()
	_reset_rig()
	var fest_script := load(SERVICE_SCRIPT) as GDScript
	var time_script := load(TIME_SCRIPT) as GDScript
	var manager_script := load(MANAGER_SCRIPT) as GDScript
	var state_script := load(STATE_SCRIPT) as GDScript
	if fest_script == null or time_script == null or manager_script == null \
			or state_script == null:
		return {}
	_ensure_rig()
	var clock: Node = time_script.new()
	clock.name = "TimeService"
	clock.running = false
	_rig.add_child(clock)
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var player := Node3D.new()
	player.name = "Player"
	# add_child first: setting global_position on a parentless node logs an error
	# on every boot (AGENTS.md, trap two).
	_rig.add_child(player)
	player.global_position = Vector3(0, 0.4, 14)
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	var festival: Node = fest_script.new()
	festival.name = "FestivalService"
	_rig.add_child(festival)
	await _step(2)
	return {"clock": clock, "state": state, "player": player,
		"manager": manager, "festival": festival}


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"festival_started": 0, &"festival_attended": 0,
		&"festival_skipped": 0, &"festival_ended": 0}
	for key: StringName in [&"festival_started", &"festival_attended",
			&"festival_skipped", &"festival_ended"]:
		var callable := _two(key) if key == &"festival_attended" else _one(key)
		_watchers[key] = callable
		bus.connect(key, callable)


func _one(key: StringName) -> Callable:
	return func(_id: StringName) -> void: _events[key] = int(_events.get(key, 0)) + 1


func _two(key: StringName) -> Callable:
	return func(_id: StringName, _gold: int) -> void: _events[key] = int(_events.get(key, 0)) + 1


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	for key: StringName in _watchers:
		if bus.is_connected(key, _watchers[key]):
			bus.disconnect(key, _watchers[key])
	_watchers.clear()
	_events.clear()


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "FestivalTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null
	var decor := root().get_node_or_null(^"FestivalDecor")
	if decor != null:
		decor.free()


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
