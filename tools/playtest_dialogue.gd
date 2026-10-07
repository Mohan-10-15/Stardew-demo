extends SceneTree
## Plays the conversation in the real game and photographs it, so "32 cases are
## green" and "a player can talk to somebody" stop being the same claim.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_dialogue.gd
##
## ## What is real here
##
## The shipped `scenes/core/main.tscn`: the same world, the same player, the
## clock, the HUD, the villagers walking their schedules and the same dialogue
## panel a player gets. The only things this file does that a player cannot are
## hold keys to a schedule and take a screenshot. Nothing here calls
## `DialogueService.open()` — every conversation is started by pressing the real
## interact key with the crosshair on a person, and every line is moved along by
## real key events on the panel itself.
##
## ## The five questions this asks
##
## 1. Can a player find a villager, take the job their key is offering first,
##    and reach a greeting at all?
## 2. Does her line arrive typed, credited to her name, with the valley holding
##    still — clock stopped, player unable to walk — and does the panel say what
##    to press next?
## 3. Does the first key read the line and the second end the conversation, with
##    the panel gone and the world running again?
## 4. Does a second meeting reach a reply, answer it with a number key, and land
##    the heart and the flag that reply promised?
## 5. Does Escape end a conversation the player walked out of?
##
## Output: `res://art_review_dialogue_*.png`, all gitignored.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const SHOT_DIR := "res://art_review_dialogue_"
const VILLAGER := &"mira"

## A hold, not a tap, on the interact key — the same rhythm a player uses, and
## the one `playtest_npc.gd` already proved reaches the probe.
const PRESS_SECONDS := 0.5

## A clock tick is `seconds_per_day / ticks_per_day` = 5.0 real seconds, and a
## tick is 10 minutes. Waiting two ticks' worth while a conversation is open is
## the difference between "the world is paused" and "not enough time passed to
## tell".
const FROZEN_SECONDS := 11.0

