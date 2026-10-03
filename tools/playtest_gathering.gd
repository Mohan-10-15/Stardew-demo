extends SceneTree
## Plays Group 12 in the real game and photographs it, so "the tests pass" and
## "it works when a person plays it" stop being the same claim.
##
## Run (needs a real rendering driver, so NOT --headless):
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_gathering.gd
##
## ## What is real here
##
## The whole shipped stack: `scenes/core/main.tscn` boots itself, so the world, the
## player, the clock, the HUD and the gathering service are the ones a player gets.
## The only things this file does that a player cannot are:
##
## - hold keys down and release them on a schedule, which is all a key is;
## - move the mouse by an exact number of pixels, which is also all a mouse is;
## - take a screenshot.
##
## Nothing here calls `GatheringService.gather`, `ResourceNode.hit` or
## `Inventory.add`. Every swing is a real `interact` press read by the real
## [InteractionProbe], and every pickup is a real walk over a real rigid body.
##
## ## Why a tool rather than a test case
##
## A headless test proves the rules. It cannot tell you that the tree you are looking
## at is the tree the crosshair is on, that the log that fell is visible, or that the
## pile you walked over went *into the bag you can see*. Those are questions about
## pictures. Four PNGs answer them; a hundred assertions do not.
##
## Output: `res://art_review_gathering_*.png`, all gitignored.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const NODE_REGISTRY := "res://scripts/gathering/resource_node_registry.gd"
const TARGET := &"oak"
## Screenshots go beside the crop ones. A screenshot of a review is not a game asset.
const SHOT_DIR := "res://art_review_gathering_"

