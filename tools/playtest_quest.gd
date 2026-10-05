extends SceneTree
## Plays Group 15 in the real game and photographs it, so "the tests pass" and "it works
## when a person plays it" stop being the same claim.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_quest.gd
##
## ## What is real here
##
## The whole shipped stack: `scenes/core/main.tscn` boots itself, so the world, the player,
## the clock, the HUDs and the quest tracker are the ones a player gets. Every acceptance,
## every conversation and every hand-in is a real `interact` press read by the real
## [InteractionProbe]. Nothing here calls `QuestService.accept()` or `QuestService.turn_in()`.
##
## ## No granted items
##
## The talking job is deliberately the one this harness plays end to end: Odette asks the
## player to speak to Halda, which needs nothing planted, nothing chopped and nothing bought.
## A playtest that reaches into the bag is testing the harness. The collect job is taken
## as well, because "the tracker counts things up" is a claim worth seeing with real wood
## in the bag - but it is played as far as one tree gets a player, not all twenty logs.
##
## ## The five questions this asks
##
## 1. Is the tracker absent when there is nothing to track, rather than an empty box?
## 2. Does a villager with work offer it, in the prompt the player actually reads?
## 3. Does the row appear on acceptance, with the objective and a tally?
## 4. Does the tally move when the player does the thing, through the real gathering?
## 5. Does a finished job leave the list, and pay?

const MAIN_SCENE := "res://scenes/core/main.tscn"
const NODE_REGISTRY := "res://scripts/gathering/resource_node_registry.gd"
const SHOT_DIR := "res://art_review_quest_"
const PRESS_SECONDS := 0.5