var _bus: Node = null
var _game_state: Node = null
var _main: Node = null
var _talked: Array[StringName] = []
var _started: Array[Array] = []
var _changed: Array[StringName] = []
var _finished: Array[StringName] = []
var _chosen: Array[Array] = []
var _refused: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# `--headless` is the wrong flag for this file, and its failure is silent:
	# the game boots and runs normally — the schedule logs keep arriving — while
	# the first screenshot waits on `frame_post_draw`, which a dummy renderer
	# never posts. Three runs sat there for minutes without reaching a second
	# print. Fail in a second instead.
	if DisplayServer.get_name() == "headless":
		_fail("no rendering driver: run it without --headless (see the header)")
		return
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("could not load %s" % MAIN_SCENE)
		return
	_bus = root.get_node_or_null(^"EventBus")
	_game_state = root.get_node_or_null(^"GameState")
	if _bus == null or _game_state == null:
		_fail("EventBus or GameState autoload missing")
		return

	var announced_ready := [false]
	_bus.game_ready.connect(func() -> void: announced_ready[0] = true)
	_watch_conversation()

	_main = packed.instantiate()
	root.add_child(_main)
	var deadline := Time.get_ticks_msec() + 30000
	while not bool(announced_ready[0]) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(announced_ready[0]):
		_fail("the game never announced EventBus.game_ready")
		return
	print("[play] game ready; playing")

	var player: Node3D = _main.get("player")
	var probe: Node = _main.get_node_or_null(^"InteractionProbe")
	if probe == null:
		probe = _find(player, "InteractionProbe")
	var manager: Node = _main.get("npc_manager")
	var panel: CanvasLayer = _main.get("dialogue_ui")
	var service: Node = _main.get("dialogue_service")
	var clock: Node = _find_clock(_main)
	if player == null or probe == null or manager == null or panel == null \
			or service == null or clock == null:
		_fail("main scene came up without player/probe/npc manager/panel/service/clock")
		return
	if panel.get_node_or_null(^"Panel/Column/NameLabel") == null \
			or panel.get_node_or_null(^"Panel/Column/TextLabel") == null \
			or panel.get_node_or_null(^"Panel/Column/Choices") == null \
			or panel.get_node_or_null(^"Panel/Column/Continue") == null:
		_fail("the generated panel is missing a label, the reply row or the continue hint")
		return

	# Mouse look only runs with the cursor captured, and a `--script` run has no
	# window to click. Without this the aiming step silently does nothing.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var mira: Node3D = null
	for candidate: Node3D in manager.call("npcs"):
		if StringName(str(candidate.get("data").get("id"))) == VILLAGER:
			mira = candidate
	if mira == null:
		_fail("the valley spawned no %s" % VILLAGER)
		return
	var friendship: Variant = mira.get("friendship")
	if friendship == null:
		_fail("%s has no friendship to measure" % VILLAGER)
		return

	# --- 1. Find her, and read what the key is promising --------------------------
	if not await _meet(player, probe, mira):
		_fail("could not walk up to %s and put the crosshair on them" % VILLAGER)
		return
	var component: Node = probe.call("get_focus")
	if component == null:
		_fail("the crosshair is on nothing after the approach")
		return
	var component_prompt := String(component.call("get_prompt", player))
	var hud_prompt := _label()
	print("[play] crosshair on %s: component '%s' / HUD '%s'" % [
		VILLAGER, component_prompt, hud_prompt,
	])
	await _settle(4)
	await _shot(SHOT_DIR + "1_prompt.png")

	# A villager with a job for you puts the job on this key before the greeting
	# does — deliberately, because a job offered behind a greeting is a job the
	# player never discovers. So the greeting is reached the way a player reaches
	# it: take the work, then ask. Found on the first run of this file, which
	# walked up to Mira expecting "Talk to Mira" and was met with
	# "Ask Mira about 'First Harvest'".
	var accepted := 0
	while (hud_prompt.contains("Ask ") or hud_prompt.contains("Hand in")) \
			and accepted < 3:
		if not await _press_interact():
			_fail("the interact press for the quest offer did not land")
			return
		await _settle(4)
		accepted += 1
		print("[play]   press %d, was '%s'" % [accepted, hud_prompt])
		if accepted == 1:
			await _shot(SHOT_DIR + "1b_quest_taken.png")
		if not await _meet(player, probe, mira):
			_fail("could not re-aim at %s after the quest press" % VILLAGER)
			return
		component = probe.call("get_focus")
		if component == null:
			_fail("the crosshair is on nothing after the quest press")
			return
		component_prompt = String(component.call("get_prompt", player))
		hud_prompt = _label()
		print("[play]   now component '%s' / HUD '%s'" % [component_prompt, hud_prompt])
	if not hud_prompt.contains("Talk to"):
		_fail("after %d quest press(es) the HUD says '%s'" % [accepted, hud_prompt])
		return
	if not component_prompt.begins_with("Talk to"):
		_fail("the HUD promises a conversation the component will not give: '%s'" % component_prompt)
		return

	# --- 2. Press it, and read the line ------------------------------------------
	var talks_before := _talked.size()
	var first_opens := _started.size()
	if not await _press_interact():
		_fail("the interact press for the conversation did not land")
		return
	await _settle(4)
	if _started.size() != first_opens + 1:
		_fail("%d conversations opened from one press" % (_started.size() - first_opens))
		return
	if _talked.size() != talks_before + 1:
		_fail("%d greetings from one press" % (_talked.size() - talks_before))
		return
	if not _refused.is_empty():
		_fail("the conversation was refused: '%s'" % str(_refused[-1]))
		return
	var entry_id := StringName(_started[-1][1])
	if entry_id != &"intro":
		_fail("a first meeting opened on '%s' instead of the introduction" % entry_id)
		return
	if not bool(panel.visible) or not bool(_game_state.get("paused")):
		_fail("the press did not open the panel and pause the valley")
		return
	var name_label := panel.get_node_or_null(^"Panel/Column/NameLabel") as Label
	var text_label := panel.get_node_or_null(^"Panel/Column/TextLabel") as Label
	var continue_hint := panel.get_node_or_null(^"Panel/Column/Continue") as Label
	if name_label.text != "Mira":
		_fail("the panel credits '%s'" % name_label.text)
		return
	if not bool(panel.get("_typing")):
		_fail("the line arrived all at once instead of being typed")
		return
	if continue_hint.visible:
		_fail("the panel hints 'continue' while it is still typing")
		return
	await _settle(4)
	await _shot(SHOT_DIR + "2_open.png")
	print("[play] open on '%s': '%s'" % [entry_id, String(panel.get("_full_text"))])

	# --- 3. The valley holds still -------------------------------------------------
	# The pause is the claim a screenshot cannot make. Two ticks' worth of wall
	# clock, during which the clock must not move, the player must not walk, and
	# the person being spoken to must neither wander off nor stop attending. The
	# clock and the walk are then shown to start again the moment the panel
	# closes, so a frozen measurement is not mistaken for a dead system.
	var frozen_at := _stamp(clock)
	var walking := player.global_position
	var standing := mira.global_position
	Input.action_press(InputActions.MOVE_FORWARD)
	await _seconds(FROZEN_SECONDS)
	Input.action_release(InputActions.MOVE_FORWARD)
	await _settle(4)
	var still_at := _stamp(clock)
	var walked := player.global_position.distance_to(walking)
	var wandered := mira.global_position.distance_to(standing)
	var attending := bool(mira.get("attending"))
	print("[play] during %0.1fs held open: clock '%s' -> '%s', player %.3f m, %s %.3f m, attending=%s" % [
		FROZEN_SECONDS, frozen_at, still_at, walked, VILLAGER, wandered, str(attending),
	])
	var broken: Array[String] = []
	if still_at != frozen_at:
		broken.append("the clock kept running: %s -> %s" % [frozen_at, still_at])
	if walked > 0.05:
		broken.append("the player walked %.3f m" % walked)
	if wandered > 0.05:
		broken.append("%s wandered %.3f m" % [VILLAGER, wandered])
	if not attending:
		broken.append("%s stopped attending mid-sentence" % VILLAGER)
	if not broken.is_empty():
		_fail("the conversation was supposed to hold the valley still, but: %s" % "; ".join(broken))
		return

	# --- 4. First key reads, second key says goodbye -------------------------------
	# Which case the first press lands in depends on how far the typewriter got
	# during the eleven-second hold above: a reader who beats it gets a press
	# that finishes the line, and one who does not gets a press that ends the
	# talk. Both are real, so both are exercised — and when the line is already
	# whole the photograph of it is taken before the press, because the press is
	# the one that closes the panel. Found on the run that assumed typing always
	# outlives the hold and reported "the reading press moved past the line".
	var typing := bool(panel.get("_typing"))
	print("[play] the line was %s when the first key arrived" % (
		"still typing" if typing else "already whole"
	))
	if not typing:
		var whole := String(panel.get("_full_text"))
		if text_label.text != whole or whole.is_empty() or not continue_hint.visible:
			_fail("the typewriter finished but the panel does not show it whole with a hint")
			return
		await _shot(SHOT_DIR + "3_reading.png")
	await _tap_key(_interact_key())
	await _settle(4)
	if typing:
		if _finished.size() != 0 or not bool(panel.visible):
			_fail("the reading press moved past a line that was still typing")
			return
		var full := String(panel.get("_full_text"))
		if text_label.text != full or full.is_empty():
			_fail("after the press the label holds %d of %d characters" % [
				text_label.text.length(), full.length(),
			])
			return
		if not continue_hint.visible:
			_fail("no continue hint once the line is whole")
			return
		await _shot(SHOT_DIR + "3_reading.png")
		await _tap_key(_interact_key())
		await _settle(4)
	if _finished.size() != 1:
		_fail("the closing press left %d finishes" % _finished.size())
		return
	if bool(panel.visible) or bool(_game_state.get("paused")):
		_fail("the panel outlived the conversation or kept the valley paused")
		return
	if _talked.size() != 1:
		_fail("the advance presses greeted %d times" % _talked.size())
		return
	await _shot(SHOT_DIR + "4_closed.png")

	# --- 5. The clock runs again ---------------------------------------------------
	var moving_at := _stamp(clock)
	await _seconds(6.5)
	var moved_at := _stamp(clock)
	print("[play] with the panel closed: clock '%s' -> '%s'" % [moving_at, moved_at])
	if moved_at == moving_at:
		_fail("the clock never moved after the conversation ended, so the frozen check above proved nothing")
		return

	# --- 6. A second meeting, and a reply -----------------------------------------
	if not await _meet(player, probe, mira):
		_fail("could not re-aim at %s for the second conversation" % VILLAGER)
		return
	var opens_before := _started.size()
	if not await _press_interact():
		_fail("the second interact press did not land")
		return
	await _settle(4)
	if _started.size() != opens_before + 1:
		_fail("the second press opened %d conversations" % (_started.size() - opens_before))
		return
	var branch := StringName(_started[-1][1])
	if branch != &"story_1":
		_fail("the second meeting opened on '%s', not the reply the content promises" % branch)
		return
	var choices := panel.get_node_or_null(^"Panel/Column/Choices") as VBoxContainer
	if choices.get_child_count() != 2:
		_fail("%d reply buttons for 2 replies" % choices.get_child_count())
		return
	if continue_hint.visible:
		_fail("the panel hints 'continue' while replies are on screen")
		return
	await _settle(4)
	await _shot(SHOT_DIR + "5_replies.png")

	var hearts_before := int(friendship.call("hearts"))
	var taken_before := _chosen.size()
	await _tap_key(KEY_1)
	await _settle(2)
	if int(panel.get("_selected")) != 0:
		_fail("key 1 selected row %d" % int(panel.get("_selected")))
		return
	if _chosen.size() != taken_before:
		_fail("the selection key already took the reply")
		return
	await _tap_key(KEY_ENTER)
	await _settle(4)
	if _chosen.size() != taken_before + 1:
		_fail("the number-keyed reply was not taken")
		return
	if int(_chosen[-1][2]) != 0:
		_fail("reply %s was taken, not reply 1" % str(_chosen[-1][2]))
		return
	var replied_to := StringName(_changed[-1]) if not _changed.is_empty() else &"nothing"
	if replied_to != &"story_2":
		_fail("reply 1 led to '%s' instead of the second beat" % replied_to)
		return
	await _settle(2)
	await _tap_key(_interact_key())
	await _settle(2)
	await _shot(SHOT_DIR + "6_after_reply.png")
	var mid_text := String(text_label.text)
	await _tap_key(_interact_key())
	await _settle(4)
	if _finished.size() != 2:
		_fail("the branching conversation left %d finishes" % _finished.size())
		return
	if bool(panel.visible) or bool(_game_state.get("paused")):
		_fail("the reply did not close the panel")
		return
	var hearts_after := int(friendship.call("hearts"))
	var flag := bool(service.call("has_flag", &"mira_field_secret"))
	print("[play] reply landed: %s hearts %d -> %d, mira_field_secret=%s, last line '%s'" % [
		VILLAGER, hearts_before, hearts_after, str(flag), mid_text,
	])
	if hearts_after != hearts_before + 1:
		_fail("the story beat paid %d hearts, wanted 1" % (hearts_after - hearts_before))
		return
	if not flag:
		_fail("the reply landed no mira_field_secret flag")
		return

	# --- 7. Escape ends it ---------------------------------------------------------
	if not await _meet(player, probe, mira):
		_fail("could not re-aim at %s for the third conversation" % VILLAGER)
		return
	var third := _started.size()
	if not await _press_interact():
		_fail("the third interact press did not land")
		return
	await _settle(4)
	if _started.size() != third + 1:
		_fail("the third press opened %d conversations" % (_started.size() - third))
		return
	var finished_before := _finished.size()
	await _tap_key(KEY_ESCAPE)
	await _settle(4)
	if _finished.size() != finished_before + 1:
		_fail("Escape owed a finish and left %d" % (_finished.size() - finished_before))
		return
	if bool(panel.visible) or bool(_game_state.get("paused")):
		_fail("Escape left the panel on screen or the valley paused")
		return
	if not _refused.is_empty():
		print("[play] a conversation was refused here: %s" % str(_refused[-1]))
	await _settle(4)
	await _shot(SHOT_DIR + "7_escape_closed.png")

	print("[play] talked=%s" % str(_talked))
	print("[play] started=%s" % str(_started))
	print("[play] lines=%s finished=%d chosen=%s" % [str(_changed), _finished.size(), str(_chosen)])
	print("[play] refusals=%s" % str(_refused))
	if not _refused.is_empty():
		_fail("a conversation was refused in a real game: '%s'" % str(_refused[-1]))
		return
	print("[play] OK")
	quit(0)


