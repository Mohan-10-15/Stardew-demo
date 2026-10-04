extends SceneTree
## Plays Group 14 in the real game and photographs it, so "the tests pass" and
## "it works when a person plays it" stop being the same claim.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_npc.gd
##
## ## What is real here
##
## The whole shipped stack: `scenes/core/main.tscn` boots itself, so the world, the
## player, the clock, the HUD, the gathering service and the six villagers are the ones
## a player gets. The only things this file does that a player cannot are hold keys down
## and release them on a schedule, move the mouse by an exact number of pixels, and take
## a screenshot.
##
## Nothing here calls `NpcManager.talk` or `NpcManager.give_gift`. Every hello and every
## present is a real `interact` press read by the real [InteractionProbe], and the present
## itself is foraged out of a real berry bush by walking over a real rigid body — no
## granted items, because a playtest that reaches into the bag is testing the harness.
##
## ## The four questions this asks
##
## 1. Can a player *find* a villager and get a prompt at all?
## 2. Does the prompt say the right thing — "Talk to Mira", then "Give the Wild Berry"
##    the moment a present is in hand — and does it keep saying it?
## 3. Does one press do exactly one thing: hello, then present, then a refusal that says
##    why and takes nothing?
## 4. Does the standing actually move, and does the bag actually empty?
##
## Output: `res://art_review_npc_*.png`, all gitignored.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const NODE_REGISTRY := "res://scripts/gathering/resource_node_registry.gd"
const SHOT_DIR := "res://art_review_npc_"