const TALK_JOB_GIVER := &"odette"
const TALK_JOB_TARGET := &"halda"
const TALK_JOB := &"q_odette_first_frost"
const WOOD_JOB_GIVER := &"fen"
const WOOD_JOB := &"q_fen_firewood"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("could not load %s" % MAIN_SCENE)
		return

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
	var probe: Node = _find(player, "InteractionProbe")
	var state: Node = main.get("player_state")
	var manager: Node = main.get("npc_manager")
	var quests: Node = main.get("quest_service")
	var tracker: Node = main.get("quest_tracker")
	var field: Node = _find(main.get("world"), "ResourceField")
	var gathering: Node = main.get("gathering_service")
	if player == null or probe == null or state == null or manager == null \
			or quests == null or tracker == null or field == null or gathering == null:
		_fail("main scene came up without player/probe/state/npcs/quests/tracker/field")
		return
	var bag: Resource = state.get("inventory")
	var bar: Resource = state.get("hotbar")
	var wallet: Resource = state.get("wallet")

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Print the whole quest channel. A press that does nothing is the one failure a
	# screenshot cannot show, and the refusal reason is the only thing that says which
	# one it was.
	var accepted: Array[String] = []
	var accept_failures: Array[StringName] = []
	var turned_in: Array[String] = []
	var turn_in_failures: Array[StringName] = []
	var progress: Array[String] = []
	bus.quest_accepted.connect(func(id: StringName, giver: StringName) -> void:
		accepted.append(String(id))
		print("[play]   accepted '%s' from %s" % [id, giver])
	)
	bus.quest_accepted_failed.connect(func(id: StringName, reason: StringName) -> void:
		accept_failures.append(reason)
		print("[play]   accept refused: '%s' (%s)" % [reason, id])
	)
	bus.quest_turned_in.connect(func(id: StringName, giver: StringName) -> void:
		turned_in.append(String(id))
		print("[play]   TURNED IN '%s' at %s" % [id, giver])
	)
	bus.quest_turned_in_failed.connect(func(id: StringName, npc: StringName, reason: StringName) -> void:
		turn_in_failures.append(reason)
		print("[play]   hand-in refused: '%s' (%s at %s)" % [reason, id, npc])
	)
	bus.quest_progress_changed.connect(func(id: StringName, now: int, need: int) -> void:
		progress.append("%s %d/%d" % [id, now, need])
		print("[play]   progress: %s %d/%d" % [id, now, need])
	)

	# --- 1. A new game has no jobs, and no box -----------------------------------
	# An always-visible empty panel in the corner is a piece of UI every player learns to
	# look straight past, so "nothing to track" has to be nothing on screen.
	await _settle(20)
	print("[play] tracker with no jobs: visible=%s rows=%s" % [
		str(_tracker_visible(tracker)), str(_tracker_rows(tracker)),
	])
	await _shot(SHOT_DIR + "1_spawn.png")
	if _tracker_visible(tracker) or not _tracker_rows(tracker).is_empty():
		_fail("a new game with no jobs is already showing '%s'" % str(_tracker_rows(tracker)))
		return

	# The two titles, read from the service rather than hard-coded, so the harness breaks
	# when a quest is renamed instead of quietly asserting against stale copy.
	var talk_title := String(quests.call("title_of", TALK_JOB))
	var wood_title := String(quests.call("title_of", WOOD_JOB))
	print("[play] playing '%s' (%s) and '%s' (%s)" % [
		TALK_JOB, talk_title, WOOD_JOB, wood_title,
	])

	# --- 2. Odette offers the job -------------------------------------------------
	var giver := _npc(manager, TALK_JOB_GIVER)
	if giver == null:
		_fail("no %s in the cast" % TALK_JOB_GIVER)
		return
	if not await _meet(player, probe, giver):
		_fail("could not walk up to %s and put the crosshair on them" % TALK_JOB_GIVER)
		return
	var offer_prompt := _prompt(probe, player)
	var offer_label := _label(main)
	print("[play] at %s: component says '%s', HUD shows '%s'" % [
		TALK_JOB_GIVER, offer_prompt, offer_label,
	])
	await _settle(4)
	await _shot(SHOT_DIR + "2_offer_prompt.png")
	# The title, not the id: the prompt is player-facing copy, and a harness that asserted
	# on `q_odette_first_frost` would fail on a build that says "First Frost" perfectly.
	if not offer_label.contains(talk_title):
		_fail("the HUD does not offer '%s': '%s'" % [talk_title, offer_label])
		return

	var accepted_before := accepted.size()
	if not await _press_interact():
		_fail("the press to take the job did not land")
		return
	await _seconds(0.4)
	if accepted.size() <= accepted_before:
		_fail("pressed the key on a villager with work and no job was taken: '%s'" % offer_label)
		return

	# --- 3. The row appears -------------------------------------------------------
	var rows := _tracker_rows(tracker)
	print("[play] tracker after accepting: visible=%s rows=%s" % [
		str(_tracker_visible(tracker)), str(rows),
	])
	await _shot(SHOT_DIR + "3_accepted.png")
	if rows.size() != 1:
		_fail("took one job and the tracker drew %d rows: %s" % [rows.size(), str(rows)])
		return
	if not rows[0].contains("Halda"):
		_fail("the row does not say who to ask: '%s'" % rows[0])
		return
	if not rows[0].contains("0/1"):
		_fail("a job the player has not started reads '%s'" % rows[0])
		return

	# --- 4. Doing it, with the real key -------------------------------------------
	var target := _npc(manager, TALK_JOB_TARGET)
	if target == null:
		_fail("no %s in the cast" % TALK_JOB_TARGET)
		return
	if not await _meet(player, probe, target):
		_fail("could not walk up to %s" % TALK_JOB_TARGET)
		return
	var talk_prompt := _prompt(probe, player)
	print("[play] at %s: prompt '%s', HUD '%s'" % [
		TALK_JOB_TARGET, talk_prompt, _label(main),
	])
	if not talk_prompt.begins_with("Talk to"):
		_fail("standing next to %s the prompt says '%s'" % [TALK_JOB_TARGET, talk_prompt])
		return
	if not await _press_interact():
		_fail("the press to speak to %s did not land" % TALK_JOB_TARGET)
		return
	await _seconds(0.4)
	rows = _tracker_rows(tracker)
	print("[play] tracker after asking: %s" % str(rows))
	await _shot(SHOT_DIR + "4_asked.png")
	if rows.size() != 1 or not rows[0].contains("1/1"):
		_fail("spoke to %s and the row reads %s" % [TALK_JOB_TARGET, str(rows)])
		return
	# "ready" here means the objective is done, not that the job is finished: the player
	# still has to walk back to %s to be paid. Asserting the word is here on purpose —
	# an earlier version of this harness expected the row to stay unmarked until the
	# hand-in, which would mean the player is told nothing while carrying a finished job.
	if not rows[0].contains("ready"):
		_fail("the objective is done and the row does not say so: '%s'" % rows[0])
		return

	# --- 5. Handing it back --------------------------------------------------------
	if not await _meet(player, probe, giver):
		_fail("could not walk back to %s" % TALK_JOB_GIVER)
		return
	var handin_prompt := _prompt(probe, player)
	var handin_label := _label(main)
	var gold_before := int(wallet.get("gold"))
	print("[play] back at %s: prompt '%s', HUD '%s', gold %d" % [
		TALK_JOB_GIVER, handin_prompt, handin_label, gold_before,
	])
	await _settle(4)
	await _shot(SHOT_DIR + "5_handin_prompt.png")
	if not handin_label.contains(talk_title):
		_fail("the HUD does not offer to finish '%s': '%s'" % [talk_title, handin_label])
		return
	var paid_before := turned_in.size()
	if not await _press_interact():
		_fail("the press to hand the job in did not land")
		return
	await _seconds(0.5)
	var gold_after := int(wallet.get("gold"))
	print("[play] after the hand-in: turned_in=%s gold %d -> %d, tracker visible=%s rows=%s" % [
		str(turned_in), gold_before, gold_after,
		str(_tracker_visible(tracker)), str(_tracker_rows(tracker)),
	])
	await _shot(SHOT_DIR + "6_paid.png")
	if turned_in.size() <= paid_before:
		_fail("the press did not pay out: '%s'" % handin_label)
		return
	if gold_after <= gold_before:
		_fail("a job paid %d -> %d" % [gold_before, gold_after])
		return
	if _tracker_visible(tracker) or not _tracker_rows(tracker).is_empty():
		_fail("a paid job is still on the tracker: %s" % str(_tracker_rows(tracker)))
		return

	# --- 6. A collect job, counted from real wood ----------------------------------
	# The tracker showing a tally is only half the claim; the other half is that the tally
	# is right, and the only way to know that is to gather something the player gathered.
	var wood_giver := _npc(manager, WOOD_JOB_GIVER)
	if wood_giver == null:
		_fail("no %s in the cast" % WOOD_JOB_GIVER)
		return
	if not await _meet(player, probe, wood_giver):
		_fail("could not walk up to %s" % WOOD_JOB_GIVER)
		return
	print("[play] at %s: prompt '%s', HUD '%s'" % [
		WOOD_JOB_GIVER, _prompt(probe, player), _label(main),
	])
	if not _label(main).contains(wood_title):
		_fail("the HUD does not offer '%s': '%s'" % [wood_title, _label(main)])
		return
	var wood_before := accepted.size()
	if not await _press_interact():
		_fail("the press to take the firewood job did not land")
		return
	await _seconds(0.4)
	if accepted.size() <= wood_before:
		_fail("could not take '%s'" % WOOD_JOB)
		return
	rows = _tracker_rows(tracker)
	print("[play] tracker with the firewood job: %s" % str(rows))
	if rows.size() != 1 or not rows[0].contains("Wood"):
		_fail("the firewood row does not say what is wanted: %s" % str(rows))
		return

	if not await _fell_one_tree(player, probe, gathering, field, bag, bar):
		return
	await _seconds(0.4)
	rows = _tracker_rows(tracker)
	var wood_in_bag := int(bag.call("count", &"wood"))
	print("[play] tracker after felling a tree: %s (bag holds %d wood)" % [str(rows), wood_in_bag])
	await _shot(SHOT_DIR + "7_wood.png")
	if rows.size() != 1 or rows[0].contains("0/"):
		_fail("felled a tree and the row still reads %s" % str(rows))
		return
	if wood_in_bag <= 0:
		_fail("felled a tree and the bag holds no wood")
		return

	print("[play] accepted=%s refused=%s turned_in=%s hand_in_failures=%s progress=%s" % [
		str(accepted), str(accept_failures), str(turned_in),
		str(turn_in_failures), str(progress),
	])
	print("[play] OK")
	quit(0)


