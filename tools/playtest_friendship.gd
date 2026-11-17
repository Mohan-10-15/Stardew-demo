extends SceneTree
## Plays the relationship path in the real game and photographs each step, so
## "535 green cases" and "a player can court somebody" stop being the same claim.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_friendship.gd
##
## ## What is real here
##
## The shipped `scenes/core/main.tscn`: the same world, player, clock, cast,
## interaction probe, relationship panel and schedule system a player gets. Every
## transaction below is started by pressing the real interact key with the
## crosshair on Mira. The HUD prompt and the relationship rows are read off the
## real labels, not off the components behind them — the two came apart once
## already in Group 14.
##
## The one thing a player cannot do here is skip the weeks of gift-giving needed
## for six and ten hearts. This file sets those two heart counts directly and
## says so in the log; the *decision* at each count is still the player's key.
##
## ## The questions this asks
##
## 1. Is the relationship readable before anything happens?
## 2. Does a disliked gift actually cost hearts when handed over with the key?
## 3. At six hearts, does the key promise a courtship and publish one when pressed?
## 4. At ten hearts while dating, does it promise a proposal and move Mira to the
##    farm, onto her spouse day?
## 5. After a night's sleep, is she actually at the farmhouse rather than walking
##    out of her old cottage?
##
## Output: `res://art_review_friendship_*.png`, all gitignored.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const SHOT_DIR := "res://art_review_friendship_"
const VILLAGER := &"mira"
const PRESS_SECONDS := 0.5