# --- The conversation channel -------------------------------------------------


func _watch_conversation() -> void:
	_bus.dialogue_started.connect(func(npc_id: StringName, entry_id: StringName) -> void:
		_started.append([npc_id, entry_id])
		print("[play]   dialogue_started %s / %s" % [npc_id, entry_id])
	)
	_bus.npc_talked.connect(func(id: StringName) -> void:
		_talked.append(id)
		print("[play]   npc_talked %s" % id)
	)
	_bus.dialogue_line_changed.connect(func(_npc_id: StringName, entry_id: StringName) -> void:
		_changed.append(entry_id)
		print("[play]   dialogue_line_changed %s" % entry_id)
	)
	_bus.dialogue_finished.connect(func(npc_id: StringName, _entry_id: StringName) -> void:
		_finished.append(npc_id)
		print("[play]   dialogue_finished %s" % npc_id)
	)
	_bus.dialogue_choice_taken.connect(func(npc_id: StringName, entry_id: StringName, index: int) -> void:
		_chosen.append([npc_id, entry_id, index])
		print("[play]   dialogue_choice_taken %s / %s [%d]" % [npc_id, entry_id, index])
	)
	_bus.dialogue_failed.connect(func(npc_id: StringName, reason: StringName) -> void:
		_refused.append(reason)
		print("[play]   DIALOGUE REFUSED %s (%s)" % [reason, npc_id])
	)


