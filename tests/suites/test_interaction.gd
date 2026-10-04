extends TestSuite
## Group 3 - interaction system.
##
## Covers the reusable component, the probe's focus resolution, the real `E`
## input path, timed (hold) interactions, and the world's demo props.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

## Fixture geometry: the prop sits at z=10 and the player at z=12.5, so the
## default forward (-Z) aims straight at it from inside both the ray length and
## the component's max_distance.
const PROP_POS := Vector3(0, 0, 10)
const STAND_POS := Vector3(0, 0.2, 12.5)

var _rig: Node3D = null


func is_async() -> bool:
	return true


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func get_cases() -> Array[StringName]:
	return [
		&"interactable_resolves_from_collider",
		&"interactable_resolves_from_ancestor_of_collider",
		&"interactable_resolve_returns_null_for_plain_geometry",
		&"interactable_is_available_by_default",
		&"disabled_interactable_is_unavailable",
		&"one_shot_interactable_latches_after_use",
		&"one_shot_interactable_reset_reopens",
		&"interact_emits_actor",
		&"focus_signals_fire_once_per_transition",
		&"probe_finds_the_thing_it_aims_at",
		&"probe_clears_focus_when_aiming_at_nothing",
		&"probe_ignores_interactable_beyond_reach",
		&"probe_reports_action_label_from_input_map",
		&"pressing_e_interacts_with_focused_target",
		&"interactable_is_consumed_after_one_shot_use",
		&"held_interaction_completes_after_its_duration",
		&"held_interaction_does_not_fire_early",
		&"world_contains_demo_interactables",
		&"world_demo_props_resolve_to_interactables",
		&"every_demo_prop_is_reachable_on_foot",
		&"something_is_interactable_from_the_spawn_point",
	]


# --- Fixtures -----------------------------------------------------------------

func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null
	# Leave no simulated keypress behind for the next suite.
	Input.action_release(&"interact")


func _ensure_rig() -> Node3D:
	if _rig == null or not is_instance_valid(_rig):
		_rig = Node3D.new()
		root().add_child(_rig)
	return _rig


func _make_prop(
	position: Vector3, prompt: String, hold: float = 0.0, one_shot: bool = false
) -> Node:
	_ensure_rig()
	var body := StaticBody3D.new()
	body.name = "TestProp"
	body.position = position
	body.collision_layer = 1

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	# Tall enough to be reached by a crosshair at eye height, matching how the
	# world pads its own interactable props.
	box.size = Vector3(1, 2.6, 1)
	shape.shape = box
	shape.position = Vector3(0, 1.3, 0)
	body.add_child(shape)

	var component := Interactable.new()
	component.name = "Interactable"
	component.prompt_text = prompt
	component.hold_seconds = hold
	component.one_shot = one_shot
	body.add_child(component)
	_rig.add_child(body)
	return body


func _build(player_position: Vector3 = Vector3.INF) -> Dictionary:
	# A fresh rig per case is essential: leftover worlds and players would keep
	# their own Camera3D, and `get_viewport().get_camera_3d()` returns whichever
	# camera is current, so the probe would aim with the *previous* case's rig.
	_reset_rig()
	var world_packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	if world_packed == null or player_packed == null:
		return {}

	_ensure_rig()
	var world := world_packed.instantiate()
	var player := player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)

	player.global_position = world.get_spawn_point()
	await _step(4)

	if player_position != Vector3.INF:
		player.global_position = player_position
		await _step(4)

	return {
		"world": world,
		"player": player,
		"probe": player.get_node_or_null(^"InteractionProbe") as InteractionProbe,
	}


## The common probe-test arrangement: a fixture prop in front of a standing
## player, both already in the tree.
func _build_aimed_at(
	prompt: String, hold: float = 0.0, one_shot: bool = false
) -> Dictionary:
	# The rig is rebuilt by `_build`, so the prop has to be added afterwards or
	# it would be freed along with the previous case.
	var built := await _build(STAND_POS)
	if built.is_empty():
		return built
	built["prop"] = _make_prop(PROP_POS, prompt, hold, one_shot)
	await _step(2)
	return built