# --- Steps ---------------------------------------------------------------------


## Holds the axe, fells the nearest oak, and walks over what falls.
##
## One tree, deliberately: the question is whether the tracker counts what the player
## really gathered, and twenty logs is a minute of swinging for an answer that one tree
## gives. The rest of the job is left unfinished on purpose, so the run also ends with a
## job visibly in progress rather than a clean slate.
func _fell_one_tree(player: Node3D, probe: Node, gathering: Node, field: Node,
		bag: Resource, bar: Resource) -> bool:
	var tree := _nearest_node(field, &"oak", player.global_position)
	if tree == null:
		_fail("no oak in the valley")
		return false
	var slot := _slot_of(bar, &"axe")
	if slot < 0:
		_fail("the starter loadout has no axe")
		return false
	await _tap_key(_keycode_for_slot(slot))
	await _settle(6)
	print("[play] holding %s (slot %d), action=%s" % [
		&"axe", slot, str(bar.call("get_selected_tool_action")),
	])
	if not await _walk_to(player, tree.global_position, 2.2):
		_fail("could not walk to the oak")
		return false
	if not await _aim_at(player, probe, tree):
		_fail("could not aim at the oak")
		return false
	await _settle(4)
	await _shot(SHOT_DIR + "7a_chop_prompt.png")

	var swings := 0
	while not bool(tree.get("depleted")) and swings < 14:
		Input.action_press(&"interact")
		await _seconds(PRESS_SECONDS)
		Input.action_release(&"interact")
		await _settle(3)
		swings += 1
	if not bool(tree.get("depleted")):
		_fail("the oak survived %d presses" % swings)
		return false
	print("[play] oak felled in %d presses" % swings)

	var drops: Array = gathering.call("get_drops")
	if drops.is_empty():
		_fail("the oak left nothing to pick up")
		return false
	var pile: Node = drops[-1]
	var pile_id: StringName = StringName(pile.get("item_id"))
	var pile_amount := int(pile.get("amount"))
	print("[play] %d %s on the ground" % [pile_amount, pile_id])
	await _seconds(0.4)
	if not await _walk_to(player, pile.global_position, 0.2, 6.0):
		_fail("could not walk onto the %s" % pile_id)
		return false
	await _seconds(0.8)
	print("[play] bag %s: %d" % [pile_id, int(bag.call("count", pile_id))])
	return true


