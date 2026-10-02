extends TestSuite
## Whether the shop panel is *actually* modal.
##
## Group 25 regression.
##
## Pausing the tree was supposed to be the whole modal mechanism: one call stops
## the player, the clock and the interaction probe at once, with no new plumbing
## between systems. That reasoning has a hole in it, and the hole is
## `PROCESS_MODE_ALWAYS` — which **inherits down the tree**.
##
## `Main` is ALWAYS, because it has to keep handling input while paused. So the
## player, the probe, the clock and every other body under it are ALWAYS too, and
## `SceneTree.paused` skips nothing at all. The tests that drive `open()` and
## `close()` directly passed, and a real player would still walk out of the shop.
## These cases assert on the *mode*, not on the pause flag, because the flag is
## the thing that lies.

var _rig: Node = null


func is_async() -> bool:
	return true


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func get_cases() -> Array[StringName]:
	return [
		&"a_paused_node_under_an_always_ancestor_still_processes",
		&"the_player_is_actually_pausable",
		&"the_interaction_probe_is_actually_pausable",
		&"opening_the_shop_really_stops_the_player",
	]


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"a_paused_node_under_an_always_ancestor_still_processes":
			return _t_inheritance_is_the_culprit()
		&"the_player_is_actually_pausable":
			return await _t_player_pausable()
		&"the_interaction_probe_is_actually_pausable":
			return await _t_probe_pausable()
		&"opening_the_shop_really_stops_the_player":
			return await _t_shop_stops_player()
	return fail(case, "no case implementation for %s" % case)


## The bug in miniature: the documented claim in the shop panel's comment is false.
##
## Godot resolves `PROCESS_MODE_INHERIT` by walking up to the nearest ancestor
## that sets a mode, so an ALWAYS root silently makes everything below it ALWAYS.
func _t_inheritance_is_the_culprit() -> Dictionary:
	var c := &"a_paused_node_under_an_always_ancestor_still_processes"
	var parent := Node.new()
	parent.process_mode = Node.PROCESS_MODE_ALWAYS
	var child := Node.new()
	# Left at the default, INHERIT.
	var grandchild := Node.new()
	parent.add_child(child)
	child.add_child(grandchild)
	_rig_new(parent)

	if not child.can_process():
		return fail(c, "precondition: the child should inherit ALWAYS")
	if not grandchild.can_process():
		return fail(c, "precondition: the grandchild should inherit too")

	tree.paused = true
	# The whole point: still processable, so pausing changes nothing.
	var running := grandchild.can_process()
	tree.paused = false
	if not running:
		return fail(c, "the tree pause stopped it — inheritance did not propagate as expected")
	return succeeded(c, "INHERIT follows ALWAYS all the way down")


func _t_player_pausable() -> Dictionary:
	var c := &"the_player_is_actually_pausable"
	var main := await _boot_main()
	if main == null:
		return fail(c, "could not boot the main scene")
	var player: PlayerController = main.get("player")
	if player == null:
		return fail(c, "Main did not build a player")
	return _assert_pausable(c, player, "PlayerController")


func _t_probe_pausable() -> Dictionary:
	var c := &"the_interaction_probe_is_actually_pausable"
	var main := await _boot_main()
	if main == null:
		return fail(c, "could not boot the main scene")
	var player: PlayerController = main.get("player")
	var probe := _find_first(player, "InteractionProbe")
	if probe == null:
		probe = _find_scripted(player, "interaction_probe.gd")
	if probe == null:
		return fail(c, "no interaction probe under the player")
	return _assert_pausable(c, probe, "InteractionProbe")