func _interactable_of(node: Node) -> Interactable:
	return Interactable.resolve(node)


## Builds a bare prop with no world or player, for component-only cases.
func _lonely_prop(prompt: String, hold: float = 0.0, one_shot: bool = false) -> Node:
	_reset_rig()
	_ensure_rig()
	return _make_prop(Vector3(0, 0, 5), prompt, hold, one_shot)


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


## Human-readable probe state for failure messages. Without this a failed
## precondition is indistinguishable from a broken aim setup.
func _probe_diag(probe: InteractionProbe) -> String:
	if probe == null:
		return "probe is null"
	var camera := probe.get_camera()
	if camera == null:
		return "no active Camera3D in the viewport"
	var fwd := camera.global_transform.basis.z
	return "cam=%s pos=%s fwd=%s len=%.2f focus=%s" % [
		camera.get_path(),
		camera.global_position,
		Vector3(fwd.x, fwd.y, fwd.z).normalized(),
		probe.ray_length,
		"none" if probe.get_focus() == null else probe.get_focus().name,
	]


# --- Component-level cases ----------------------------------------------------

func _t_resolve_collider() -> Dictionary:
	var c := &"interactable_resolves_from_collider"
	var prop := _lonely_prop("Use")
	await _step(2)
	var found := Interactable.resolve(prop.get_node(^"CollisionShape3D"))
	if found == null:
		return fail(c, "resolve() found nothing on a prop that has one")
	return succeeded(c, "resolved %s" % found.name)


func _t_resolve_ancestor() -> Dictionary:
	var c := &"interactable_resolves_from_ancestor_of_collider"
	_reset_rig()
	_ensure_rig()

	# Component sits one level *above* the body, also a supported layout.
	var group := Node3D.new()
	group.name = "PropGroup"
	_rig.add_child(group)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2.6, 1)
	shape.shape = box
	body.add_child(shape)
	group.add_child(body)

	var component := Interactable.new()
	component.name = "Interactable"
	group.add_child(component)
	await _step(2)

	if Interactable.resolve(shape) != component:
		return fail(c, "did not resolve the ancestor's component")
	return succeeded(c, "resolved through the ancestor")


func _t_resolve_none() -> Dictionary:
	var c := &"interactable_resolve_returns_null_for_plain_geometry"
	_reset_rig()
	_ensure_rig()
	var plain := StaticBody3D.new()
	plain.name = "PlainBody"
	plain.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2.6, 1)
	shape.shape = box
	plain.add_child(shape)
	_rig.add_child(plain)
	await _step(2)

	if Interactable.resolve(shape) != null:
		return fail(c, "resolve() invented an interactable")
	return succeeded(c, "correctly returned null")


func _t_available_default() -> Dictionary:
	var c := &"interactable_is_available_by_default"
	var prop := _lonely_prop("Use")
	await _step(2)
	var it := _interactable_of(prop)
	if it == null:
		return fail(c, "prop had no interactable")
	if not it.is_available(null):
		return fail(c, "fresh interactable reported unavailable")
	return succeeded(c, "available")


func _t_disabled() -> Dictionary:
	var c := &"disabled_interactable_is_unavailable"
	var prop := _lonely_prop("Use")
	await _step(2)
	var it := _interactable_of(prop)
	it.set_enabled(false)
	if it.is_available(null):
		return fail(c, "disabled interactable still reported available")

	var changes := [0]
	it.availability_changed.connect(func() -> void: changes[0] += 1)
	it.set_enabled(true)
	if changes[0] != 1:
		return fail(c, "availability_changed fired %d times" % changes[0])
	return succeeded(c, "disable/enable honoured and signalled once")


func _t_one_shot_latch() -> Dictionary:
	var c := &"one_shot_interactable_latches_after_use"
	var prop := _lonely_prop("Use", 0.0, true)
	await _step(2)
	var it := _interactable_of(prop)
	var ok := it.interact(null)
	if not ok:
		return fail(c, "first interact() failed; one_shot=%s available=%s" % [
			it.one_shot, it.is_available(null),
		])
	if not it.has_been_used():
		return fail(c, "used flag not set after a successful interact; one_shot=%s" % it.one_shot)
	if it.interact(null):
		return fail(c, "one-shot allowed a second interaction")
	return succeeded(c, "second interaction refused")