## One press-and-let-go of the real interact action.
func _press_interact() -> bool:
	Input.action_press(&"interact")
	await _seconds(PRESS_SECONDS)
	Input.action_release(&"interact")
	await _settle(3)
	return true


## Walks the player toward [param target] with the real movement keys held down.
##
## Yaw is set from the heading rather than fed through the mouse, because walking into a
## fence while the harness fights the camera for control is a harness bug, not a game bug.
## Walks *around* things rather than at them, exactly as `playtest_gathering.gd` does.
##
## [param live] re-reads the target every tick, for the villagers: walking once to a fixed
## position is not "arriving" when the villager keeps walking their patrol.
func _walk_to(player: Node3D, target: Vector3, tolerance: float, ceiling: float = 30.0,
		live: Callable = Callable()) -> bool:
	var deadline := Time.get_ticks_msec() + int(ceiling * 1000.0)
	var goal := func() -> Vector3:
		return live.call() if live.is_valid() else target
	var flat := func() -> float:
		var point: Vector3 = goal.call()
		return Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(point.x, point.z)
		)
	var last: float = flat.call()
	var stalled_since := Time.get_ticks_msec()
	var blocked_by := ""
	var strafe_left := true
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() < deadline:
		var to: Vector3 = goal.call() - player.global_position
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
		blocked_by = _blocking(player, maxf(now, 0.5))
		var side := &"move_left" if strafe_left else &"move_right"
		var other := &"move_right" if strafe_left else &"move_left"
		Input.action_release(other)
		Input.action_press(side)
		strafe_left = not strafe_left
		print("[play]   wedged %.2fm short of %s (blocked by %s); stepping %s" % [
			now, str(goal.call()), blocked_by, String(side),
		])
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
		print("[play] walk gave up: %s -> %s, still %.2fm away, blocked by %s" % [
			str(player.global_position), str(target), remaining,
			blocked_by if not blocked_by.is_empty() else _blocking(player, maxf(remaining, 0.5)),
		])
	return remaining <= tolerance


