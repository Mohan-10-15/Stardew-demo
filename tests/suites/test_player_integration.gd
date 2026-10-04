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

## Every character body the CC0 pack ships, listed rather than derived from the villager
## definitions. The attachment filter has to hold for the whole pack and not just the six
## villagers currently in the game, because the next villager added is an archetype nobody
## has tested — and `RogueHooded` in particular shares every mesh name with `Rogue` except
## its head, so a filter tuned on one of the pair passes on the other for the wrong reason.
const CHARACTER_MODELS: Array[String] = [
	"res://assets/models/kaykit/Characters/Barbarian.fbx",
	"res://assets/models/kaykit/Characters/Knight.fbx",
	"res://assets/models/kaykit/Characters/Mage.fbx",
	"res://assets/models/kaykit/Characters/Rogue.fbx",
	"res://assets/models/kaykit/Characters/RogueHooded.fbx",
]

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
		&"first_person_eye_stays_at_eye_height_when_pitched",
		&"third_person_camera_is_behind_the_player",
		&"body_meshes_hidden_in_first_person",
		&"body_meshes_visible_in_third_person",
		&"a_nested_body_mesh_is_hidden_in_first_person",
		&"avatar_stands_on_the_ground",
		&"avatar_drops_held_props",
		&"npc_drops_held_props",
		&"every_character_model_drops_held_props",
		&"attachment_list_names_real_meshes",
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
		&"first_person_eye_stays_at_eye_height_when_pitched":
			return await _t_fp_eye_survives_pitch()
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
		&"a_nested_body_mesh_is_hidden_in_first_person":
			return await _t_nested_mesh_hidden_in_first_person()
		&"avatar_stands_on_the_ground":
			return await _t_avatar_stands_on_the_ground()
		&"avatar_drops_held_props":
			return await _t_avatar_drops_held_props()
		&"npc_drops_held_props":
			return await _t_npc_drops_held_props()
		&"every_character_model_drops_held_props":
			return _t_every_character_model_drops_held_props()
		&"attachment_list_names_real_meshes":
			return _t_attachment_list_names_real_meshes()
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


## The eye stays at eye height when you look up or down.
##
## The rig sits at the player's *origin*, at the feet, and carries the pitch. A camera
## parented to it therefore orbits the feet rather than the head: look down and the
## eye swings back and down, look up and it drops forward. `_t_fp_height` above cannot
## see this — it only ever measures the camera with the pitch at zero.
##
## Asserted in **world** space, because that is where the defect lives: local position is
## correct-looking in every case, and the error is entirely in how the rig's rotation
## composes with it. The eye must stay a fixed distance above the feet, directly over
## them, at every pitch.
func _t_fp_eye_survives_pitch() -> Dictionary:
	var c := &"first_person_eye_stays_at_eye_height_when_pitched"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	if not player.camera_rig.is_first_person():
		player.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, true)
		await await_step(2)
	var cam := player.camera_rig.get_camera()
	var want_height: float = player.camera_rig.first_person_height
	var worst := ""
	# Both ends and straight down, because the error is a function of pitch and the
	# ends are where it is largest.
	for degrees: float in [0.0, -45.0, 45.0, -70.0]:
		player.set_pitch(deg_to_rad(degrees))
		await await_step(3)
		var offset := cam.global_position - player.global_position
		if absf(offset.y - want_height) > 0.02:
			worst = "pitch %+.0f deg: eye %.2f above the feet, expected %.2f" % [
				degrees, offset.y, want_height,
			]
			break
		# Directly over the player. Drift along the view axis is the orbit.
		var sideways := Vector2(offset.x, offset.z).length()
		if sideways > 0.02:
			worst = "pitch %+.0f deg: eye %.3fm off the body axis" % [degrees, sideways]
			break
	if not worst.is_empty():
		return fail(c, worst)
	return succeeded(c, "eye held %.2fm above the feet from -70 to +45 degrees"
		% want_height)


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
	var meshes := _avatar_meshes(player)
	if meshes.is_empty():
		return fail(c, "the avatar drew no meshes at all")
	for mesh: MeshInstance3D in meshes:
		if mesh.visible:
			return fail(c, "%s still visible in first person" % mesh.name)
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
	var meshes := _avatar_meshes(player)
	if meshes.is_empty():
		return fail(c, "the avatar drew no meshes at all")
	for mesh: MeshInstance3D in meshes:
		if not mesh.visible:
			return fail(c, "%s hidden in third person, character would be invisible" % mesh.name)
	return succeeded(c)