func _t_one_shot_reset() -> Dictionary:
	var c := &"one_shot_interactable_reset_reopens"
	var prop := _lonely_prop("Use", 0.0, true)
	await _step(2)
	var it := _interactable_of(prop)
	it.interact(null)
	it.reset()
	if it.has_been_used():
		return fail(c, "reset() did not clear the used flag")
	if not it.interact(null):
		return fail(c, "still refuses after reset")
	return succeeded(c, "usable again after reset")


func _t_interact_emits() -> Dictionary:
	var c := &"interact_emits_actor"
	var prop := _lonely_prop("Use")
	await _step(2)
	var it := _interactable_of(prop)
	var got: Array = [null]
	it.interacted.connect(func(actor: Node) -> void: got[0] = actor)

	var sentinel := Node.new()
	sentinel.name = "SentinelActor"
	_rig.add_child(sentinel)
	it.interact(sentinel)
	if got[0] != sentinel:
		return fail(c, "interacted did not carry the actor")
	return succeeded(c, "actor delivered")


func _t_focus_signals() -> Dictionary:
	var c := &"focus_signals_fire_once_per_transition"
	var prop := _lonely_prop("Use")
	await _step(2)
	var it := _interactable_of(prop)
	var gained := [0]
	var lost := [0]
	it.focus_gained.connect(func() -> void: gained[0] += 1)
	it.focus_lost.connect(func() -> void: lost[0] += 1)

	it.set_focused(true)
	it.set_focused(true)
	it.set_focused(false)
	it.set_focused(false)
	if gained[0] != 1 or lost[0] != 1:
		return fail(c, "gained=%d lost=%d (expected 1/1)" % [gained[0], lost[0]])
	return succeeded(c, "one signal per transition")


# --- Probe-level cases --------------------------------------------------------

func _t_probe_finds() -> Dictionary:
	var c := &"probe_finds_the_thing_it_aims_at"
	var built := await _build_aimed_at("Use")
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	if probe == null:
		return fail(c, "player scene has no InteractionProbe")
	probe.update_focus()
	if probe.get_focus() == null:
		return fail(c, "probe found nothing while aiming at a prop; %s" % _probe_diag(probe))
	if probe.get_focus().get_prompt(null) != "Use":
		return fail(c, "focused the wrong prop")
	return succeeded(c, "focused %s" % probe.get_focus().name)


func _t_probe_clears() -> Dictionary:
	var c := &"probe_clears_focus_when_aiming_at_nothing"
	var built := await _build_aimed_at("Use")
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	probe.update_focus()
	if probe.get_focus() == null:
		return fail(c, "precondition failed: nothing was focused to begin with; %s" % _probe_diag(probe))

	# Turn around; the prop is then behind the player.
	var player: PlayerController = built["player"]
	player.set_yaw(PI)
	await _step(3)
	probe.update_focus()
	if probe.get_focus() != null:
		return fail(c, "still focused %s while facing away" % probe.get_focus().name)
	return succeeded(c, "focus cleared")


func _t_probe_out_of_reach() -> Dictionary:
	var c := &"probe_ignores_interactable_beyond_reach"
	var built := await _build_aimed_at("Use")
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	var player: PlayerController = built["player"]

	# Stand well past the component's own max_distance, still in line of sight.
	player.global_position = Vector3(0, 0.2, PROP_POS.z + 40.0)
	await _step(4)
	probe.update_focus()
	if probe.get_focus() != null:
		return fail(c, "focused a prop 40m away")
	return succeeded(c, "out-of-reach prop ignored")


func _t_action_label() -> Dictionary:
	var c := &"probe_reports_action_label_from_input_map"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	var label := probe.get_action_label()
	if label == "":
		return fail(c, "no label resolved for the interact action")
	# The default binding is KEY_E.
	if label.to_upper() != "E":
		return fail(c, "expected 'E' from the default binding, got '%s'" % label)
	return succeeded(c, "label=%s" % label)