# --- Steps ---------------------------------------------------------------------


## One press-and-let-go of the real interact action, as a player would.
func _press_interact() -> bool:
	Input.action_press(InputActions.INTERACT)
	await _seconds(PRESS_SECONDS)
	Input.action_release(InputActions.INTERACT)
	await _settle(3)
	return true


## Walks the player toward [param target] with the real movement keys held down,
## walking around obstacles the way `playtest_npc.gd` does — the valley scatters
## enough scenery that a straight line crosses something often enough to matter.
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
	var strafe_left := true
	Input.action_press(InputActions.MOVE_FORWARD)
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
			Input.action_release(InputActions.MOVE_LEFT)
			Input.action_release(InputActions.MOVE_RIGHT)
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


## Turns the camera onto [param target] with real mouse-motion events, closed
## loop because the camera rig pulls in and a single nudge lands near it rather
## than on it.
func _aim_at(player: Node3D, probe: Node, target: Node3D) -> bool:
	var wanted := target.get_node_or_null(^"AimVolume/Interactable")
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
		var sensitivity := _mouse_sensitivity()
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
	return false


## Walks up to [param villager] and puts the crosshair on them, retrying while
## they walk their patrol — a moving target is not the same as a broken range.
func _meet(player: Node3D, probe: Node, villager: Node3D, tolerance: float = 2.0) -> bool:
	var live := func() -> Vector3:
		return villager.global_position
	for _attempt: int in range(6):
		var here: Vector3 = villager.global_position
		var away := Vector2(player.global_position.x - here.x, player.global_position.z - here.z).length()
		if away > tolerance:
			print("[play]   approach: %s is %.2fm away" % [villager.name, away])
			if not await _walk_to(player, here, tolerance, 30.0, live):
				await _seconds(0.3)
				continue
		if await _aim_at(player, probe, villager):
			return true
		await _seconds(0.3)
	return false