## Held long enough for a 0.35 s chop to finish several times over. The probe
## restarts a hold on release, so this is a real press-and-let-go rhythm rather than
## one continuous stream of swings.
const PRESS_SECONDS := 0.55


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("could not load %s" % MAIN_SCENE)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i: int in range(12):
		await process_frame

	var player: Node3D = main.get("player")
	var probe: Node = _find(player, "InteractionProbe")
	var service: Node = main.get("gathering_service")
	var state: Node = main.get("player_state")
	var field: Node = _find(main.get("world"), "ResourceField")
	if player == null or probe == null or service == null or state == null or field == null:
		_fail("main scene came up without a player/probe/service/state/field")
		return
	var bag: Resource = state.get("inventory")
	var bar: Resource = state.get("hotbar")

	# Mouse look only runs while the cursor is captured, and a `--script` run has no
	# window to click, so capture is set the way the game sets it when the player
	# presses play. Without this the aim step below silently does nothing — which is
	# the failure mode of every scripted mouse-look harness ever written.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Listen for the gathering channel and print it. A swing that does nothing is the
	# one failure a screenshot cannot show, and the refusal reason is the only thing
	# that says which one it was.
	var bus := root.get_node_or_null(^"EventBus")
	if bus != null:
		bus.gathering_failed.connect(
			func(id: StringName, verb: StringName, reason: StringName) -> void:
				print("[play]   refused: %s (%s, %s)" % [reason, verb, id])
		)
		bus.resource_hit.connect(
			func(id: StringName, left: int, total: int) -> void:
				print("[play]   hit %s: %d/%d left" % [id, left, total])
		)
		bus.resource_depleted.connect(
			func(id: StringName, where: Vector3) -> void:
				print("[play]   DEPLETED %s at %s" % [id, str(where)])
		)
		bus.resource_collected.connect(
			func(id: StringName, amount: int) -> void:
				print("[play]   collected %d %s" % [amount, id])
		)

	var target: Node3D = _nearest_node(field, TARGET, player.global_position)
	if target == null:
		_fail("no %s in the valley to chop" % TARGET)
		return
	print("[play] target %s at %s, player at %s" % [target.name, target.global_position, player.global_position])

	# --- 1. The valley as a new game opens it ------------------------------------
	await _settle(20)
	await _shot(SHOT_DIR + "1_spawn.png")

	# --- 2. Pick up the axe with the real hotbar key -----------------------------
	# Key event rather than `Input.action_press`, because the hotbar answers in
	# `_unhandled_input` and `action_press` never delivers one.
	var axe_slot := _slot_of(bar, &"axe")
	if axe_slot < 0:
		_fail("a new game has no axe in the bag")
		return
	await _tap_key(_keycode_for_slot(axe_slot))
	await _settle(6)
	print("[play] hotbar selected slot %d, tool action = %s" % [
		axe_slot, bar.call("get_selected_tool_action"),
	])

	# --- 3. Walk up to the tree and put the crosshair on it -----------------------
	if not await _walk_to(player, target.global_position, 2.2):
		_fail("could not walk to the tree")
		return
	if not await _aim_at(player, probe, target):
		_fail("could not aim at the tree with real mouse motion")
		return
	var focus: Node = probe.call("get_focus")
	print("[play] prompt reads: %s" % String(focus.call("get_prompt", player)))
	await _settle(4)
	await _shot(SHOT_DIR + "2_prompt.png")

	# --- 4. Chop it with the real interact key -----------------------------------
	var needed := int(target.call("hits_required", 1))
	var swings := 0
	while not bool(target.get("depleted")) and swings < needed + 3:
		Input.action_press(&"interact")
		await _seconds(PRESS_SECONDS)
		Input.action_release(&"interact")
		await _settle(3)
		swings += 1
		print("[play] press %d -> hits_taken=%s focus=%s prompt=%s" % [
			swings,
			str(target.get("hits_taken")),
			str(probe.call("get_focus").get("name") if probe.call("get_focus") != null else "nothing"),
			str(probe.call("get_focus").call("get_prompt", player)) if probe.call("get_focus") != null else "",
		])
	print("[play] %d keypresses, depleted=%s" % [swings, str(target.get("depleted"))])
	if not bool(target.get("depleted")):
		_fail("the tree survived %d presses of the interact key" % swings)
		return
	var drops: Array = service.call("get_drops")
	print("[play] %d pile(s) on the ground" % drops.size())
	if drops.is_empty():
		_fail("the tree felled and left nothing to pick up")
		return

	# Caught mid-fall: the whole point of the rigid body is that the wood does not
	# teleport into the bag, so the shot has to be taken before it lands.
	await _seconds(0.15)
	await _shot(SHOT_DIR + "3_felled.png")
	var pile: Node = drops[0]
	var pile_id: StringName = StringName(pile.get("item_id"))
	var pile_amount := int(pile.get("amount"))
	var pile_pos: Vector3 = pile.global_position
	print("[play] pile: %d %s at %s" % [pile_amount, pile_id, str(pile_pos)])

	# --- 5. Walk over the wood ----------------------------------------------------
	var wood_before := int(bag.call("count", pile_id))
	if not await _walk_to(player, pile_pos, 0.2, 6.0):
		_fail("could not walk onto the wood")
		return
	await _seconds(0.5)
	var wood_after := int(bag.call("count", pile_id))
	print("[play] bag %s: %d -> %d (promised %d)" % [pile_id, wood_before, wood_after, pile_amount])
	await _shot(SHOT_DIR + "4_collected.png")
	if wood_after != wood_before + pile_amount:
		_fail("walked over %d %s and the bag went to %d" % [pile_amount, pile_id, wood_after])
		return

	# --- 6. And the refusal still reads ------------------------------------------
	# Walk back to the stump and swing at nothing, because a refused press that says
	# nothing is the failure this system is most often reported for.
	#
	# Retried, and the aim result checked, because the first version trusted it. Walking
	# back lands the player between the stump and the next tree over, the crosshair
	# settles on the neighbour, the press fells a birch nobody asked it to, and the
	# "is the focus null?" guard then crashed the harness with `get_focus()` on Nil —
	# two bugs from one unchecked call. A harness that walks into a neighbour's tree and
	# cannot tell the difference is not verifying anything.
	var aimed := false
	if await _walk_to(player, target.global_position, 2.2):
		for attempt: int in range(4):
			if await _aim_at(player, probe, target):
				aimed = true
				break
			await _settle(8)
		if not aimed:
			# Say *why* before failing. "Could not aim at it" covers four different
			# faults — a stump with no aim point, a camera that will not pitch far
			# enough, terrain in the way, a neighbour stealing the focus — and picking
			# between them by re-running is how a harness burns an afternoon.
			var wanted: Node = target.get_node_or_null(^"AimVolume/Interactable")
			var camera: Camera3D = probe.call("get_camera")
			var got: Node = probe.call("get_focus")
			print("[play] aim failed: dist=%.2f aim_point=%s camera=%s focus=%s wanted=%s" % [
				player.global_position.distance_to(target.global_position),
				str(wanted.call("get_aim_point")) if wanted != null else "none",
				str(camera.global_position) if camera != null else "none",
				str(got.get("name")) if got != null else "nil",
				str(wanted.get("name")) if wanted != null else "none",
			])
	if not aimed:
		_fail("walked back to the stump and could not put the crosshair on it")
		return
	var focus_now: Node = probe.call("get_focus")
	if focus_now == null:
		_fail("aimed at the stump but the probe reports no focus at all")
		return
	var stump_prompt := String(focus_now.call("get_prompt", player))
	print("[play] stump prompt: %s" % stump_prompt)
	if not stump_prompt.contains("Regrowing"):
		_fail("a felled tree's stump does not say it is regrowing; it says '%s'" % stump_prompt)
		return
	await _shot(SHOT_DIR + "5_stump.png")
	var wood_now := int(bag.call("count", pile_id))
	Input.action_press(&"interact")
	await _seconds(PRESS_SECONDS)
	Input.action_release(&"interact")
	await _settle(3)
	if int(bag.call("count", pile_id)) != wood_now:
		_fail("swinging at a stump produced wood")
		return
	if probe.call("get_focus") == null:
		_fail("swinging at a stump took the focus off it entirely")
		return
	print("[play] refused press left the prompt as: %s" % String(
		probe.call("get_focus").call("get_prompt", player)
	))

	# --- 7. The other two verbs, same loop ----------------------------------------
	# Chopping one tree proves the plumbing, not the content: `mine` and `forage` take
	# different paths through the service (a tool check, no tool check, durability or
	# none), and a group that only ever exercised `chop` would ship two verbs nobody
	# had walked. Stone and wild berry are chosen because a new game can reach both
	# with the starter loadout — no granted items, no waiting out a week of income.
	# `rock` and `berry_bush` are the *node* ids; `stone` and `wild_berry` are the
	# things the first drafts of this line asked for, and asking for those returned
	# "no stone in the valley" from a valley full of rocks. A node id and an item id
	# that read alike is exactly the sort of thing that gets asserted into a comment
	# as fact.
	if not await _gather_one(player, probe, service, bag, bar, field, &"rock", &"pickaxe", "6_mine"):
		return
	if not await _gather_one(player, probe, service, bag, bar, field, &"berry_bush", &"", "7_forage"):
		return

	print("[play] OK")
	quit(0)