## Every mesh the player's avatar actually drew.
##
## Read off the [PlayerAvatar] rather than hard-coding a node name. These two cases used to
## look up `^"Head"`, which was one of five primitive meshes sitting directly on the player;
## the modelled avatar is an imported scene under `Model`, so that lookup no longer finds
## anything at all. Checking *every* mesh instead of one named part is also closer to what
## the assertion is about — a rig that hides the head and leaves the torso inside the
## camera is the failure worth catching.
func _avatar_meshes(player: PlayerController) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var avatar := player.get_node_or_null(^"Model") as PlayerAvatar
	if avatar == null:
		return out
	var model := avatar.get_model()
	if model == null:
		return out
	_collect_meshes(model, out)
	return out


static func _collect_meshes(from: Node, out: Array[MeshInstance3D]) -> void:
	if from == null:
		return
	if from is MeshInstance3D:
		out.append(from as MeshInstance3D)
	for child: Node in from.get_children():
		_collect_meshes(child, out)


## The avatar stands on the player's origin, at the height it was asked for.
##
## Both halves were wrong at once and neither raised anything. The rig is authored with its
## root at the hips, so the feet hang 0.09m below the imported origin and an ungrounded body
## is buried to the waist; and because the pack embeds five weapons under the same root, the
## measured body was 4.1m wide and 2.4m tall, which put that offset a metre out. The result
## was an avatar hovering above the floor in third person with a green suite.
func _t_avatar_stands_on_the_ground() -> Dictionary:
	var c := &"avatar_stands_on_the_ground"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(3)
	var avatar := player.get_node_or_null(^"Model") as PlayerAvatar
	if avatar == null or not avatar.built:
		return fail(c, "the avatar did not build")
	var box := avatar.measured_bounds()
	if box.size.y <= 0.0:
		return fail(c, "measured bounds are empty, so nothing can be asserted about them")
	if absf(box.position.y) > 0.05:
		var model := avatar.get_model()
		return fail(c, "feet are %.3fm off the floor (box %s, model at y=%.4f scaled by %.4f)" % [
			box.position.y, box, model.position.y, model.scale.y,
		])
	var wanted := avatar.get_definition().target_height
	if absf(box.size.y - wanted) > 0.05:
		return fail(c, "avatar stands %.3fm, was asked for %.2fm" % [box.size.y, wanted])
	return succeeded(c)


## No held props survive on the player's body.
##
## `Rogue.fbx` is a 1.25m character *and* a 1H crossbow, a 2H crossbow, two knives and a
## throwable, all under one imported root. Instanced whole, the player carries the whole
## armoury — which also made the measured body four metres wide, so this case is really two
## assertions wearing one name.
func _t_avatar_drops_held_props() -> Dictionary:
	var c := &"avatar_drops_held_props"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(3)
	var meshes := _avatar_meshes(player)
	if meshes.is_empty():
		return fail(c, "the avatar drew no meshes at all")
	for mesh: MeshInstance3D in meshes:
		if ModelArt.is_attachment(String(mesh.name)):
			return fail(c, "%s is still attached to the player" % mesh.name)
	return succeeded(c)


## Every character model in the pack loses its held props, not just the player's.
##
## The six shipped villagers were instanced whole too, so each was carrying its archetype's
## entire armoury — four shields and three swords for the Knight, a mug and three axes for
## the Barbarian. Asserted per model, because the filter that fixes the Rogue is a *name
## list*, and a list that happens to work for one archetype is exactly the list that leaves
## the other four broken. `RogueHooded` is the interesting one: it reuses `Rogue_` for
## every part, so no prefix rule can strip it.
func _t_every_character_model_drops_held_props() -> Dictionary:
	var c := &"every_character_model_drops_held_props"
	for path: String in CHARACTER_MODELS:
		if not ModelArt.can_load(path):
			return fail(c, "cannot load %s" % path)
		var node := ModelArt.instantiate(path)
		if node == null:
			return fail(c, "%s did not instantiate" % path)
		var before := _attachments_under(node)
		ModelArt.strip_attachments(node)
		var after := _attachments_under(node)
		node.free()
		if after > 0:
			return fail(c, "%s still carries %d held props" % [path.get_file(), after])
		if before == 0:
			return fail(c, "%s reported no held props, so this proves nothing" % path.get_file())
	return succeeded(c)


