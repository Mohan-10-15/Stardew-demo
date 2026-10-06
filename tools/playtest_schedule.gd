extends SceneTree
## Plays Group 16 in the real game and photographs it, so "every schedule passes
## `is_valid()`" and "a person watches six villagers live a day" stop being the
## same claim.
##
## Run (needs a real rendering driver, so NOT --headless):
##     tools\Godot_v4.5-stable_win64_console.exe --path . --rendering-driver opengl3 --script res://tools/playtest_schedule.gd
##
## ## What is real here
##
## The whole shipped stack: `scenes/core/main.tscn` boots itself, so the world, the
## player, the clock, the HUD, the navigation grid and the six villagers are the ones
## a player gets. The only things this file does that a player cannot are hold the
## clock open so an afternoon is not ten real minutes, walk with scripted key events,
## and take a screenshot.
##
## Nothing here calls [method Npc.walk_to], [method NpcManager.refresh_schedules] or
## [method Npc.set_schedule]. The clock is stepped with `TimeService.advance_tick()` -
## the very call `_process` makes - which fires `EventBus.time_minute_changed`, which
## is what the manager is subscribed to. Every destination the harness reports is read
## back off `Npc.scheduled_location_id`, which is the manager's own answer, not one
## this file computed. A playtest that lays paths itself is testing the playtest.
##
## ## Why the clock is held still
##
## `TimeService.running` is switched off for the whole run, so every change of hour is
## one the harness asked for. The reason is that a checkpoint that slides while it is
## being measured measures nothing: the first run of this file left the clock running
## through a two-minute arrival wait, watched three villagers be reassigned out from
## under it, and reported a 60 m "drift" that was the afternoon happening on schedule.
## Holding time still is what makes "where is everybody at 15:00" a question with one
## answer; the walking itself is still real, still on real physics frames, and still
## started by the clock's own tick.
##
## ## The five questions this asks
##
## 1. Does a new day start with everybody on their own doorstep, and does the corner
##    clock agree that it is 6:00 AM?
## 2. When the clock ticks past the start of a block, does the villager whose block it
##    is actually *walk* there - never teleport - and stop close enough to be found?
## 3. Having arrived, do they hold it, or drift off it the moment the harness looks
##    away?
## 4. Does a player who walks into the village square find them there?
## 5. Does the day rollover put everyone back, and is that a walk or a placement?
##
## Output: `res://art_review_schedule_*.png`, all gitignored.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const SHOT_DIR := "res://art_review_schedule_"
## Loaded by path rather than named: this is a `--script` entry point, and naming a
## `class_name` here would pull that script - and everything it references - into the
## tool's own compile. Same reason `playtest_npc.gd` loads its registry.
const LOCATION_REGISTRY := "res://scripts/world/location_registry.gd"