## Walk to one node of [param node_id], work it with the real keys, and collect
## whatever it leaves on the ground. Shared by the three verbs so a fix to one of
## them cannot quietly break the others.
##
## [param tool_id] empty means "no tool", which is a real case and not a shrug:
## forage is picked with hands, and the held pickaxe must not be a reason to refuse a
## berry bush.
func _gather_one(player: Node3D, probe: Node, service: Node, bag: Resource, bar: Resource,
		field: Node, node_id: StringName, tool_id: StringName, tag: String) -> bool:
	var node: Node3D = _nearest_node(field, node_id, player.global_position)
	if node == null:
		_fail("no %s in the valley" % node_id)
		return false
	if not tool_id.is_empty():
		var slot := _slot_of(bar, tool_id)
		if slot < 0:
			_fail("the starter loadout has no %s" % tool_id)
			return false
		await _tap_key(_keycode_for_slot(slot))
		await _settle(6)
		print("[play] %s: holding %s (slot %d), action=%s" % [
			tag, tool_id, slot, str(bar.call("get_selected_tool_action")),
		])
	else:
		print("[play] %s: nothing selected, gathering %s by hand" % [tag, node_id])

	print("[play] %s: %s at %s" % [tag, node.name, str(node.global_position)])
	if not await _walk_to(player, node.global_position, 2.2):
		_fail("%s: could not walk to the %s" % [tag, node_id])
		return false
	if not await _aim_at(player, probe, node):
		_fail("%s: could not aim at the %s" % [tag, node_id])
		return false
	var focus: Node = probe.call("get_focus")
	if focus == null:
		_fail("%s: the crosshair found nothing on a %s" % [tag, node_id])
		return false
	print("[play] %s prompt: %s" % [tag, String(focus.call("get_prompt", player))])
	await _settle(4)
	await _shot(SHOT_DIR + tag + "_prompt.png")

	var swings := 0
	while not bool(node.get("depleted")) and swings < 14:
		Input.action_press(&"interact")
		await _seconds(PRESS_SECONDS)
		Input.action_release(&"interact")
		await _settle(3)
		swings += 1
	if not bool(node.get("depleted")):
		_fail("%s: the %s survived %d presses" % [tag, node_id, swings])
		return false

	var drops: Array = service.call("get_drops")
	if drops.is_empty():
		_fail("%s: the %s was worked and left nothing to pick up" % [tag, node_id])
		return false
	var pile: Node = drops[-1]
	var pile_id: StringName = StringName(pile.get("item_id"))
	var pile_amount := int(pile.get("amount"))
	print("[play] %s: %d keypresses -> %d %s dropped" % [tag, swings, pile_amount, pile_id])

	await _seconds(0.4)
	var before := int(bag.call("count", pile_id))
	if not await _walk_to(player, pile.global_position, 0.2, 6.0):
		_fail("%s: could not walk onto the %s" % [tag, pile_id])
		return false
	await _seconds(0.6)
	var after := int(bag.call("count", pile_id))
	print("[play] %s: bag %s %d -> %d" % [tag, pile_id, before, after])
	await _shot(SHOT_DIR + tag + "_collected.png")
	if after != before + pile_amount:
		_fail("%s: walked over %d %s and the bag went to %d" % [tag, pile_amount, pile_id, after])
		return false
	return true