## Every name in the attachment list still names a mesh that exists.
##
## The list in [member ModelArt.ATTACHMENT_MESH_NAMES] is the one thing here that cannot
## report its own staleness — an entry for a mesh the pack no longer ships costs nothing and
## protects nothing. So the list is checked against the real files, which turns "someone
## deleted an asset" into a failing test instead of a silently shorter filter.
func _t_attachment_list_names_real_meshes() -> Dictionary:
	var c := &"attachment_list_names_real_meshes"
	var present: Dictionary = {}
	for path: String in CHARACTER_MODELS:
		var packed := ModelArt.scene(path)
		if packed == null:
			return fail(c, "cannot load %s" % path)
		var node := packed.instantiate()
		if node == null:
			return fail(c, "%s did not instantiate" % path)
		_mesh_names(node, present)
		node.free()
	for name: String in ModelArt.ATTACHMENT_MESH_NAMES:
		if not present.has(name):
			return fail(c, "%s is in the attachment list but in no character model" % name)
	return succeeded(c)


## A villager stands on the ground too, and carries nothing it should not.
##
## The avatar's copy of this bug was found first because the player is the one body a test
## looks at. The villagers were measured with the same broken box, so they were floating by
## the same amount, and their colliders — which come from `target_height`, not the box —
## were fine the whole time, which is why nothing looked obviously wrong from the outside.
func _t_npc_drops_held_props() -> Dictionary:
	var c := &"npc_drops_held_props"
	var npc := Npc.new()
	npc.name = "Fen"
	# Data before the node enters the tree: `_ready` builds the collider and the model out
	# of it, so a definition assigned afterwards measures an empty one and the villager
	# comes out with no body at all.
	npc.data = load("res://resources/npc/npcs/fen.tres")
	if npc.data == null:
		return fail(c, "no fen definition")
	_reset_rig()
	_rig = Node3D.new()
	root().add_child(_rig)
	_rig.add_child(npc)
	await await_step(3)
	var model := npc.get_node_or_null(^"Model")
	var meshes: Array[MeshInstance3D] = []
	if model != null:
		_collect_meshes(model, meshes)
	if meshes.is_empty():
		return fail(c, "the villager drew no meshes at all")
	for mesh: MeshInstance3D in meshes:
		if ModelArt.is_attachment(String(mesh.name)):
			return fail(c, "%s is still attached to the villager" % mesh.name)
	return succeeded(c)


static func _attachments_under(from: Node) -> int:
	if from == null:
		return 0
	var n := 0
	if from is MeshInstance3D and ModelArt.is_attachment(String(from.name)):
		n += 1
	for child: Node in from.get_children():
		n += _attachments_under(child)
	return n


static func _mesh_names(from: Node, out: Dictionary) -> void:
	if from == null:
		return
	if from is MeshInstance3D:
		out[String(from.name)] = true
	for child: Node in from.get_children():
		_mesh_names(child, out)


## A nested body mesh is hidden in first person too.
##
## The rig discovers the meshes it hides by walking the player, and that walk used to be
## one level deep — which is the shape the primitive avatar happens to have, five meshes
## sitting directly on the player. A modelled character is one imported scene under a
## `Model` node, so the walk finds nothing, registers nothing, and the first-person view
## is rendered from inside the player's own chest with no error anywhere.
##
## So this nests a mesh under a fresh child *after* the rig has already discovered
## everything, which is the honest version of the swap: it fails unless discovery is
## re-run over the whole subtree.
func _t_nested_mesh_hidden_in_first_person() -> Dictionary:
	var c := &"a_nested_body_mesh_is_hidden_in_first_person"
	var built := await _build_world_and_player()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	await await_step(5)
	if not player.camera_rig.is_first_person():
		player.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, true)
		await await_step(2)

	# The shape an imported avatar arrives in: a node holding several meshes.
	var model := Node3D.new()
	model.name = "Model"
	player.add_child(model)
	var hat := MeshInstance3D.new()
	hat.name = "Hat"
	hat.mesh = BoxMesh.new()
	model.add_child(hat)
	await await_step(2)
	player.camera_rig.call("_discover_body_meshes")
	await await_step(2)

	if hat.visible:
		return fail(c, "a mesh nested under Model is still visible in first person")
	player.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, true)
	await await_step(2)
	if not hat.visible:
		return fail(c, "the nested mesh stayed hidden in third person")
	return succeeded(c, "hidden in first person, shown in third")


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