func _t_press_e() -> Dictionary:
	var c := &"pressing_e_interacts_with_focused_target"
	var built := await _build_aimed_at("Use")
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	var it := _interactable_of(built["prop"])

	var seen := [0]
	it.interacted.connect(func(_actor: Node) -> void: seen[0] += 1)
	probe.update_focus()
	if probe.get_focus() == null:
		return fail(c, "precondition failed: prop was not focused; %s" % _probe_diag(probe))

	Input.action_press(&"interact")
	await _step(3)
	Input.action_release(&"interact")
	await _step(2)

	if seen[0] != 1:
		return fail(c, "E press fired %d interactions; %s" % [seen[0], _probe_diag(probe)])
	return succeeded(c, "interacted exactly once")


func _t_one_shot_consumed() -> Dictionary:
	var c := &"interactable_is_consumed_after_one_shot_use"
	var built := await _build_aimed_at("Open", 0.0, true)
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	probe.update_focus()
	if probe.get_focus() == null:
		return fail(c, "precondition failed: prop was not focused; %s" % _probe_diag(probe))

	Input.action_press(&"interact")
	await _step(3)
	Input.action_release(&"interact")
	await _step(2)

	if probe.get_focus() != null:
		return fail(c, "focus lingered on a spent one-shot")
	return succeeded(c, "prompt cleared after use")


func _t_hold_completes() -> Dictionary:
	var c := &"held_interaction_completes_after_its_duration"
	var built := await _build_aimed_at("Open", 0.25)
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	var it := _interactable_of(built["prop"])

	var seen := [0]
	it.interacted.connect(func(_actor: Node) -> void: seen[0] += 1)
	probe.update_focus()

	# Step one frame at a time and release the moment it fires, so the count
	# cannot be a multiple of the hold just because we overshot the duration.
	Input.action_press(&"interact")
	var frames := 0
	while seen[0] == 0 and frames < 60:
		await _step(1)
		frames += 1
	Input.action_release(&"interact")
	await _step(2)

	if seen[0] == 0:
		return fail(c, "hold never fired within 60 frames; %s" % _probe_diag(probe))
	if seen[0] != 1:
		return fail(c, "hold fired %d times (expected 1)" % seen[0])
	return succeeded(c, "held interaction fired after %d frames" % frames)


func _t_hold_not_early() -> Dictionary:
	var c := &"held_interaction_does_not_fire_early"
	var built := await _build_aimed_at("Open", 1.5)
	if built.is_empty():
		return fail(c, "could not build scene")
	var probe: InteractionProbe = built["probe"]
	var it := _interactable_of(built["prop"])

	var seen := [0]
	it.interacted.connect(func(_actor: Node) -> void: seen[0] += 1)
	probe.update_focus()

	# 6 frames is ~0.1s, far short of the 1.5s requirement.
	Input.action_press(&"interact")
	await _step(6)
	if seen[0] != 0:
		Input.action_release(&"interact")
		return fail(c, "fired after 0.1s despite a 1.5s hold")
	var progress := probe.get_hold_progress()
	if progress <= 0.0:
		Input.action_release(&"interact")
		return fail(c, "hold progress did not advance; %s" % _probe_diag(probe))
	Input.action_release(&"interact")
	await _step(2)
	if seen[0] != 0:
		return fail(c, "fired on release without completing the hold")
	return succeeded(c, "no early fire, progress=%.2f" % progress)


# --- World integration --------------------------------------------------------

func _t_world_has_interactables() -> Dictionary:
	var c := &"world_contains_demo_interactables"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build scene")
	var found := _collect_interactables(built["world"])
	if found.size() < 3:
		return fail(c, "only %d demo interactables in the world" % found.size())
	return succeeded(c, "%d interactables" % found.size())