## One in-game hour is six ticks of ten minutes.
const TICKS_PER_HOUR := 6
## Real frames to let the world run between clock ticks. Half a second: long enough
## that a villager takes a visible step, short enough that four hours is not an hour
## of watching.
const FRAMES_PER_TICK := 30
## How close to a scheduled post counts as "arrived", and how slow. The runtime suite
## asserts 1.2 m; this asks for 2 m because a player reading a villager across the
## square is not holding a tape measure, and the path's last waypoint is a snapped
## grid cell rather than the anchor itself. The speed half is what makes arrival a
## *state* rather than a coordinate - see [method _stragglers].
const ARRIVAL_METRES := 2.0
## Below this, a villager counts as standing rather than still covering the last of
## their walk. A tenth of walking pace; anything above it is a body still in motion.
const ARRIVED_SPEED := 0.17
## How far from their own front step a villager may be while on free time. The wander
## disc is `wander_radius * 0.85` around home, and the widest is 7 m.
const DOORSTEP_METRES := 9.0
## How far a held post may move *during* the hold window - displacement from where
## the villager was standing when the window opened, not distance to the anchor. The
## two came apart in the first run: Bram stops about 2 m from `forest_edge`'s authored
## point because the destination is snapped to the nearest walkable cell and trees are
## exactly what a forest edge has, and a check that measured distance to the anchor
## called a villager standing perfectly still "60 m of drift".
##
## Measured after a settle, because arrival coasts - `ARRIVE_DISTANCE` is 0.6 m and the
## body still has velocity when the check opens.
const HOLD_METRES := 0.4
## Frames of settling before the hold window opens, and frames in it. Half a second
## either way: long enough that a coasting body has stopped, short enough that the
## window is still about this hour rather than the next one.
const HOLD_SETTLE_FRAMES := 40
const HOLD_FRAMES := 90
## A villager walks at about 1.7 m/s. Over a 60 Hz physics tick that is under 3 cm, so
## anything larger than this in a single frame is a placement rather than a walk.
const TELEPORT_METRES := 0.5
## Generous: Bram's walk from his cottage to the forest edge is 77 m, which is three
## quarters of a minute of real walking before any detour the grid asks for.
const ARRIVAL_SECONDS := 130.0
## The player's walk to the square, in real seconds.
const PLAYER_WALK_SECONDS := 75.0


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("could not load %s" % MAIN_SCENE)
		return

	# Wait for the game to say it is ready, not for a number of frames.
	var bus: Node = root.get_node_or_null(^"EventBus")
	if bus == null:
		_fail("EventBus autoload missing")
		return
	var announced_ready := [false]
	bus.game_ready.connect(func() -> void: announced_ready[0] = true)

	var main: Node = packed.instantiate()
	root.add_child(main)
	var ready_deadline := Time.get_ticks_msec() + 30000
	while not bool(announced_ready[0]) and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	if not bool(announced_ready[0]):
		_fail("the game never announced EventBus.game_ready")
		return
	print("[play] game ready; playing")

	var player: Node3D = main.get("player")
	var manager: Node = main.get("npc_manager")
	var clock: Node = _find_clock(main)
	var clock_hud: Node = main.get("clock_hud")
	var locations: Script = load(LOCATION_REGISTRY)
	if player == null or manager == null or clock == null or locations == null:
		_fail("main scene came up without a player / npc manager / clock / location registry")
		return
	if not bool(manager.get("apply_schedules")):
		_fail("npc_manager.apply_schedules is off; the shipped world does not give anyone a day")
		return

	# Hold time still before anything is measured. See the header: with the clock
	# running, a two-minute arrival wait is three in-game hours and every post in the
	# valley changes underneath the harness.
	clock.set("running", false)

	var cast: Array = manager.call("npcs")
	if cast.is_empty():
		_fail("the valley spawned no villagers")
		return
	print("[play] %d villagers, clock at %s" % [
		cast.size(), String(clock.get("time").call("describe_time")),
	])

	# The teleport watcher runs alongside everything below for the whole session. It is
	# stopped before the day rollover, which places people rather than walking them, so
	# that the one placement the design calls for does not hide the ones it does not.
	var watching := [true]
	_watch_for_teleports(cast, watching)

	# --- 1. Six in the morning ---------------------------------------------------
	await _settle(40)
	_report("06:00", cast, locations, clock, clock_hud)
	_check_doorsteps(cast, locations, "the morning starts at the doorstep")
	await _shot(SHOT_DIR + "1_morning.png")

	# --- 2. Let the morning happen ------------------------------------------------
	# The clock is stepped and the world is given real frames between steps, so the
	# walks happen while the hours pass rather than after them. That is the difference
	# between "the destination is right" and "they got there in time to be seen".
	print("[play] stepping the clock 06:00 -> 10:00")
	await _advance_to(clock, 10, cast, locations)
	_report("10:00", cast, locations, clock, clock_hud)
	_check_clock_hud(clock_hud, "10:00 AM", "the corner clock reads 10:00 AM")
	if not await _wait_for_arrival(cast, locations, ARRIVAL_SECONDS):
		_fail("not everyone reached their 10:00 post in %.0f s" % ARRIVAL_SECONDS)
	await _hold_check(cast, locations, "the morning post is held")

	# --- 3. Three of them are in the square all afternoon ------------------------
	print("[play] stepping the clock 10:00 -> 15:00")
	await _advance_to(clock, 15, cast, locations)
	_report("15:00", cast, locations, clock, clock_hud)
	if not await _wait_for_arrival(cast, locations, ARRIVAL_SECONDS):
		_fail("not everyone reached their 15:00 post in %.0f s" % ARRIVAL_SECONDS)
	await _hold_check(cast, locations, "the afternoon post is held")

	# The player's own walk. Everything above can be true while the valley is still
	# somewhere the player cannot reach; this is the part a person actually does.
	var square: Variant = locations.call("get_location", &"village_square")
	if square == null:
		_fail("the village square has no location")
	else:
		var there: Vector3 = square.call("ground_position")
		print("[play] walking the player to %s at %s" % [
			String(square.get("display_name")), str(there),
		])
		if not await _walk_to(player, there, 3.0, PLAYER_WALK_SECONDS):
			_fail("the player could not walk to the village square")
		await _settle(20)
		_near_post_check(cast, locations, &"village_square", 30.0,
			"a player in the square finds the square's villagers")
		await _shot(SHOT_DIR + "2_square.png")

	# --- 4. The day rolls over ---------------------------------------------------
	# Stopped first: `go_home` places everyone on their own step, by design, and the
	# watcher is here to catch the walks it would otherwise drown in.
	watching[0] = false
	await _settle(10)
	print("[play] ending the day (the method the bed will call; there is no bed yet)")
	clock.call("sleep_until_morning")
	await _settle(60)
	_report("06:00 day 2", cast, locations, clock, clock_hud)
	_check_doorsteps(cast, locations, "the new day starts at the doorstep")
	await _shot(SHOT_DIR + "3_next_morning.png")

	if _failures.is_empty():
		print("[play] PASS - every question above was answered by the shipped game")
		quit(0)
		return
	for reason: String in _failures:
		printerr("[play] FAILED: %s" % reason)
	quit(1)


