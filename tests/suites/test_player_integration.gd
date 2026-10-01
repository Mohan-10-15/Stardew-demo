extends TestSuite
## Group 1 / 2 / 4 integration tests.
##
## Unlike the pure-maths suite, this one builds the real scenes and steps the
## real physics server. That is the only way to catch the failure modes that
## matter most in practice: falling through the world, jitter, and the camera
## switching modes while the player is standing on geometry.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const PHYSICS_STEPS := 30

var _rig: Node3D = null


func is_async() -> bool:
	return true


func setup() -> void:
	_rig = null


func teardown() -> void:
	# Held actions would leak into the next case and move the player during
	# assertions that assume it is standing still.
	Input.action_release(InputActions.MOVE_FORWARD)
	Input.action_release(InputActions.MOVE_BACK)
	Input.action_release(InputActions.MOVE_LEFT)
	Input.action_release(InputActions.MOVE_RIGHT)
	_reset_rig()


func get_cases() -> Array[StringName]:
	return [
		&"player_scene_instantiates_with_controller",
		&"player_scene_has_collision_shape",
		&"player_scene_has_camera_rig",
		&"camera_rig_finds_its_camera",
		&"player_stays_above_the_ground",
		&"player_does_not_sink_into_terrain",
		&"player_velocity_settles_when_idle",
		&"player_facing_is_upright",
		&"camera_mode_starts_first_person",
		&"toggle_switches_to_third_person",
		&"toggle_switches_back_to_first_person",
		&"v_key_press_toggles_the_camera_mode",
		&"default_camera_mode_is_honoured_from_config",
		&"switching_preserves_player_position",
		&"first_person_camera_is_at_eye_height",
		&"third_person_camera_is_behind_the_player",
		&"body_meshes_hidden_in_first_person",
		&"body_meshes_visible_in_third_person",
		&"camera_is_the_only_current_camera",
		&"world_builds_with_collision",
		&"world_has_ground_surface",
		&"world_regions_are_distinct",
		&"player_spawn_is_above_ground",
		&"third_person_camera_is_at_shoulder_height",
		&"strafing_does_not_spin_the_body",
		&"strafing_keeps_moving_in_a_straight_line",
		&"aim_yaw_is_independent_of_facing_yaw",
	]


func await_step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


func _build_world_and_player() -> Dictionary:
	# Each case gets a clean rig. Reusing one rig across cases stacks dozens of
	# players at the same spawn point, where they push each other around and
	# every "is the player standing on the floor" assertion becomes meaningless.
	_reset_rig()

	var world_packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	if world_packed == null or player_packed == null:
		return {}

	var world := world_packed.instantiate()
	var player := player_packed.instantiate()
	_rig = Node3D.new()
	root().add_child(_rig)
	_rig.add_child(world)
	_rig.add_child(player)

	player.global_position = world.get_spawn_point()
	# Collision pairs need a couple of frames before they resolve.
	await await_step(4)
	return {"world": world, "player": player}


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _run_async(case: StringName) -> Dictionary:
	# Every branch awaits: these helpers step the physics server, which makes
	# them coroutines.
	match case:
		&"player_scene_instantiates_with_controller":
			return await _t_scene_type()
		&"player_scene_has_collision_shape":
			return await _t_collision_shape()
		&"player_scene_has_camera_rig":
			return await _t_has_rig()
		&"camera_rig_finds_its_camera":
			return await _t_rig_camera()
		&"player_stays_above_the_ground":
			return await _t_no_fall()
		&"player_does_not_sink_into_terrain":
			return await _t_no_sink()
		&"player_velocity_settles_when_idle":
			return await _t_idle_settles()
		&"player_facing_is_upright":
			return await _t_upright()
		&"camera_mode_starts_first_person":
			return await _t_mode_starts_fp()
		&"toggle_switches_to_third_person":
			return await _t_toggle_tp()
		&"toggle_switches_back_to_first_person":
			return await _t_toggle_back()
		&"v_key_press_toggles_the_camera_mode":
			return await _t_v_key_press()
		&"default_camera_mode_is_honoured_from_config":
			return await _t_config_default_mode()
		&"switching_preserves_player_position":
			return await _t_position_preserved()
		&"first_person_camera_is_at_eye_height":
			return await _t_fp_height()
		&"third_person_camera_is_behind_the_player":
			return await _t_tp_behind()
		&"third_person_camera_is_at_shoulder_height":
			return await _t_tp_height()
		&"strafing_does_not_spin_the_body":
			return await _t_strafe_no_spin()
		&"strafing_keeps_moving_in_a_straight_line":
			return await _t_strafe_straight_line()
		&"aim_yaw_is_independent_of_facing_yaw":
			return await _t_yaw_independent()
		&"body_meshes_hidden_in_first_person":
			return await _t_meshes_fp()
		&"body_meshes_visible_in_third_person":
			return await _t_meshes_tp()
		&"camera_is_the_only_current_camera":
			return await _t_single_camera()
		&"world_builds_with_collision":
			return await _t_world_collision()
		&"world_has_ground_surface":
			return await _t_world_ground()
		&"world_regions_are_distinct":
			return await _t_regions()
		&"player_spawn_is_above_ground":
			return await _t_spawn_clear()
	return fail(case, "unhandled case")