## Boots the real main scene, opens a real shop, and checks the player stopped.
func _t_shop_stops_player() -> Dictionary:
	var c := &"opening_the_shop_really_stops_the_player"
	var main := await _boot_main()
	if main == null:
		return fail(c, "could not boot the main scene")
	var player: Node = main.get("player")
	if player == null:
		return fail(c, "no player on Main")

	var shop: Shop = main.find_child("GeneralStore", true, false)
	if shop == null:
		return fail(c, "no shop in the world")
	var panel := _find_first(tree.root, ^"ShopUI")
	if panel == null:
		return fail(c, "the shop panel is not in the tree")

	# Walk forward and record the body actually moving, to prove the test can
	# detect movement at all. A modal test that passes because the player never
	# moved is worse than no test.
	var start := (player as Node3D).global_position
	_drive_move(player, true)
	await _steps(12)
	var moved := (player as Node3D).global_position.distance_to(start)
	_drive_move(player, false)
	await _steps(6)
	if moved <= 0.0:
		return fail(c, "the player did not move before the shop opened, so the test proves nothing")

	EventBus.shop_opened.emit(shop)
	await _steps(2)
	var before := (player as Node3D).global_position
	_drive_move(player, true)
	await _steps(12)
	var after_open := (player as Node3D).global_position.distance_to(before)
	_drive_move(player, false)

	panel.call("close")
	await _steps(2)

	# Turn about before checking that control came back.
	#
	# The first leg walked the player into the shop counter, so continuing in the
	# same direction after the resume measures a body pressed against a wall — a
	# zero here says nothing about whether input is live. `drive_right` and
	# `drive_left` face opposite ways, so reversing is unambiguous.
	_drive_move(player, false)
	await _steps(4)
	var resumed := (player as Node3D).global_position
	_drive_move(player, true, [&"move_right", &"move_back"])
	await _steps(12)
	var after_close := (player as Node3D).global_position.distance_to(resumed)
	_drive_move(player, false)
	await _steps(4)

	if after_open > moved * 0.5:
		return fail(c, "the player still walked %.2fm with the shop open (it moves %.2fm freely)"
			% [after_open, moved])
	if after_close <= 0.001:
		return fail(c, "the player is still frozen after the shop closed")
	return succeeded(c, "%.2fm free, %.2fm while open, %.2fm after close"
		% [moved, after_open, after_close])


func _assert_pausable(c: StringName, node: Node, label: String) -> Dictionary:
	if node.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return fail(c, "%s has process_mode %d, so it ignores the pause"
			% [label, node.process_mode])
	return succeeded(c, "PAUSABLE")


# --- Fixtures ----------------------------------------------------------------


func _rig_new(node: Node) -> void:
	_reset_rig()
	_rig = Node.new()
	_rig.name = "PauseRig"
	tree.root.add_child(_rig)
	_rig.add_child(node)


## Drops the previous case's tree before the next one builds its own.
##
## `TestSuite.run_all` calls `setup()` and `teardown()` **once for the whole
## suite**, not once per case. A rig freed only in `teardown` therefore stacks up
## across cases, and four booted main scenes means four worlds, four players and
## four shop panels alive at once — the player under test ends up shoved by three
## other players at the same spawn point, and the wallet under test is not the one
## the panel reads.
func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_release_tree()


## Loads the real main scene and returns the root, or null.
func _boot_main() -> Node:
	_reset_rig()
	var packed := load("res://scenes/core/main.tscn") as PackedScene
	if packed == null:
		return null
	_rig = packed.instantiate()
	tree.root.add_child(_rig)
	for _i: int in range(8):
		await tree.process_frame
		await tree.physics_frame
	return _rig





func _find_first(from: Node, node_name: String) -> Node:
	if from == null:
		return null
	if from.name == node_name:
		return from
	for child: Node in from.get_children():
		var hit := _find_first(child, node_name)
		if hit != null:
			return hit
	return null


func _find_scripted(from: Node, script_file: String) -> Node:
	if from == null:
		return null
	var s := from.get_script() as Script
	if s != null and String(s.resource_path).ends_with(script_file):
		return from
	for child: Node in from.get_children():
		var hit := _find_scripted(child, script_file)
		if hit != null:
			return hit
	return null


## Hands the tree back in a usable state.
##
## Freeing the rig removes the booted scene and its autoload registrations, but
## `SceneTree.paused` is a property of the tree, not of anything in it. A case
## that failed mid-shop leaves it set, and every subsequent suite runs with no
## physics and no input — which is how four unrelated cases in `test_ui` and
## `test_time` failed for a reason that had nothing to do with them.
func _release_tree() -> void:
	if tree.paused:
		tree.paused = false
	var game_state := tree.root.get_node_or_null(^"GameState")
	if game_state != null and game_state.paused:
		game_state.set_paused(false)
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)


## Holds the movement actions down, so `_physics_process` has something to read.
## Holds [param actions] down, or releases everything if [param actions] is empty.
##
## The player reads input in `_physics_process`, which only runs while the tree is
## unpaused — that is the whole mechanism under test — so the actions have to be
## genuinely held on `Input`, not merely passed to a function.
func _drive_move(_player: Node, down: bool, actions: Array[StringName] = []) -> void:
	if down and actions.is_empty():
		actions = [&"move_left", &"move_right", &"move_forward", &"move_back"]
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		if not down or not actions.has(action):
			Input.action_release(action)
	for action: StringName in actions:
		if down:
			Input.action_press(action)


func _steps(n: int) -> void:
	for _i: int in range(n):
		await tree.process_frame
		await tree.physics_frame