# --- The questions ---------------------------------------------------------------


## Every villager is on their own doorstep and the HUD agrees about the hour.
func _check_doorsteps(cast: Array, locations: Script, label: String) -> void:
	var strays: Array[String] = []
	for member: Node3D in cast:
		var id := _id_of(member)
		var post := StringName(member.get("scheduled_location_id"))
		var home := StringName("%s_cottage" % id)
		var away := _distance_to(member, locations, home)
		if post != home:
			strays.append("%s is assigned '%s' at dawn, not their cottage" % [id, post])
		elif away > DOORSTEP_METRES:
			strays.append("%s is %.1f m from their own front step" % [id, away])
	if strays.is_empty():
		print("[play] ok   %s (all %d within %.0f m of home)" % [
			label, cast.size(), DOORSTEP_METRES,
		])
		return
	for reason: String in strays:
		_fail("%s: %s" % [label, reason])


## The corner clock is drawn from the real label, not from the component behind it.
##
## Reading the pixels rather than the model is the whole reason this harness takes
## screenshots: the component knowing the hour and the player being told the hour are
## two different claims, and only one of them is what a person reads.
func _check_clock_hud(clock_hud: Node, expected: String, label: String) -> void:
	if clock_hud == null:
		_fail("%s: there is no clock HUD to read" % label)
		return
	var time_label: Node = clock_hud.get_node_or_null(^"Panel/Column/TimeLabel")
	if time_label == null:
		_fail("%s: the clock HUD has no Panel/Column/TimeLabel" % label)
		return
	var shown := String(time_label.get("text")).strip_edges()
	if shown == expected:
		print("[play] ok   %s (label says '%s')" % [label, shown])
	else:
		_fail("%s: the label says '%s', expected '%s'" % [label, shown, expected])