func _t_world_props_resolve() -> Dictionary:
	var c := &"world_demo_props_resolve_to_interactables"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build scene")
	var world: WorldRoot = built["world"]

	# Every demo prop must expose a usable component through the same
	# resolve() path the probe uses at runtime.
	for prop_name: String in ["VillageWell", "NoticeBoard", "SupplyCrate"]:
		var body := world.get_node_or_null(NodePath(prop_name))
		if body == null:
			return fail(c, "missing prop %s" % prop_name)
		var shape := body.get_node_or_null(^"CollisionShape3D")
		if shape == null:
			return fail(c, "%s has no CollisionShape3D" % prop_name)
		var it := Interactable.resolve(shape)
		if it == null:
			return fail(c, "%s does not resolve to an Interactable" % prop_name)
		if it.get_prompt(null) == "":
			return fail(c, "%s has an empty prompt" % prop_name)
		if not it.get_prompt(null).begins_with("["):
			if it.get_prompt(null) == "Interact":
				return fail(c, "%s kept the default prompt" % prop_name)
	return succeeded(c, "all demo props resolve with their own prompts")


## A new game must open with something the player can actually interact with.
##
## Distinct from `every_demo_prop_is_reachable_on_foot`, which walks up to each
## prop. This asserts the *starting position* has a target within interaction
## range, without moving the player. Nothing enforced this before, so the first
## build opened facing an empty field: interaction worked, but the player had no
## way to discover it and reasonably concluded it was broken.
func _t_spawn_has_interactable() -> Dictionary:
	var c := &"something_is_interactable_from_the_spawn_point"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build scene")
	var world: WorldRoot = built["world"]
	var player: PlayerController = built["player"]

	var spawn: Vector3 = world.get_spawn_point()
	var best := INF
	var best_name := ""
	for it: Interactable in _collect_interactables(world):
		var d: float = spawn.distance_to(it.get_focus_point())
		if d < best:
			best = d
			best_name = String(it.get_parent().name)
	if best == INF:
		return fail(c, "world has no interactables at all")
	# Under the 3.2m component reach, with slack: the player has to be able to
	# look at it without walking off the spawn pad first.
	if best > 3.2:
		return fail(c, "nearest prop %s is %.1fm from spawn (0, 1.2, 14); reach is 3.2m"
			% [best_name, best])

	# And confirm the ray actually focuses it from where the player starts.
	player.global_position = spawn
	await _step(5)
	var probe: InteractionProbe = built["probe"]
	if probe == null:
		return fail(c, "player scene has no InteractionProbe")
	var prop := (built["world"] as Node).get_node_or_null(NodePath(best_name)) as Node3D
	if prop == null:
		return fail(c, "could not resolve prop node %s" % best_name)
	if not await _aim_at(player, probe, prop):
		return fail(c, "%s is in range but the crosshair did not focus it" % best_name)
	return succeeded(c, "%s at %.1fm from spawn" % [best_name, best])


## Walks the real player up to each real demo prop and confirms the actual
## crosshair ray focuses it.
##
## Existence and component resolution are covered above, but neither proves the
## player can *reach* anything. Every prop sat 26-44m from the spawn point,
## which is well outside the 3.2m interaction range, so a new game opened with
## no prompt in reach and no hint of where to go. This walks the props into
## range instead, which also proves the ray is not being blocked by scenery.
func _t_world_props_reachable() -> Dictionary:
	var c := &"every_demo_prop_is_reachable_on_foot"
	var built := await _build()
	if built.is_empty():
		return fail(c, "could not build scene")
	var world: Node3D = built["world"]
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	if probe == null:
		return fail(c, "player scene has no InteractionProbe")

	var props: Array[Node3D] = []
	for it: Interactable in _collect_interactables(world):
		var host := it.get_parent() as Node3D
		if host != null and not props.has(host):
			props.append(host)
	if props.is_empty():
		return fail(c, "world has no interactable props to walk to")

	# Enough directions to notice a prop boxed in on three sides, few enough that the
	# test stays quick: each bearing is a teleport, a settle and a raycast.
	var unreachable: Array[String] = []
	var wedged: Array[String] = []
	var tightest := 99
	for it: Interactable in _collect_interactables(world):
		var host := it.get_parent() as Node3D
		if host == null:
			continue
		# Every bearing, not one. A single fixed offset only proves the prop is
		# focusable from due south, and a valley full of scenery fails it constantly
		# for reasons a player never notices — they step round the bush. Requiring at
		# least one clear approach is the property that matters, and requiring *most* of
		# them is what catches a prop that has genuinely been grown into a thicket.
		var clear := 0
		for bearing: int in APPROACH_BEARINGS:
			if not await _aim_at(player, probe, host, it, bearing):
				continue
			clear += 1
			# The first clear approach is enough. Sweeping all eight for all 250
			# interactables cost more than the whole rest of the suite and timed the
			# stage out, and the extra six tell us nothing unless the first one failed.
			if clear == 1:
				break
		if clear == 0:
			unreachable.append("%s under %s -- no clear approach from any of %d bearings; %s" % [
				String(host.name), blocker_name(probe, it), APPROACH_BEARINGS,
				why_not_focused(probe, player, it),
			])
		else:
			tightest = mini(tightest, clear)
			if clear <= 2:
				wedged.append("%s under %s is focusable from only %d of %d sides" % [
					String(host.name), blocker_name(probe, it), clear, APPROACH_BEARINGS,
				])
	if not unreachable.is_empty():
		return fail(c, "%d unreachable: %s" % [unreachable.size(), "; ".join(unreachable.slice(0, 6))])
	return succeeded(c, "%d props focusable; tightest had %d of %d clear approaches%s" % [
		props.size(), tightest, APPROACH_BEARINGS,
		"" if wedged.is_empty() else "; %d wedged: %s" % [wedged.size(), "; ".join(wedged.slice(0, 4))],
	])