## A real key press and release, delivered as an event. The panel answers in
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


## The interact key's current binding, read from the InputMap so a remap shows
## up here without a code change — same read as `DialogueUI._interact_label`.
func _interact_key() -> int:
	if InputMap.has_action(InputActions.INTERACT):
		for event: InputEvent in InputMap.action_get_events(InputActions.INTERACT):
			if event is InputEventKey:
				var code := (event as InputEventKey).physical_keycode
				if code == 0:
					code = (event as InputEventKey).keycode
				if code != 0:
					return code
	return KEY_E


# --- Reading the screen --------------------------------------------------------


## What the player's screen actually says in the prompt slot. Read off the label
## rather than off the component, because the two came apart once already — see
## `playtest_npc.gd`.
func _label() -> String:
	var hud: Node = _main.get("hud")
	if hud == null:
		return "<no hud>"
	var text: Node = hud.get_node_or_null(^"PromptContainer/PromptLabel")
	if text == null:
		return "<no label>"
	return String(text.get("text"))


## The clock as a string precise enough to notice a tick: date and minute.
func _stamp(clock: Node) -> String:
	var time: Variant = clock.get("time")
	if time == null:
		return "<no clock>"
	return "%d/s%d/d%d %02d:%02d" % [
		int(time.get("year")), int(time.get("season")), int(time.get("day_of_month")),
		int(time.get("hour")), int(time.get("minute")),
	]


func _mouse_sensitivity() -> float:
	var config: Node = root.get_node_or_null(^"Config")
	if config == null:
		return 0.0
	var value: Variant = config.call("get_mouse_sensitivity")
	return float(value) if value != null else 0.0


# --- Plumbing ------------------------------------------------------------------


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


## Waits for wall-clock time, with a ceiling so a wedged engine fails the tool
## instead of hanging it.
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
		"wrote" if err == OK else "FAILED to write", path, image.get_width(), image.get_height(),
	])


## The clock in the tree, found by what it can do rather than by its type name.
##
## `--script` again, exactly as `playtest_schedule.gd` found it: naming the class
## here would compile its whole dependency chain into this tool, and that chain
## reaches the `Log` autoload — which is not a global identifier while a
## `--script` run is still compiling.
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


func _fail(reason: String) -> void:
	printerr("[play] FAILED: %s" % reason)
	quit(1)