## Nobody assigned a post for this hour has wandered off where they stopped.
##
## Displacement, not distance-to-anchor - see [constant HOLD_METRES]. The distance is
## still printed, because "2 m from the authored point" is a thing worth seeing even
## when it is the grid's snapping rather than a villager who cannot stand still.
func _hold_check(cast: Array, locations: Script, label: String) -> void:
	# Let the coast finish first, or the window measures arrival rather than holding.
	await _settle(HOLD_SETTLE_FRAMES)
	var origin: Dictionary = {}
	for member: Node3D in cast:
		origin[member] = member.global_position
	var worst := 0.0
	var worst_id := &""
	for _frame: int in range(HOLD_FRAMES):
		await physics_frame
		for member: Node3D in cast:
			if not is_instance_valid(member):
				continue
			var start: Vector3 = origin[member]
			var here: Vector3 = member.global_position
			var moved := Vector2(here.x - start.x, here.z - start.z).length()
			if moved > worst:
				worst = moved
				worst_id = _id_of(member)
	var standing := 0.0
	var standing_id := &""
	for member: Node3D in cast:
		var post := StringName(member.get("scheduled_location_id"))
		if post == _home_of(member):
			continue
		var away := _distance_to(member, locations, post)
		if away > standing:
			standing = away
			standing_id = _id_of(member)
	if worst <= HOLD_METRES:
		print("[play] ok   %s (%.3f m of movement over %d frames; furthest from an anchor %s at %.1f m)" % [
			label, worst, HOLD_FRAMES, standing_id, standing,
		])
	else:
		_fail("%s: %s moved %.2f m over %d frames without being reassigned" % [
			label, worst_id, worst, HOLD_FRAMES,
		])


## Anyone whose current post is [param post_id] is standing in [param radius] of it.
##
## This is the player's-eye version of the arrival check: it does not ask whether a
## path exists or a walk finished, it asks whether the people who are supposed to be
## somewhere are somewhere you can see when you get there.
func _near_post_check(cast: Array, locations: Script, post_id: StringName,
		radius: float, label: String) -> void:
	var expected := 0
	var missing: Array[String] = []
	for member: Node3D in cast:
		if StringName(member.get("scheduled_location_id")) != post_id:
			continue
		expected += 1
		var away := _distance_to(member, locations, post_id)
		if away > radius:
			missing.append("%s is %.1f m from %s" % [_id_of(member), away, post_id])
	if expected == 0:
		print("[play] note %s: nobody was assigned %s at this hour" % [label, post_id])
		return
	if missing.is_empty():
		print("[play] ok   %s (%d of %d within %.0f m)" % [label, expected, expected, radius])
		return
	for reason: String in missing:
		_fail("%s: %s" % [label, reason])