func _t_scene_type() -> Dictionary:
	var c := &"player_scene_instantiates_with_controller"
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate()
	if not (p is PlayerController):
		var actual := p.get_class()
		p.free()
		return fail(c, "root is %s, expected PlayerController" % actual)
	p.free()
	return succeeded(c)


func _t_collision_shape() -> Dictionary:
	var c := &"player_scene_has_collision_shape"
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate()
	var shape := p.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape == null or shape.shape == null:
		p.free()
		return fail(c, "no CollisionShape3D with a shape")
	var is_capsule := shape.shape is CapsuleShape3D
	p.free()
	if not is_capsule:
		return fail(c, "expected a capsule collider")
	return succeeded(c)


func _t_has_rig() -> Dictionary:
	var c := &"player_scene_has_camera_rig"
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate()
	var rig := p.get_node_or_null(^"CameraRig") as CameraRig
	# Assert before freeing: a freed reference compares equal to null.
	var ok := rig != null
	p.free()
	if not ok:
		return fail(c, "no CameraRig child")
	return succeeded(c)


func _t_rig_camera() -> Dictionary:
	var c := &"camera_rig_finds_its_camera"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var rig := built["player"].get_node_or_null(^"CameraRig") as CameraRig
	if rig == null:
		return fail(c, "rig missing")
	if rig.get_camera() == null:
		return fail(c, "rig did not resolve its Camera3D")
	return succeeded(c)


func _t_v_key_press() -> Dictionary:
	var c := &"v_key_press_toggles_the_camera_mode"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var rig: CameraRig = player.camera_rig
	if rig == null:
		return fail(c, "player has no camera rig")

	var before := rig.get_mode()
	var press := InputEventKey.new()
	press.keycode = KEY_V
	press.physical_keycode = KEY_V
	press.pressed = true
	Input.parse_input_event(press)
	await await_step(2)

	if rig.get_mode() == before:
		return fail(c, "V press did not change the camera mode")
	var after := rig.get_mode()

	# Releasing must not toggle back, otherwise one press counts as two.
	var release := InputEventKey.new()
	release.keycode = KEY_V
	release.physical_keycode = KEY_V
	release.pressed = false
	Input.parse_input_event(release)
	await await_step(2)
	if rig.get_mode() != after:
		return fail(c, "V release toggled the camera again")
	return succeeded(c, "%s -> %s" % [CameraRig.Mode.keys()[before], CameraRig.Mode.keys()[after]])


func _t_config_default_mode() -> Dictionary:
	var c := &"default_camera_mode_is_honoured_from_config"
	var cfg := root().get_node_or_null(^"/root/Config")
	if cfg == null:
		return skip(c, "Config autoload unavailable")
	var original: int = cfg.settings.default_camera_mode
	cfg.settings.default_camera_mode = 1
	var built := await _build_world_and_player()
	cfg.settings.default_camera_mode = original
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var rig: CameraRig = player.camera_rig
	if rig == null:
		return fail(c, "player has no camera rig")
	if rig.get_mode() != CameraRig.Mode.THIRD_PERSON:
		return fail(c, "config asked for third person, rig started in %s" % CameraRig.Mode.keys()[rig.get_mode()])
	return succeeded(c, "started in %s as configured" % CameraRig.Mode.keys()[rig.get_mode()])