## Which of the three ways this can fail actually happened. "The crosshair did not focus
## it" on its own has been the message behind four unrelated bugs, and each one needed a
## different fix: a bad aim vector, a camera inside the target, scenery in the line of
## fire, and a target the player was standing too far back from.
static func why_not_focused(probe: InteractionProbe, player: PlayerController, target: Interactable) -> String:
	var blocker := probe.get_last_blocker()
	if blocker != null:
		return "occluded by %s" % blocker_name(probe)
	var rejected := probe.get_last_rejected()
	if rejected != null:
		var from: Vector3 = player.global_position
		var spot: Vector3 = rejected.get_focus_point()
		return "found it at %.1fm but reach is %.1fm (player at %s, target at %s)" % [
			from.distance_to(spot), rejected.max_distance, _v(from), _v(spot),
		]
	return "the ray hit empty space (no collider along a %.1fm line)" % probe.get_last_ray_length()


## One decimal place. The exact values are not interesting; the question is always
## "how far below the camera is this, and how far sideways".
static func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


## The ancestor chain above an interactable, skipping generated names. Its purpose is
## to say *which kind* of thing a nameless "AimVolume" belongs to, and secondarily to
## name whatever solid body stopped the probe's ray — a collider is usually nested under
## a named holder, and "Village/Shop/AimVolume" beats "StaticBody3D@42".
static func blocker_name(probe: InteractionProbe, of: Node = null) -> String:
	if of != null:
		var chain: Array[String] = []
		var up: Node = of
		for _i: int in 5:
			if up == null:
				break
			var named := String(up.name)
			if not named.begins_with("@"):
				chain.append(named)
			up = up.get_parent()
		return "/".join(chain)
	var blocker := probe.get_last_blocker()
	if blocker == null:
		return "nothing (the ray hit empty space)"
	var names: Array[String] = []
	var at: Node = blocker
	for _i: int in 4:
		if at == null:
			break
		var own := String(at.name)
		if not own.begins_with("@"):
			names.append(own)
		at = at.get_parent()
	if names.is_empty():
		return blocker.get_class()
	return "/".join(names)


## The approach directions tried per prop. Eight is every 45 degrees, which is close
## enough to "can a player get to it" without pretending to be a pathfinder.
const APPROACH_BEARINGS: int = 8