# --- Steps ---------------------------------------------------------------------

## Walks the player toward [param target] with the real movement keys held down.
##
## Returns whether it got there. Yaw is set from the heading rather than fed through
## the mouse, because walking into a tree while the harness fights the camera for
## control is a harness bug, not a game bug — and the aim step that follows uses the
## real mouse path.
func _walk_to(player: Node3D, target: Vector3, tolerance: float, ceiling: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(ceiling * 1000.0)
	var flat := func() -> float:
		return Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(target.x, target.z)
		)
	var last: float = flat.call()
	var stalled_since := Time.get_ticks_msec()
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() < deadline:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() <= tolerance:
			break
		# Turn first, then walk: the movement basis is the aim heading, so walking
		# before turning sends the player off at forty-five degrees.
		player.call("set_yaw", atan2(-to.x, -to.z))
		await _seconds(0.05)
		var now: float = flat.call()
		if now > last - 0.01:
			# Not getting closer. Give up on this walk rather than spend the rest of
			# the budget pushing a player into a boulder — the step is normally small
			# enough that two in a row means something is in the way.
			if Time.get_ticks_msec() - stalled_since > 1500:
				break
			await _seconds(0.2)
		else:
			last = now
			stalled_since = Time.get_ticks_msec()
	Input.action_release(&"move_forward")
	await _settle(4)
	return float(flat.call()) <= tolerance


## Turns the camera onto [param target] with real mouse-motion events.
##
## Closed loop rather than one computed nudge: the camera is a spring arm with
## occlusion pull-in, so a single large motion lands somewhere near the target and
## not exactly on it. Re-measures until the probe agrees.
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
		var sensitivity := _mouse_sensitivity(player)
		if sensitivity <= 0.0:
			sensitivity = 0.0025
		var forward := -camera.global_transform.basis.z
		var yaw_error := atan2(forward.x, forward.z) - atan2(to.x, to.z)
		# Signed wrap: an error just over PI is a nudge the other way, not a spin.
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
	return probe.call("get_focus") == wanted


func _mouse_sensitivity(player: Node3D) -> float:
	# Read the same way the controller does, so the harness and the game agree on
	# how far a pixel turns the camera.
	var config: Node = self.root.get_node_or_null(^"Config")
	if config == null:
		return 0.0
	var value: Variant = config.call("get_mouse_sensitivity")
	return float(value) if value != null else 0.0


## The hotbar slot holding [param item_id], by search. Hard-coding "the axe is 4"
## is asserting the loadout's order, which is not what this tool is checking.
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


## A real key press and release, delivered as an event.
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


## Settles for [param frames] frames. Both halves, because the camera rig and the
## drops both live on the physics tick and a render-only wait catches them mid-step.
func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame
		await physics_frame


## Waits for wall-clock time.
##
## A held swing is [member Interactable.hold_seconds] of accumulated process delta and
## a headless-ish frame is about a millisecond of real time, so a frame count is not a
## duration. With a ceiling, so a wedged engine fails the tool instead of hanging it.
func _seconds(value: float, frame_ceiling: int = 900) -> void:
	var deadline := Time.get_ticks_msec() + int(value * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline and frames < frame_ceiling:
		await process_frame
		await physics_frame
		frames += 1


## Saves the viewport to [param path].
func _shot(path: String) -> void:
	# Two frames after a settled world: the first composites, the second is the
	# composited result. Grabbing on the first gives a half-updated framebuffer often
	# enough to be worth two lines.
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