## Long enough for a press-and-let-go on the interact action, which the probe restarts on
## release. A hold, not a tap: a villager's aim volume is entered by a ray, and the same
## rhythm a player uses to swing at a tree is the one that greets a person.
const PRESS_SECONDS := 0.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("could not load %s" % MAIN_SCENE)
		return

	# Wait for the game to say it is ready, not for a number of frames. See the same note
	# in `playtest_gathering.gd`: the early-input version of this harness typed at the
	# game before the hotbar existed and failed much later for the wrong reason.
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
	var field: Node = _find(main.get("world"), "ResourceField")
	var gathering: Node = main.get("gathering_service")
	if player == null or probe == null or state == null or manager == null \
			or field == null or gathering == null:
		_fail("main scene came up without a player/probe/state/npc manager/field/gathering")
		return
	var bag: Resource = state.get("inventory")
	var bar: Resource = state.get("hotbar")

	# Mouse look only runs while the cursor is captured, and a `--script` run has no
	# window to click, so capture is set the way the game sets it when the player presses
	# play. Without it the aim step silently does nothing.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Print the whole NPC channel. A press that does nothing is the one failure a
	# screenshot cannot show, and the refusal reason is the only thing that says which
	# one it was.
	var talked: Array[StringName] = []
	var talk_failures: Array[StringName] = []
	var gifted: Array[String] = []
	var gift_failures: Array[String] = []
	var tier_changes: Array[String] = []
	bus.npc_talked.connect(func(id: StringName) -> void:
		talked.append(id)
		print("[play]   talked to %s" % id)
	)
	bus.npc_talk_failed.connect(func(id: StringName, reason: StringName) -> void:
		talk_failures.append(reason)
		print("[play]   talk refused: %s (%s)" % [reason, id])
	)
	bus.npc_gifted.connect(func(id: StringName, item_id: StringName, reaction: StringName) -> void:
		gifted.append("%s -> %s (%s)" % [item_id, id, reaction])
		print("[play]   GAVE %s to %s (%s)" % [item_id, id, reaction])
	)
	bus.npc_gift_failed.connect(func(id: StringName, item_id: StringName, reason: StringName) -> void:
		gift_failures.append(reason)
		print("[play]   gift refused: %s (%s, %s)" % [reason, item_id, id])
	)
	bus.npc_friendship_changed.connect(func(id: StringName, hearts: int, tier: String) -> void:
		tier_changes.append("%s: %d hearts (%s)" % [id, hearts, tier])
		print("[play]   standing changed: %s %d hearts (%s)" % [id, hearts, tier])
	)

	var cast: Array = manager.call("npcs")
	if cast.is_empty():
		_fail("the valley spawned no villagers")
		return
	for member: Node3D in cast:
		print("[play] villager %s '%s' at %s" % [
			str(member.get("data").get("id")), str(member.get("data").get("display_name")),
			str(member.global_position),
		])

	# --- 1. The valley as a new game opens it ------------------------------------
	await _settle(20)
	await _shot(SHOT_DIR + "1_spawn.png")

	# --- 2. Forage the presents, because a new game has none -----------------------
	# The villager content loves wild berries and parsnips. A new game can reach neither
	# from its own pocket, and granting one would test the harness rather than the game, so
	# this walks to berry bushes and picks them up off the ground like a player would. The
	# alternative — reaching into the bag — is the one shortcut that makes a playtest lie.
	#
	# Two, not one. A gift that empties the hand leaves the *next* press as a hello, so a
	# single berry cannot test a refusal at all; the first run of this harness pressed
	# again with an empty hand, got `npc_talked`, and very nearly filed that as "villagers
	# never refuse anything".
	var berry: StringName = &"wild_berry"
	for pick: int in range(2):
		if not await _forage_one(player, probe, gathering, field, bag, berry, &"berry_bush"):
			return
		print("[play] foraging pass %d done, %d %s in the bag" % [pick + 1, int(bag.call("count", berry)), str(berry)])
	var slot := _slot_of(bar, berry)
	if slot < 0:
		_fail("foraged a %s and it is not in the bag" % berry)
		return
	await _tap_key(_keycode_for_slot(slot))
	await _settle(6)
	print("[play] hotbar slot %d holds %s" % [slot, String(bar.call("describe_selected"))])

	# --- 3. Find somebody and say hello --------------------------------------------
	var villager: Node3D = _nearest_npc(manager, player.global_position)
	if villager == null:
		_fail("no villager to talk to")
		return
	var villager_id: StringName = StringName(villager.get("data").get("id"))
	print("[play] nearest villager %s at %s" % [villager_id, str(villager.global_position)])

	# With a present in hand the prompt must be a present, not a hello. Checked before
	# talking, because this is the case that reads wrong: the villager stands there
	# accepting gifts all day and the player can never hand one over.
	#
	# The *label* is read rather than `get_prompt()`, deliberately. Asking the component
	# what it would say proves the component is right; reading the pixels proves the
	# player is being told. The two came apart — the component was right while the label
	# still promised a gift the press had stopped giving — which is the whole reason this
	# harness takes screenshots at all.
	if not await _meet(player, probe, villager):
		_fail("could not walk up to %s and put the crosshair on them" % villager_id)
		return
	var held_prompt := _prompt(probe, player)
	var held_label := _label(main)
	print("[play] in hand: component says '%s', HUD shows '%s'" % [held_prompt, held_label])
	await _settle(4)
	await _shot(SHOT_DIR + "2_gift_prompt.png")
	if not held_prompt.begins_with("Give the"):
		_fail("holding a %s the prompt says '%s'" % [berry, held_prompt])
		return
	if not held_label.contains("Give the"):
		_fail("the HUD is showing '%s' while the player holds a %s" % [held_label, berry])
		return

	var points_before := _friendship(villager)
	var berries_before := int(bag.call("count", berry))
	print("[play] standing before: %s" % points_before)
	if not await _press_interact():
		_fail("the interact press for the present did not land")
		return
	await _seconds(0.4)
	var berries_after := int(bag.call("count", berry))
	print("[play] bag %s: %d -> %d | standing: %s" % [berry, berries_before, berries_after, _friendship(villager)])
	await _shot(SHOT_DIR + "3_gifted.png")
	if berries_after != berries_before - 1:
		_fail("pressed the key to give a %s and the bag went %d -> %d" % [berry, berries_before, berries_after])
		return
	if gifted.is_empty():
		_fail("the present left the bag and nothing published npc_gifted")
		return
	if points_before == _friendship(villager):
		_fail("a present was given and %s's standing did not move" % villager_id)
		return

	# The label has to notice. The gift spent Mira's day, so "Give the Wild Berry" became
	# a promise the key would break — and until this was fixed the label kept making it,
	# because the HUD only ever redrew itself when the crosshair moved.
	var spent_label := _label(main)
	print("[play] after the gift the HUD shows '%s'" % spent_label)
	if spent_label.contains("Give the"):
		_fail("Mira is full for the day and the HUD still reads '%s'" % spent_label)
		return

	# --- 4. The refusal still reads ------------------------------------------------
	# One press, one question at a time: the second present is refused, said hello instead,
	# and says *why* — on the label, and on [signal EventBus.npc_gift_failed], because a
	# refused present that leaves no trace is the failure this system is most often
	# reported for. The bag must not move.
	var still_slot := _slot_of(bar, berry)
	if still_slot >= 0:
		await _tap_key(_keycode_for_slot(still_slot))
		await _settle(4)
	if not await _meet(player, probe, villager):
		_fail("could not re-aim at %s for the second present" % villager_id)
		return
	var second_prompt := _prompt(probe, player)
	var second_note := _note(probe, player)
	print("[play] second present: prompt '%s', note '%s', HUD '%s'" % [
		second_prompt, second_note, _label(main),
	])
	var refused_before := int(bag.call("count", berry))
	var hello_before := talked.size()
	var refusals_before := gift_failures.size()
	if not await _press_interact():
		_fail("the interact press for the refusal did not land")
		return
	await _seconds(0.4)
	var refused_after := int(bag.call("count", berry))
	var refusal := gift_failures[-1] if not gift_failures.is_empty() else "<none>"
	print("[play] second press: refused as '%s', bag %d -> %d, HUD now '%s'" % [
		refusal, refused_before, refused_after, _label(main),
	])
	await _shot(SHOT_DIR + "4_refused.png")
	if gift_failures.size() <= refusals_before:
		_fail("a refused present published nothing: no npc_gift_failed, so a sound or a toast has nothing to play")
		return
	if refused_after != refused_before:
		_fail("a refused present still took the %s out of the bag" % berry)
		return
	if gift_failures[-1] != &"already_gifted_today":
		_fail("a second present on the same day was refused as '%s', not already_gifted_today" % gift_failures[-1])
		return
	if talked.size() <= hello_before:
		_fail("a refused present took the villager's hello away with it")
		return
	if second_note.is_empty():
		_fail("the second present was refused and the prompt never said why")
		return
	if not _label(main).contains(second_note):
		_fail("the note '%s' is not on screen; the HUD shows '%s'" % [second_note, _label(main)])
		return
	if probe.call("get_focus") == null:
		_fail("a refused present took the crosshair off the villager entirely")
		return

	# --- 5. Empty hand, same key, hello ---------------------------------------------
	# The key has to mean "talk" again the moment nothing giftable is in hand, or the
	# player cannot say hello to anybody for the rest of the week.
	var axe_slot := _slot_of(bar, &"axe")
	if axe_slot < 0:
		_fail("the starter loadout has no axe to hold instead")
		return
	await _tap_key(_keycode_for_slot(axe_slot))
	await _settle(6)
	if not await _meet(player, probe, villager):
		_fail("could not re-aim at %s holding a tool" % villager_id)
		return
	var tool_prompt := _prompt(probe, player)
	var tool_label := _label(main)
	print("[play] with a tool: prompt '%s', HUD '%s'" % [tool_prompt, tool_label])
	if not tool_prompt.begins_with("Talk to"):
		_fail("holding a tool the prompt says '%s', which is not a hello" % tool_prompt)
		return
	if tool_label.contains("Give the"):
		_fail("switched to a tool and the HUD still offers a gift: '%s'" % tool_label)
		return
	var talked_before := talked.size()
	if not await _press_interact():
		_fail("the interact press for the hello did not land")
		return
	await _seconds(0.4)
	print("[play] standing after: %s" % _friendship(villager))
	await _shot(SHOT_DIR + "5_talked.png")
	if talked.size() <= talked_before:
		_fail("pressed the key to say hello and nothing published npc_talked")
		return
	if not bool(villager.get("attending")):
		_fail("%s is not attending the conversation" % villager_id)
		return
	var off_by := _facing_error(villager, player)
	print("[play] %s faces %.2f rad from the player" % [villager_id, off_by])
	if off_by > 0.35:
		_fail("%s is %.2f rad off from facing the player" % [villager_id, off_by])
		return

	# --- 6. And the refusal for a hello, same loop -----------------------------------
	# A definition-less villager is the only way to see a `nothing_to_say` in a real game,
	# and the real game has none, so this one check is asserted here rather than staged:
	# every refusal the shipped content can produce has been produced above.
	print("[play] talked=%s gifted=%s refusals=%s tiers=%s" % [
		str(talked), str(gifted), str(gift_failures), str(tier_changes),
	])
	print("[play] OK")
	quit(0)