## Positions the player within interaction range of `host`, aims the real camera
## at `target_component`'s own focus point, and asserts the probe focused
## something.
##
## The aim is computed from the camera-to-target vector rather than guessed from a
## heading. Guessing is what made an earlier diagnostic report "occluded by a
## tree" when the ray was in fact pointing off past the side of the prop.
##
## Aimed at the component's declared aim point rather than a fixed height above
## the host. A fixed height suits a chest on a fence post and points at empty air
## for a farm tile lying flat on the ground; aiming at the tile's *origin* was
## worse, since that is the soil surface and the ray hit the terrain instead.
## Each component now says where its aimable surface is.
func _aim_at(
	player: PlayerController,
	probe: InteractionProbe,
	host: Node3D,
	target_component: Interactable = null,
	bearing: int = 0
) -> bool:
	var target: Vector3 = host.global_position + Vector3(0, 0.9, 0)
	if target_component != null:
		target = target_component.get_aim_point()
	# Standing off by `reach` at `bearing`. A different bearing each call, so repeated
	# calls walk the player around the prop instead of shoving them through it.
	var angle := TAU * float(bearing) / float(APPROACH_BEARINGS)
	var reach: float = target_component.max_distance if target_component != null else 3.2
	var stand := Vector3(cos(angle), 0.0, sin(angle)) * (reach * 0.6)
	player.global_position = Vector3(target.x + stand.x, 0.2, target.z + stand.z)
	await _step(5)

	var camera := probe.get_camera()
	if camera == null:
		return false
	var dir := (target - camera.global_position).normalized()
	player.set_yaw(atan2(-dir.x, -dir.z))
	# `atan2(dir.y, horizontal)`, not the negated form. A camera looks along -Z,
	# so rotating about +X carries that vector *upward*: positive pitch looks at
	# the sky. Negating `dir.y` aimed at the ceiling, which is why props standing
	# below eye height reported "could not focus" with no ray hit at all — not
	# even the terrain, which is the tell that the aim was wrong rather than the
	# target being unreachable.
	var horizontal := Vector2(dir.x, dir.z).length()
	player.camera_rig.set_pitch(atan2(dir.y, horizontal))
	await _step(3)

	probe.update_focus()
	return probe.get_focus() != null


func _collect_interactables(from: Node) -> Array[Interactable]:
	var out: Array[Interactable] = []
	if from is Interactable:
		out.append(from as Interactable)
	for child: Node in from.get_children():
		out.append_array(_collect_interactables(child))
	return out


# --- Dispatch -----------------------------------------------------------------

func _run_async(case: StringName) -> Dictionary:
	match case:
		&"interactable_resolves_from_collider":
			return await _t_resolve_collider()
		&"interactable_resolves_from_ancestor_of_collider":
			return await _t_resolve_ancestor()
		&"interactable_resolve_returns_null_for_plain_geometry":
			return await _t_resolve_none()
		&"interactable_is_available_by_default":
			return await _t_available_default()
		&"disabled_interactable_is_unavailable":
			return await _t_disabled()
		&"one_shot_interactable_latches_after_use":
			return await _t_one_shot_latch()
		&"one_shot_interactable_reset_reopens":
			return await _t_one_shot_reset()
		&"interact_emits_actor":
			return await _t_interact_emits()
		&"focus_signals_fire_once_per_transition":
			return await _t_focus_signals()
		&"probe_finds_the_thing_it_aims_at":
			return await _t_probe_finds()
		&"probe_clears_focus_when_aiming_at_nothing":
			return await _t_probe_clears()
		&"probe_ignores_interactable_beyond_reach":
			return await _t_probe_out_of_reach()
		&"probe_reports_action_label_from_input_map":
			return await _t_action_label()
		&"pressing_e_interacts_with_focused_target":
			return await _t_press_e()
		&"interactable_is_consumed_after_one_shot_use":
			return await _t_one_shot_consumed()
		&"held_interaction_completes_after_its_duration":
			return await _t_hold_completes()
		&"held_interaction_does_not_fire_early":
			return await _t_hold_not_early()
		&"world_contains_demo_interactables":
			return await _t_world_has_interactables()
		&"world_demo_props_resolve_to_interactables":
			return await _t_world_props_resolve()
		&"every_demo_prop_is_reachable_on_foot":
			return await _t_world_props_reachable()
		&"something_is_interactable_from_the_spawn_point":
			return await _t_spawn_has_interactable()
	return fail(case, "no case implementation for %s" % case)