## A one-line description of whatever solid thing is in the player's way.
func _blocking(player: Node3D, radius: float) -> String:
	var world := player.get_world_3d()
	if world == null:
		return "no world"
	var space := world.direct_space_state
	if space == null:
		return "no physics space"
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius, 0.5)
	query.shape = shape
	query.transform = Transform3D(Basis(), player.global_position + Vector3(0.0, 0.9, 0.0))
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_bodies = true
	var hits: Array[Dictionary] = space.intersect_shape(query, 6)
	var names: Array[String] = []
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider")
		names.append(String(collider.name) if collider != null else "?")
	return ", ".join(names) if not names.is_empty() else "nothing in the way"


## Turns the camera onto [param target] with real mouse-motion events.
##
## Closed loop rather than one computed nudge: the camera is a spring arm with occlusion
## pull-in, so a single large motion lands near the target and not exactly on it.
func _aim_at(player: Node3D, probe: Node, target: Node3D) -> bool:
	var wanted := target.get_node_or_null(^"AimVolume/Interactable")
	if wanted == null:
		_fail("%s has no interaction component" % target.name)
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
		var sensitivity := _mouse_sensitivity(player)
		if sensitivity <= 0.0:
			sensitivity = 0.0025
		var forward := -camera.global_transform.basis.z
		var yaw_error := atan2(forward.x, forward.z) - atan2(to.x, to.z)
		yaw_error = wrapf(yaw_error, -PI, PI)
		var flat := Vector2(to.x, to.z).length()
		var pitch_error := atan2(to.y, flat) - asin(clampf(forward.y, -1.0, 1.0))
		if absf(yaw_error) < 0.004 and absf(pitch_error) < 0.004:
			return true
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(-yaw_error / sensitivity, -pitch_error / sensitivity)
		Input.parse_input_event(motion)
		await _settle(3)
		if probe.call("get_focus") == wanted:
			return true
	if probe.call("get_focus") != wanted:
		print("[play]   aim gave up: wanted %s, player %s, target %s" % [
			str(wanted.get("name")), str(player.global_position),
			str(target.global_position),
		])
	return false


## Walks up to [param villager] and puts the crosshair on them, retrying while they walk.
##
## The tolerance is tight (1.3 m, not 2.0) because this harness crosses the whole valley
## rather than talking to whoever is nearest: a villager standing on the far side of the
## farm gets "aimed at" from just outside their aim volume, and the run reports a broken
## interaction range when the problem was that the harness stopped walking. The second
## half re-walks even when the distance already looks fine, so a first attempt that
## stopped one step short is corrected instead of retried in place.
func _meet(player: Node3D, probe: Node, villager: Node3D, tolerance: float = 1.3) -> bool:
	var live := func() -> Vector3:
		var volume := villager.get_node_or_null(^"AimVolume")
		return (volume as Node3D).global_position if volume is Node3D \
			else villager.global_position
	for attempt: int in range(6):
		var here: Vector3 = live.call()
		var away := Vector2(
			player.global_position.x - here.x, player.global_position.z - here.z
		).length()
		if away > tolerance or attempt > 0:
			print("[play]   approach %d: %s is %.2fm away" % [attempt + 1, villager.name, away])
			if not await _walk_to(player, here, tolerance, 30.0, live):
				await _seconds(0.3)
				continue
		if await _aim_at(player, probe, villager):
			return true
		await _seconds(0.3)
	return false