# --- Steps ---------------------------------------------------------------------


## Forage one [param item_id] out of the nearest [param node_id] and collect it off the
## ground, so the present the player hands over is one the player actually picked up.
func _forage_one(player: Node3D, probe: Node, service: Node, field: Node, bag: Resource,
		item_id: StringName, node_id: StringName) -> bool:
	var bush: Node3D = _nearest_node(field, node_id, player.global_position)
	if bush == null:
		_fail("no %s in the valley" % node_id)
		return false
	print("[play] %s at %s" % [bush.name, str(bush.global_position)])
	if not await _walk_to(player, bush.global_position, 2.2):
		_fail("could not walk to the %s" % node_id)
		return false
	if not await _aim_at(player, probe, bush):
		_fail("could not aim at the %s" % node_id)
		return false
	print("[play] %s prompt: '%s'" % [node_id, _prompt(probe, player)])
	var swings := 0
	while not bool(bush.get("depleted")) and swings < 14:
		if not await _press_interact():
			return false
		swings += 1
	if not bool(bush.get("depleted")):
		_fail("the %s survived %d presses" % [node_id, swings])
		return false
	var drops: Array = service.call("get_drops")
	if drops.is_empty():
		_fail("the %s was worked and left nothing to pick up" % node_id)
		return false
	var pile: Node = drops[-1]
	var amount := int(pile.get("amount"))
	print("[play] %d keypresses -> %d %s dropped" % [swings, amount, str(pile.get("item_id"))])
	await _seconds(0.4)
	var before := int(bag.call("count", item_id))
	if not await _walk_to(player, pile.global_position, 0.2, 6.0):
		_fail("could not walk onto the %s" % item_id)
		return false
	await _seconds(0.6)
	var after := int(bag.call("count", item_id))
	print("[play] bag %s: %d -> %d" % [item_id, before, after])
	if after != before + amount:
		_fail("walked over %d %s and the bag went to %d" % [amount, item_id, after])
		return false
	return true