func _t_no_fall() -> Dictionary:
	var c := &"player_stays_above_the_ground"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var start_y: float = player.global_position.y
	await await_step(PHYSICS_STEPS)
	var end_y: float = player.global_position.y
	if end_y < start_y - 3.0:
		return fail(c, "player fell from y=%f to y=%f" % [start_y, end_y])
	if end_y < -5.0:
		return fail(c, "player ended up below the world at y=%f" % end_y)
	return succeeded(c, "y %.2f -> %.2f" % [start_y, end_y])


func _t_no_sink() -> Dictionary:
	var c := &"player_does_not_sink_into_terrain"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(PHYSICS_STEPS * 2)
	if not player.is_on_floor():
		return fail(c, "player never registered as grounded (y=%f)" % player.global_position.y)
	# The collider is offset so the body origin sits at the feet, meaning a
	# resting player settles at y ~ 0. Floating or sinking are both failures.
	var y: float = player.global_position.y
	if y < -0.05:
		return fail(c, "sank below the ground surface: y=%f" % y)
	if y > 0.3:
		return fail(c, "floating above the ground: y=%f" % y)
	return succeeded(c, "resting y=%.3f on_floor=%s" % [y, player.is_on_floor()])


func _t_idle_settles() -> Dictionary:
	var c := &"player_velocity_settles_when_idle"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(PHYSICS_STEPS * 2)
	var flat := Vector2(player.velocity.x, player.velocity.z).length()
	if flat > 0.05:
		return fail(c, "horizontal velocity did not settle: %f" % flat)
	return succeeded(c, "residual %.4f" % flat)


func _t_upright() -> Dictionary:
	var c := &"player_facing_is_upright"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	var up: Vector3 = player.global_transform.basis.y
	if up.distance_to(Vector3.UP) > 0.001:
		return fail(c, "body tilted: up=%s" % str(up))
	return succeeded(c)


func _t_mode_starts_fp() -> Dictionary:
	var c := &"camera_mode_starts_first_person"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var rig: CameraRig = built["player"].camera_rig
	if rig == null:
		return fail(c, "no rig")
	if not rig.is_first_person():
		return fail(c, "expected FIRST_PERSON, got %s" % rig.get_mode())
	return succeeded(c)


func _t_toggle_tp() -> Dictionary:
	var c := &"toggle_switches_to_third_person"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var rig: CameraRig = built["player"].camera_rig
	rig.toggle_mode()
	await await_step(2)
	if rig.get_mode() != CameraRig.Mode.THIRD_PERSON:
		return fail(c, "toggle did not switch to third person")
	return succeeded(c)


func _t_toggle_back() -> Dictionary:
	var c := &"toggle_switches_back_to_first_person"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var rig: CameraRig = built["player"].camera_rig
	rig.toggle_mode()
	await await_step(2)
	rig.toggle_mode()
	await await_step(2)
	if not rig.is_first_person():
		return fail(c, "second toggle did not return to first person")
	return succeeded(c)


func _t_position_preserved() -> Dictionary:
	var c := &"switching_preserves_player_position"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(PHYSICS_STEPS)
	var before: Vector3 = player.global_position
	player.camera_rig.toggle_mode()
	await await_step(2)
	var after: Vector3 = player.global_position
	var drift := before.distance_to(after)
	if drift > 0.001:
		return fail(c, "player moved on switch: %s -> %s" % [str(before), str(after)])
	return succeeded(c, "delta %.5f" % drift)


func _t_fp_height() -> Dictionary:
	var c := &"first_person_camera_is_at_eye_height"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	var cam := player.camera_rig.get_camera()
	var eye_local := cam.position.y
	if eye_local < 1.2 or eye_local > 2.0:
		return fail(c, "camera height %f not at eye level" % eye_local)
	return succeeded(c, "eye %.2f" % eye_local)


func _t_tp_behind() -> Dictionary:
	var c := &"third_person_camera_is_behind_the_player"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	player.camera_rig.toggle_mode()
	# The camera eases out from 0, so give it frames to actually travel back.
	await await_step(20)
	var cam := player.camera_rig.get_camera()
	# Rig-local +Z is behind, so the camera must sit at positive Z locally.
	if cam.position.z <= 0.1:
		return fail(c, "camera at z=%f, expected positive (behind)" % cam.position.z)
	return succeeded(c, "behind by %.2f" % cam.position.z)