## Waits until everyone with a post has reached it, or gives up.
##
## Waits rather than asserting immediately because the walk is the feature: a harness
## that checks the destination one frame after setting the clock reads a villager mid-
## stride, files "nobody is at the well", and burns an afternoon on a bug that does not
## exist. The deadline is the other half - a villager who never arrives is the real
## failure this is here to catch.
func _wait_for_arrival(cast: Array, locations: Script, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last_report := Time.get_ticks_msec()
	var stragglers: Array[String] = _stragglers(cast, locations)
	while not stragglers.is_empty() and Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() - last_report > 15000:
			last_report = Time.get_ticks_msec()
			print("[play]   still waiting on: %s" % ", ".join(stragglers))
		await _settle(10)
		stragglers = _stragglers(cast, locations)
	if stragglers.is_empty():
		print("[play] ok   everyone reached their post (%.0f s budget)" % seconds)
		return true
	for reason: String in stragglers:
		print("[play]   straggler: %s" % reason)
	return false


## Who has not reached the place their schedule named.
##
## "Reached" is two things, not one: close enough, and standing still. The first run
## only asked the first, and the hold window then opened on a villager who was still
## walking the last metre of the path they had already arrived on - the path's own
## [constant Npc.ARRIVE_DISTANCE] is 0.6 m while this harness allows 2 m, so a body
## with real velocity was still coasting into place while the harness called it
## standing still and measured the coast as drift.
func _stragglers(cast: Array, locations: Script) -> Array[String]:
	var out: Array[String] = []
	for member: Node3D in cast:
		var post := StringName(member.get("scheduled_location_id"))
		if post == _home_of(member):
			continue
		var away := _distance_to(member, locations, post)
		# `velocity` belongs to CharacterBody3D, not Node3D, so it arrives as a Variant.
		var speed := 0.0
		var body: Variant = member.get("velocity")
		if body is Vector3:
			speed = (body as Vector3).length()
		if away > ARRIVAL_METRES:
			out.append("%s -> %s, %.1f m short" % [_id_of(member), post, away])
		elif speed > ARRIVED_SPEED:
			out.append("%s -> %s, still moving at %.2f m/s" % [_id_of(member), post, speed])
	return out


# --- Driving the world -----------------------------------------------------------


## Steps the real clock to [param target_hour], giving the world real frames between
## ticks so the walks happen while the hours pass.
func _advance_to(clock: Node, target_hour: int, _cast: Array, _locations: Script) -> void:
	var guard := 0
	while int(clock.get("time").get("hour")) < target_hour and guard < 200:
		clock.call("advance_tick")
		guard += 1
		await _settle(FRAMES_PER_TICK)
	if int(clock.get("time").get("hour")) != target_hour:
		_fail("the clock would not reach %02d:00 (stopped at %s)" % [
			target_hour, String(clock.get("time").call("describe_time")),
		])


## Samples every villager every physics frame and records the largest single-frame
## move any of them makes.
##
## The point is the *shape* of the movement, not the distance: a schedule that
## teleports people to their post would satisfy every arrival check in this file while
## reading as a bug the first time a player watches it happen.
func _watch_for_teleports(cast: Array, watching: Array) -> void:
	var worst := 0.0
	var worst_id := &""
	var worst_at := ""
	var previous: Dictionary = {}
	for member: Node3D in cast:
		previous[member] = member.global_position
	while bool(watching[0]):
		await physics_frame
		for member: Node3D in cast:
			if not is_instance_valid(member):
				continue
			var here: Vector3 = member.global_position
			var before: Vector3 = previous.get(member, here)
			var step := Vector2(here.x - before.x, here.z - before.z).length()
			if step > worst:
				worst = step
				worst_id = _id_of(member)
				worst_at = String(member.get("scheduled_location_id"))
			previous[member] = here
	if worst <= TELEPORT_METRES:
		print("[play] ok   nobody teleported (largest single-frame move %.3f m, %s)" % [
			worst, worst_id,
		])
	else:
		_fail("%s moved %.2f m in one frame while assigned '%s' - that is a placement, not a walk" % [
			worst_id, worst, worst_at,
		])


## Prints where everybody is, in the words a player would recognise.
func _report(when: String, cast: Array, locations: Script, clock: Node, clock_hud: Node) -> void:
	var hud := ""
	if clock_hud != null:
		var label: Node = clock_hud.get_node_or_null(^"Panel/Column/TimeLabel")
		if label != null:
			hud = String(label.get("text"))
	print("[play] --- %s (clock says %s%s) ---" % [
		when, String(clock.get("time").call("describe_time")),
		"; HUD says '%s'" % hud if hud != "" else "",
	])
	for member: Node3D in cast:
		var post := StringName(member.get("scheduled_location_id"))
		var place: Variant = locations.call("get_location", post)
		var name := post
		if place != null:
			name = StringName(String(place.get("display_name")))
		print("[play]   %-7s %-18s %s away=%s walking=%s" % [
			_id_of(member), String(name), str(member.global_position),
			("%.1f" % _distance_to(member, locations, post)) if place != null else "n/a",
			str(bool(member.call("is_walking_to_post"))),
		])


# --- Plumbing --------------------------------------------------------------------


## XZ distance from [param member] to [param post_id]'s authored ground position.
func _distance_to(member: Node3D, locations: Script, post_id: StringName) -> float:
	var place: Variant = locations.call("get_location", post_id)
	if place == null:
		return INF
	var goal: Vector3 = place.call("ground_position")
	return Vector2(member.global_position.x - goal.x,
		member.global_position.z - goal.z).length()


func _home_of(member: Node3D) -> StringName:
	return StringName("%s_cottage" % _id_of(member))


func _id_of(member: Node3D) -> StringName:
	var data: Resource = member.get("data")
	return StringName(data.get("id")) if data != null else &""


## The [TimeService] in the tree, found by what it can do rather than by its type name.
##
## `--script` again: naming the class here would compile its whole dependency chain
## into this tool, and that chain reaches the `Log` autoload.
func _find_clock(from: Node) -> Node:
	if from == null:
		return null
	if from.has_method("advance_tick") and from.has_method("sleep_until_morning"):
		return from
	for child: Node in from.get_children():
		var found := _find_clock(child)
		if found != null:
			return found
	return null


## Walks the player toward [param target] with the real movement keys held down.
##
## Turned first, then walked: the movement basis is the aim heading, so walking before
## turning sends the player off at forty-five degrees. Sides-steps with a real key when
## wedged, the way anyone gets past a boulder, alternating so a corridor of two trees
## cannot trap it going the same way twice.
func _walk_to(player: Node3D, target: Vector3, tolerance: float, ceiling: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(ceiling * 1000.0)
	var flat := func() -> float:
		return Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(target.x, target.z)
		)
	var last: float = flat.call()
	var stalled_since := Time.get_ticks_msec()
	var strafe_left := true
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() < deadline:
		var to: Vector3 = target - player.global_position
		to.y = 0.0
		if to.length() <= tolerance:
			break
		player.call("set_yaw", atan2(-to.x, -to.z))
		await _seconds(0.05)
		var now: float = flat.call()
		if now <= last - 0.01:
			last = now
			stalled_since = Time.get_ticks_msec()
			Input.action_release(&"move_left")
			Input.action_release(&"move_right")
			continue
		if Time.get_ticks_msec() - stalled_since <= 700:
			await _seconds(0.15)
			continue
		var side := &"move_left" if strafe_left else &"move_right"
		var other := &"move_right" if strafe_left else &"move_left"
		Input.action_release(other)
		Input.action_press(side)
		strafe_left = not strafe_left
		print("[play]   wedged %.2fm short of %s; stepping %s" % [now, str(target), String(side)])
		await _seconds(0.45)
		Input.action_release(side)
		last = flat.call()
		stalled_since = Time.get_ticks_msec()
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	await _settle(4)
	var remaining := float(flat.call())
	if remaining > tolerance:
		print("[play] walk gave up: %s -> %s, still %.2fm away" % [
			str(player.global_position), str(target), remaining,
		])
		return false
	return true


## Settles for [param frames] frames. Both halves, because the camera rig and the
## villagers both live on the physics tick and a render-only wait catches them mid-step.
func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


## Waits for wall-clock time, with a frame ceiling so a wedged engine fails the tool
## instead of hanging it.
func _seconds(value: float, frame_ceiling: int = 900) -> void:
	var deadline := Time.get_ticks_msec() + int(value * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline and frames < frame_ceiling:
		await process_frame
		await physics_frame
		frames += 1


## Saves the viewport to [param path].
func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("[play] no image for %s" % path)
		return
	var err := image.save_png(path)
	print("[play] %s %s (%dx%d)" % [
		"wrote" if err == OK else "FAILED to write", path, image.get_width(), image.get_height(),
	])


func _fail(reason: String) -> void:
	_failures.append(reason)
	printerr("[play] FAILED: %s" % reason)