## One press-and-let-go of the real interact action. Returns whether the press was sent;
## whether it *did* anything is the caller's business, because only the caller knows what
## it was expecting.
func _press_interact() -> bool:
	Input.action_press(&"interact")
	await _seconds(PRESS_SECONDS)
	Input.action_release(&"interact")
	await _settle(3)
	return true


## Walks the player toward [param target] with the real movement keys held down.
##
## Yaw is set from the heading rather than fed through the mouse, because walking into a
## fence while the harness fights the camera for control is a harness bug, not a game
## bug. Walks *around* things rather than at them, exactly as `playtest_gathering.gd`
## does: the valley scatters 146 nodes and a straight line from the spawn to a chosen
## villager crosses one often enough to matter.
##
## [param live] re-reads the target every tick, for the villagers. Walking once to a fixed
## position is not "arriving" when the villager keeps walking their patrol: the player ends
## up where they *were*, the crosshair misses, and the log reads like a broken interaction
## range. The first run of this harness spent half a minute proving exactly that.
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


## A one-line description of whatever solid thing is in the player's way within
## [param radius] of them. Reads the physics server rather than guessing from the walk:
## "the player stopped" and "the player stopped *against a villager*" are the same
## observation until you ask what is actually there.
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
## Re-measures until the probe agrees.
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
		print("[play]   aim gave up: wanted %s, focus is %s, player %s, target %s" % [
			str(wanted.get("name")),
			str(probe.call("get_focus").get("name")) if probe.call("get_focus") != null else "nil",
			str(player.global_position),
			str(target.global_position),
		])
	return false