## Regression test for the third-person camera rendering from the floor.
##
## The rig node sits at the player's *origin*, which is at the feet, so a camera
## positioned at local (0, 0, distance) looks out from ankle height and the
## third-person view is a screenshot of grass. Asserting on local Y is what
## makes that failure visible: it is the one number that was silently zero.
func _t_tp_height() -> Dictionary:
	var c := &"third_person_camera_is_at_shoulder_height"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	player.camera_rig.toggle_mode()
	await await_step(20)

	var cam := player.camera_rig.get_camera()
	var want := player.camera_rig.pivot_height
	if absf(cam.position.y - want) > 0.001:
		return fail(c, "camera local y=%f, expected pivot_height=%f" % [cam.position.y, want])
	# Belt and braces: the camera must also be above the feet in world space.
	var above_feet := cam.global_position.y - player.global_position.y
	if above_feet < 1.0:
		return fail(c, "camera only %f above the player origin; expected shoulder height" % above_feet)
	return succeeded(c, "y=%.2f (%0.2f above feet)" % [cam.position.y, above_feet])


## Regression test for the movement yaw feedback loop.
##
## The original controller read input through `global_transform.basis` while
## writing `rotation.y` from the resulting direction. Holding W+D turned the
## body toward the input, which turned the basis that interpreted "right",
## which turned the body further: about 9 degrees per frame, so the player
## circled and never travelled in a straight line.
##
## The body *should* still turn to face a strafe, so this cannot assert on
## `rotation.y` alone. It asserts the yaw converges on the correct heading for
## forward-right instead of running away.
func _t_strafe_no_spin() -> Dictionary:
	var c := &"strafing_does_not_spin_the_body"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)

	_hold(InputActions.MOVE_FORWARD)
	_hold(InputActions.MOVE_RIGHT)
	await await_step(30)
	_release(InputActions.MOVE_FORWARD)
	_release(InputActions.MOVE_RIGHT)

	# Forward-right in a yaw-0 body frame is 45 degrees off -Z. Allow generous
	# slack for the damping curve still settling, but nothing like the runaway
	# the old code produced.
	var facing := rad_to_deg(player.get_facing_yaw())
	if absf(absf(facing) - 45.0) > 20.0:
		return fail(c, "facing settled at %.1f deg, expected ~-45 for W+D" % facing)
	# The aim never moved, because no look input happened.
	if absf(player.get_yaw()) > 0.001:
		return fail(c, "aim yaw drifted to %.4f with no look input" % player.get_yaw())
	return succeeded(c, "facing %.1f deg, aim 0.0" % facing)


## The user-visible symptom: displacement must stay on the diagonal the keys
## asked for, rather than curving around in a circle.
func _t_strafe_straight_line() -> Dictionary:
	var c := &"strafing_keeps_moving_in_a_straight_line"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)

	var start := player.global_position
	_hold(InputActions.MOVE_FORWARD)
	_hold(InputActions.MOVE_RIGHT)
	await await_step(40)
	_release(InputActions.MOVE_FORWARD)
	_release(InputActions.MOVE_RIGHT)

	var travelled := player.global_position - start
	travelled.y = 0.0
	if travelled.length() < 0.5:
		return fail(c, "player barely moved (%f); test did not exercise strafing" % travelled.length())

	# Straight-line travel means displacement is parallel to the intent. With the
	# old loop the path curved, so the heading at the end drifted from the
	# heading at the start.
	var expected := (Vector3(1, 0, 0) - Vector3(0, 0, 1)).normalized()
	var drift := rad_to_deg(travelled.normalized().angle_to(expected))
	if drift > 25.0:
		return fail(c, "travelled %.1f deg off the requested diagonal" % drift)
	return succeeded(c, "%.2fm, %.1f deg off" % [travelled.length(), drift])


## Pins the two-yaw contract the strafe tests depend on.
func _t_yaw_independent() -> Dictionary:
	var c := &"aim_yaw_is_independent_of_facing_yaw"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)

	_hold(InputActions.MOVE_LEFT)
	await await_step(20)
	_release(InputActions.MOVE_LEFT)

	# Strafing left turns the body, and must not drag the aim with it.
	if absf(player.get_yaw()) > 0.001:
		return fail(c, "aim followed the body to %.4f rad" % player.get_yaw())
	if absf(player.get_facing_yaw()) < 0.001:
		return fail(c, "body never turned to face the strafe")
	# The rig counter-rotates by (aim - facing), so its *global* yaw must land
	# back on the aim heading no matter which way the body turned.
	var rig_yaw := player.camera_rig.global_transform.basis.get_euler().y
	var off := rad_to_deg(absf(PlayerMotion.damp_angle(rig_yaw, player.get_yaw(), 99.0, 1.0)))
	if off > 0.5:
		return fail(c, "camera rig global yaw %.2f deg, expected aim %.2f" % [
			rad_to_deg(rig_yaw), rad_to_deg(player.get_yaw())])
	return succeeded(c, "aim 0.0, facing %.1f deg, rig global %.2f deg" % [
		rad_to_deg(player.get_facing_yaw()), rad_to_deg(rig_yaw)])