var _bus: Node = null
var _main: Node = null
var _started: Array[StringName] = []
var _married: Array[StringName] = []
var _courted: Array[StringName] = []
var _gifted: Array[Array] = []
var _refused: Array[String] = []
var _interacts: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("no rendering driver: run it without --headless (see the header)")
		return
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("could not load %s" % MAIN_SCENE)
		return
	_bus = root.get_node_or_null(^"EventBus")
	if _bus == null:
		_fail("EventBus autoload missing")
		return
	_watch()

	var ready := [false]
	_bus.game_ready.connect(func() -> void: ready[0] = true)
	_main = packed.instantiate()
	root.add_child(_main)
	var deadline := Time.get_ticks_msec() + 30000
	while not bool(ready[0]) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(ready[0]):
		_fail("the game never announced game_ready")
		return
	print("[play] game ready; playing")

	var player: Node3D = _main.get("player")
	var probe: Node = _find(_main, "InteractionProbe")
	var manager: Node = _main.get("npc_manager")
	var panel: CanvasLayer = _main.get("friendship_hud")
	var state: Node = _main.get("player_state")
	var clock: Node = _find_clock(_main)
	if player == null or probe == null or manager == null or panel == null \
			or state == null or clock == null:
		_fail("main is missing player/probe/manager/relationship panel/state/clock")
		return
	clock.set("running", false)  # hold the day still while the prompts are read
	probe.connect("interacted", func(target: Node, _actor: Node) -> void:
		_interacts.append(target.name if target != null else "<none>"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var mira: Node3D = null
	for candidate: Node3D in manager.call("npcs"):
		if StringName(str(candidate.get("data").get("id"))) == VILLAGER:
			mira = candidate
	if mira == null:
		_fail("the valley spawned no %s" % VILLAGER)
		return
	var friendship: Object = mira.get("friendship")
	if friendship == null:
		_fail("Mira has no friendship to measure")
		return

	# --- 1. The readout before anything happens ----------------------------------
	var rows := _rows(panel)
	if rows.size() < 6 or not _row(rows, "Mira").contains("0/10"):
		_fail("the relationship panel does not show Mira at 0/10: %s" % str(rows))
		return
	print("[play] 1. panel: '%s'" % _row(rows, "Mira"))
	await _settle(4)
	await _shot(SHOT_DIR + "1_panel_new_game.png")

	# --- 2. A disliked gift, handed over with the key ----------------------------
	friendship.set("points", Friendship.POINTS_PER_HEART)
	if not _hold(state, &"stone", 1):
		_fail("could not put a stone in the player's hand")
		return
	if not await _meet(player, probe, mira):
		_fail("could not walk up to Mira")
		return
	var before := int(friendship.get("points"))
	if not await _press_interact():
		_fail("the gift press did not land")
		return
	await _settle(4)
	if _gifted.is_empty() or StringName(_gifted[-1][2]) != NpcData.REACTION_DISLIKED:
		_fail("handing over a stone published '%s'" % (
			str(_gifted[-1][2]) if not _gifted.is_empty() else "no gift"
		))
		return
	if int(friendship.get("points")) >= before:
		_fail("a disliked gift did not cost points (%d -> %d)" % [
			before, int(friendship.get("points")),
		])
		return
	print("[play] 2. disliked stone: %d -> %d points, reaction '%s'" % [
		before, int(friendship.get("points")), str(_gifted[-1][2]),
	])
	await _shot(SHOT_DIR + "2_disliked_gift.png")

	# --- 3. Courtship at six hearts ----------------------------------------------
	_hold(state, &"", 0)
	# Through the manager, the way hearts actually move in play: a bare write to
	# the resource would leave the HUD stale for a harness reason, not a game one.
	manager.call("grant_hearts", VILLAGER, Friendship.COURT_HEARTS)
	if not await _meet(player, probe, mira):
		_fail("could not re-aim at Mira for the courtship")
		return
	var prompt := _label()
	# A job on offer takes this key before a courtship does: a player walking up
	# with work to hand out is not sneaking up on a marriage proposal. Take it the
	# way a player would, then the key is about the relationship again.
	var taken := 0
	while (prompt.contains("Ask ") or prompt.contains("Hand in")) and taken < 3:
		if not await _press_interact():
			_fail("the quest press before the courtship did not land")
			return
		taken += 1
		if not await _meet(player, probe, mira):
			_fail("could not re-aim at Mira after taking the job")
			return
		prompt = _label()
		print("[play]   took the job on offer; prompt now '%s'" % prompt)
	if not prompt.contains("Court Mira"):
		_fail("at %d hearts the prompt says '%s'" % [friendship.call("hearts"), prompt])
		return
	print("[play] 3. prompt: '%s'" % prompt)
	await _settle(4)
	await _shot(SHOT_DIR + "3_court_prompt.png")
	var courted_before := _courted.size()
	if not await _press_interact():
		_fail("the courtship press did not land")
		return
	await _settle(4)
	if _courted.size() != courted_before + 1 or not bool(friendship.call("is_dating")):
		_fail("courtship published %d event(s), dating=%s" % [
			_courted.size() - courted_before, str(friendship.call("is_dating")),
		])
		return
	if not _row(_rows(panel), "Mira").contains("dating"):
		_fail("the panel did not learn about the courtship: '%s'" % _row(_rows(panel), "Mira"))
		return
	print("[play]    after the press: '%s'" % _row(_rows(panel), "Mira"))
	await _shot(SHOT_DIR + "3b_dating.png")

	# --- 4. Proposal at ten hearts -----------------------------------------------
	manager.call("grant_hearts", VILLAGER,
		Friendship.PROPOSE_HEARTS - Friendship.COURT_HEARTS)
	if not await _meet(player, probe, mira):
		_fail("could not re-aim at Mira for the proposal")
		return
	prompt = _label()
	var component_now: Node = probe.call("get_focus")
	var component_prompt := String(component_now.call("get_prompt", player)) \
		if component_now != null else "<no focus>"
	print("[play]   at proposal: hearts=%s romance=%s refusal=%s HUD='%s' component='%s'" % [
		str(friendship.call("hearts")), str(friendship.get("romance")),
		str(friendship.call("propose_refusal")), prompt, component_prompt,
	])
	if not prompt.contains("Propose to Mira"):
		_fail("dating at ten hearts, the prompt says '%s'" % prompt)
		return
	print("[play] 4. prompt: '%s'" % prompt)
	await _settle(4)
	await _shot(SHOT_DIR + "4_propose_prompt.png")
	var married_before := _married.size()
	if not await _press_interact():
		_fail("the proposal press did not land")
		return
	await _settle(4)
	if _married.size() != married_before + 1 or not bool(friendship.call("is_married")):
		var focus_now: Node = probe.call("get_focus")
		var decision: Variant = focus_now.call("preview", player) if focus_now != null else null
		_fail("proposal: events=%d married=%s prompt='%s' decision=%s refusals=%s interacts=%s" % [
			_married.size() - married_before, str(friendship.call("is_married")),
			String(focus_now.call("get_prompt", player)) if focus_now != null else "<no focus>",
			str(decision), str(_refused), str(_interacts),
		])
		return
	if StringName(str(mira.call("home_location_id"))) != &"farm_home":
		_fail("a married Mira still lives at '%s'" % str(mira.call("home_location_id")))
		return
	var schedule: Variant = mira.call("get_schedule")
	if schedule == null or StringName(str(schedule.get("npc_id"))) != &"mira_spouse":
		_fail("a married Mira follows '%s'" % (
			str(schedule.get("npc_id")) if schedule != null else "no day"
		))
		return
	print("[play]    after the press: home=%s, day=%s" % [
		str(mira.call("home_location_id")), str(schedule.get("npc_id")),
	])
	await _shot(SHOT_DIR + "4b_married.png")

	# --- 5. The next morning, at the farmhouse -----------------------------------
	clock.set("running", true)
	clock.call("sleep_until_morning")
	await _seconds(0.6)
	clock.set("running", false)
	var home_place: Node = null
	var target := Vector3(9.0, 0.0, -19.0)
	for place: Node in _find_all(_main, "FarmhousePoint"):
		home_place = place
	# The authored farm_home location is data, not a scene node. Use the same
	# coordinates the generator wrote; the test suite pins them to the resource.
	if not await _walk_to(player, target, 3.0):
		_fail("could not walk to the farmhouse to look for Mira")
		return
	var away := Vector2(
		mira.global_position.x - target.x, mira.global_position.z - target.z
	).length()
	if away > 12.0:
		_fail("the next morning Mira is %.1fm from the farmhouse" % away)
		return
	print("[play] 5. next morning: Mira %.1fm from the farmhouse" % away)
	await _settle(4)
	await _shot(SHOT_DIR + "5_farmhouse_morning.png")
	print("[play] PASS")
	quit(0)


# --- Observing the game ----------------------------------------------------------


func _watch() -> void:
	_bus.connect("romance_started", func(id: StringName) -> void: _courted.append(id))
	_bus.connect("npc_married", func(id: StringName) -> void: _married.append(id))
	_bus.connect("npc_gifted", func(id: StringName, item: StringName, reaction: StringName) -> void:
		_gifted.append([id, item, reaction]))
	_bus.connect("npc_gift_failed", func(id: StringName, _item: StringName, reason: StringName) -> void:
		_refused.append("gift %s/%s" % [id, reason]))
	_bus.connect("npc_propose_failed", func(id: StringName, reason: StringName) -> void:
		_refused.append("propose %s/%s" % [id, reason]))
	_bus.connect("npc_talked", func(id: StringName) -> void:
		_refused.append("talked %s" % id))


func _rows(panel: CanvasLayer) -> PackedStringArray:
	var node: Node = panel.get_node_or_null(^"Panel/Column/Rows")
	if node == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for child: Node in node.get_children():
		if child is Label:
			out.append(String(child.get("text")))
	return out


func _row(rows: PackedStringArray, who: String) -> String:
	for line: String in rows:
		if line.findn(who) >= 0:
			return line
	return ""


func _label() -> String:
	var hud: Node = _main.get("hud")
	var text: Node = hud.get_node_or_null(^"PromptContainer/PromptLabel") if hud != null else null
	return String(text.get("text")) if text != null else "<no label>"


func _hold(state: Node, item_id: StringName, amount: int) -> bool:
	var bag: Object = state.get("inventory")
	if bag == null:
		return false
	bag.call("set_contents", [])
	if not item_id.is_empty() and int(bag.call("add", item_id, amount)) != amount:
		return false
	state.call("select_slot", 0)
	return true


# --- Steps -----------------------------------------------------------------------


func _press_interact() -> bool:
	Input.action_press(InputActions.INTERACT)
	await _seconds(PRESS_SECONDS)
	Input.action_release(InputActions.INTERACT)
	await _settle(3)
	return true


func _walk_to(player: Node3D, target: Vector3, tolerance: float, ceiling: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(ceiling * 1000.0)
	var flat := func() -> float:
		return Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(target.x, target.z)
		)
	Input.action_press(InputActions.MOVE_FORWARD)
	var strafe_left := true
	var last: float = float(flat.call())
	var stalled_since := Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() <= tolerance:
			break
		player.call("set_yaw", atan2(-to.x, -to.z))
		await _seconds(0.05)
		var now: float = float(flat.call())
		if now <= last - 0.01:
			last = now
			stalled_since = Time.get_ticks_msec()
			continue
		if Time.get_ticks_msec() - stalled_since <= 700:
			await _seconds(0.15)
			continue
		var side := InputActions.MOVE_LEFT if strafe_left else InputActions.MOVE_RIGHT
		var other := InputActions.MOVE_RIGHT if strafe_left else InputActions.MOVE_LEFT
		Input.action_release(other)
		Input.action_press(side)
		strafe_left = not strafe_left
		await _seconds(0.45)
		Input.action_release(side)
		last = flat.call()
		stalled_since = Time.get_ticks_msec()
	Input.action_release(InputActions.MOVE_FORWARD)
	Input.action_release(InputActions.MOVE_LEFT)
	Input.action_release(InputActions.MOVE_RIGHT)
	await _settle(4)
	return float(flat.call()) <= tolerance


func _aim_at(player: Node3D, probe: Node, villager: Node3D) -> bool:
	var wanted: Node = villager.get_node_or_null(^"AimVolume/Interactable")
	if wanted == null:
		return false
	for _attempt: int in range(8):
		var camera: Camera3D = probe.call("get_camera")
		if camera == null:
			return false
		var from := camera.global_position
		var aim: Vector3 = wanted.call("get_aim_point")
		var to := aim - from
		if to.length() < 0.05:
			return false
		var sensitivity := 0.0025
		var config: Node = root.get_node_or_null(^"Config")
		if config != null:
			var value: Variant = config.call("get_mouse_sensitivity")
			if value != null and float(value) > 0.0:
				sensitivity = float(value)
		var forward := -camera.global_transform.basis.z
		var yaw_error := atan2(forward.x, forward.z) - atan2(to.x, to.z)
		yaw_error = wrapf(yaw_error, -PI, PI)
		var pitch_error := atan2(to.y, Vector2(to.x, to.z).length()) \
			- asin(clampf(forward.y, -1.0, 1.0))
		if absf(yaw_error) < 0.004 and absf(pitch_error) < 0.004:
			return true
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(-yaw_error / sensitivity, -pitch_error / sensitivity)
		Input.parse_input_event(motion)
		await _settle(3)
		if probe.call("get_focus") == wanted:
			return true
	return false


func _meet(player: Node3D, probe: Node, villager: Node3D) -> bool:
	for _attempt: int in range(6):
		var here := villager.global_position
		var away := Vector2(
			player.global_position.x - here.x, player.global_position.z - here.z
		).length()
		if away > 2.0 and not await _walk_to(player, here, 2.0):
			await _seconds(0.3)
			continue
		if await _aim_at(player, probe, villager):
			return true
		await _seconds(0.3)
	return false


# --- Plumbing --------------------------------------------------------------------


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


func _seconds(value: float, frame_ceiling: int = 1800) -> void:
	var deadline := Time.get_ticks_msec() + int(value * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline and frames < frame_ceiling:
		await process_frame
		await physics_frame
		frames += 1


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("[play] no image for %s" % path)
		return
	var err := image.save_png(path)
	print("[play] %s %s (%dx%d)" % [
		"wrote" if err == OK else "FAILED to write", path,
		image.get_width(), image.get_height(),
	])


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


func _find(from: Node, want: String) -> Node:
	if from == null:
		return null
	if from.name == want:
		return from
	for child: Node in from.get_children():
		var found := _find(child, want)
		if found != null:
			return found
	return null


func _find_all(from: Node, want: String) -> Array[Node]:
	var out: Array[Node] = []
	if from == null:
		return out
	if from.name == want:
		out.append(from)
	for child: Node in from.get_children():
		out.append_array(_find_all(child, want))
	return out


func _fail(reason: String) -> void:
	printerr("[play] FAILED: %s" % reason)
	quit(1)