## Walks up to [param villager] and puts the crosshair on them, retrying while they walk.
##
## Retried rather than walked-to-once because a villager does not stand still: the first
## version walked to where they were, arrived a moment later, found them three metres
## further along their patrol, and reported "aim failed" — which reads like a broken
## interaction range and is really a moving target. A villager wanders within
## [member NpcData.wander_radius]; so does the player.
func _meet(player: Node3D, probe: Node, villager: Node3D, tolerance: float = 2.0) -> bool:
	var live := func() -> Vector3:
		return villager.global_position
	for attempt: int in range(5):
		var here: Vector3 = villager.global_position
		var away := Vector2(player.global_position.x - here.x, player.global_position.z - here.z).length()
		if away > tolerance:
			print("[play]   approach %d: %s is %.2fm away" % [attempt + 1, villager.name, away])
			if not await _walk_to(player, here, tolerance, 30.0, live):
				await _seconds(0.3)
				continue
		if await _aim_at(player, probe, villager):
			return true
		await _seconds(0.3)
	return false


## The prompt the crosshair is currently reading, or a note that nothing is focused.
##
## Reads the probe's *focused* component rather than the villager on purpose: "the prompt
## for a refused press and the prompt for a legal one are the same string" is the failure
## this whole system is built to avoid, and the only way to see it is to read what the
## player is actually looking at.
func _prompt(probe: Node, player: Node) -> String:
	var focus: Node = probe.call("get_focus")
	if focus == null:
		return "<nothing focused>"
	return String(focus.call("get_prompt", player))


## The explanation the focused target offers for not doing the interesting thing, or "".
func _note(probe: Node, player: Node) -> String:
	var focus: Node = probe.call("get_focus")
	if focus == null:
		return ""
	return String(focus.call("get_prompt_note", player))


## What the player's screen actually says, read off the HUD's label.
##
## The player does not call [method Interactable.get_prompt]; they read a string drawn by
## `InteractionHUD`. Asking the component instead is how a stale label survives a whole
## test suite: the component knows the truth, the label does not, and nothing compares
## them. So the label is read here, and the two are printed side by side.
func _label(main: Node) -> String:
	var hud: Node = main.get("hud")
	if hud == null:
		return "<no hud>"
	var text: Node = hud.get_node_or_null(^"PromptContainer/PromptLabel")
	if text == null:
		return "<no label>"
	return String(text.get("text"))


## How far [param villager]'s forward axis is from the direction of [param player].
func _facing_error(villager: Node3D, player: Node3D) -> float:
	var forward := -villager.global_transform.basis.z
	var towards := player.global_position - villager.global_position
	towards.y = 0.0
	if forward.length() < 0.5 or towards.length() < 0.5:
		return PI
	return forward.normalized().angle_to(towards.normalized())


## The villager's standing, in the words the HUD would use.
func _friendship(villager: Node) -> String:
	var friendship: Variant = villager.get("friendship")
	if friendship == null:
		return "no friendship"
	return String(friendship.call("describe"))


func _mouse_sensitivity(player: Node3D) -> float:
	var config: Node = self.root.get_node_or_null(^"Config")
	if config == null:
		return 0.0
	var value: Variant = config.call("get_mouse_sensitivity")
	return float(value) if value != null else 0.0


## The hotbar slot holding [param item_id], by search. Hard-coding "the berry is 4" is
## asserting the loadout's order, which is not what this tool is checking.
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


## The villager nearest to [param from], or null.
func _nearest_npc(manager: Node, from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for candidate: Node3D in manager.call("npcs"):
		var d := Vector2(candidate.global_position.x - from.x, candidate.global_position.z - from.z).length()
		if d < best_distance:
			best_distance = d
			best = candidate
	return best


## The nearest node of [param id] to [param from], or null.
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
		var d := Vector2(candidate.global_position.x - from.x, candidate.global_position.z - from.z).length()
		if d < best_distance:
			best_distance = d
			best = candidate
	return best


## Settles for [param frames] frames. Both halves, because the camera rig and the drops
## both live on the physics tick and a render-only wait catches them mid-step.
func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


## Waits for wall-clock time.
##
## A frame is about a millisecond of real time, so a frame count is not a duration. With a
## ceiling, so a wedged engine fails the tool instead of hanging it.
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