func _hold(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _t_meshes_fp() -> Dictionary:
	var c := &"body_meshes_hidden_in_first_person"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	var head := player.get_node_or_null(^"Head") as MeshInstance3D
	if head == null:
		return fail(c, "Head mesh missing")
	if head.visible:
		return fail(c, "Head still visible in first person")
	return succeeded(c)


func _t_meshes_tp() -> Dictionary:
	var c := &"body_meshes_visible_in_third_person"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	player.camera_rig.toggle_mode()
	await await_step(5)
	var head := player.get_node_or_null(^"Head") as MeshInstance3D
	if head == null:
		return fail(c, "Head mesh missing")
	if not head.visible:
		return fail(c, "Head hidden in third person, character would be invisible")
	return succeeded(c)


func _t_single_camera() -> Dictionary:
	var c := &"camera_is_the_only_current_camera"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	await await_step(5)
	var current: Array[Camera3D] = []
	_collect_cameras(built["player"], current)
	if current.size() != 1:
		return fail(c, "found %d current cameras, expected 1" % current.size())
	return succeeded(c)


func _collect_cameras(node: Node, out: Array[Camera3D]) -> void:
	if node is Camera3D and (node as Camera3D).current:
		out.append(node as Camera3D)
	for child: Node in node.get_children():
		_collect_cameras(child, out)


func _t_world_collision() -> Dictionary:
	var c := &"world_builds_with_collision"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build world")
	var world: WorldRoot = built["world"]
	if world.get_child_count() == 0:
		return fail(c, "world produced no children")
	# GDScript ints are value types, so this returns the count rather than
	# mutating an out-parameter.
	var bodies := _count_bodies(world)
	if bodies == 0:
		return fail(c, "world has no StaticBody3D colliders (%d children: %s)" % [
			world.get_child_count(), str(_child_names(world)),
		])
	return succeeded(c, "%d children, %d colliders" % [world.get_child_count(), bodies])


func _child_names(node: Node, depth: int = 0) -> PackedStringArray:
	var out := PackedStringArray()
	if depth > 1:
		return out
	for child: Node in node.get_children():
		out.append(String(child.name))
		out.append_array(_child_names(child, depth + 1))
	return out


func _count_bodies(node: Node) -> int:
	var total := 1 if node is StaticBody3D else 0
	for child: Node in node.get_children():
		total += _count_bodies(child)
	return total


func _t_world_ground() -> Dictionary:
	var c := &"world_has_ground_surface"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build world")
	var world: WorldRoot = built["world"]
	var ground := world.get_node_or_null(^"Ground")
	if ground == null:
		return fail(c, "no Ground node (children: %s)" % str(_child_names(world)))
	var shape := ground.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape == null:
		return fail(c, "Ground has no CollisionShape3D child")
	if shape.shape == null:
		return fail(c, "Ground CollisionShape3D has a null shape")
	return succeeded(c)


func _t_regions() -> Dictionary:
	var c := &"world_regions_are_distinct"
	var farm := WorldBuilder.REGION_FARM
	var village := WorldBuilder.REGION_VILLAGE
	var forest := WorldBuilder.REGION_FOREST
	if farm.distance_to(village) < 10.0:
		return fail(c, "farm and village overlap")
	if farm.distance_to(forest) < 10.0:
		return fail(c, "farm and forest overlap")
	if village.distance_to(forest) < 10.0:
		return fail(c, "village and forest overlap")
	return succeeded(c)


func _t_spawn_clear() -> Dictionary:
	var c := &"player_spawn_is_above_ground"
	var world := (load(WORLD_SCENE) as PackedScene).instantiate()
	var spawn: Vector3 = world.get_spawn_point()
	world.free()
	if spawn.y < 0.5:
		return fail(c, "spawn point at y=%f is inside terrain" % spawn.y)
	return succeeded(c, "spawn %s" % str(spawn))