## The prompt the crosshair is currently reading, or a note that nothing is focused.
func _prompt(probe: Node, player: Node) -> String:
	var focus: Node = probe.call("get_focus")
	if focus == null:
		return "<nothing focused>"
	return String(focus.call("get_prompt", player))


## What the player's screen actually says, read off the HUD's label.
##
## The player does not call [method Interactable.get_prompt]; they read a string drawn by
## `InteractionHUD`. Asking the component instead is how a stale label survives a whole
## test suite, so the label is read here and the two printed side by side.
func _label(main: Node) -> String:
	var hud: Node = main.get("hud")
	if hud == null:
		return "<no hud>"
	var text: Node = hud.get_node_or_null(^"PromptContainer/PromptLabel")
	if text == null:
		return "<no label>"
	return String(text.get("text"))


## What the quest tracker's rows say, as the player sees them.
##
## Read off the real [CanvasLayer] the game spawned, for the same reason the prompt label
## is: a tracker that computes the right line and never draws it is a tracker nobody has.
func _tracker_rows(tracker: Node) -> Array[String]:
	var out: Array[String] = []
	var rows := tracker.get_node_or_null(^"Panel/Column/Rows")
	if rows == null:
		return out
	for row: Node in rows.get_children():
		var label := row.get_node_or_null(^"Label")
		out.append("" if label == null else String(label.get("text")))
	return out


func _tracker_visible(tracker: Node) -> bool:
	var box := tracker.get_node_or_null(^"Panel")
	return box != null and bool(box.get("visible"))


func _mouse_sensitivity(player: Node3D) -> float:
	var config: Node = self.root.get_node_or_null(^"Config")
	if config == null:
		return 0.0
	var value: Variant = config.call("get_mouse_sensitivity")
	return float(value) if value != null else 0.0


## The hotbar slot holding [param item_id], by search.
func _slot_of(bar: Resource, item_id: StringName) -> int:
	var bag: Resource = bar.get("inventory")
	for i: int in range(int(bag.call("slot_count"))):
		var stack: Resource = bag.call("get_slot", i)
		if stack != null and StringName(stack.get("id")) == item_id:
			return i
	return -1


func _keycode_for_slot(slot: int) -> int:
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	return int(keys[clampi(slot, 0, keys.size() - 1)])


## A real key press and release, delivered as an event. The hotbar answers in
## `_unhandled_input`, which `Input.action_press` never reaches.
func _tap_key(code: int) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(2)
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await _settle(2)


# --- Plumbing ------------------------------------------------------------------


## The villager whose id is [param id], or null.
func _npc(manager: Node, id: StringName) -> Node3D:
	for candidate: Node3D in manager.call("npcs"):
		if StringName(candidate.get("data").get("id")) == id:
			return candidate
	return null


## The nearest un-felled node of [param id] to [param from], or null.
func _nearest_node(field: Node, id: StringName, from: Vector3) -> Node3D:
	var registry: GDScript = load(NODE_REGISTRY)
	var data: Resource = registry.call("get_node", id)
	if data == null:
		return null
	var found: Array = field.call("nodes_of", data)
	var best: Node3D = null
	var best_distance := INF
	for candidate: Node3D in found:
		if bool(candidate.get("depleted")):
			continue
		var d := Vector2(
			candidate.global_position.x - from.x, candidate.global_position.z - from.z
		).length()
		if d < best_distance:
			best_distance = d
			best = candidate
	return best


## Settles for [param frames] frames. Both halves, because the camera rig and the drops
## both live on the physics tick.
func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


## Waits for wall-clock time. A frame is about a millisecond of real time, so a frame
## count is not a duration. With a ceiling, so a wedged engine fails the tool rather than
## hanging it.
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


func _fail(reason: String) -> void:
	printerr("[play] FAILED: %s" % reason)
	quit(1)
