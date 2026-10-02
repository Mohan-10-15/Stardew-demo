extends SceneTree
## Headless tool: generates `scenes/player/player.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_player_scene.gd
##
## The character is built from primitive meshes (capsule body, sphere head) —
## original placeholder geometry, no external art.

const OUTPUT_PATH := "res://scenes/player/player.tscn"

const SKIN := Color(0.85, 0.63, 0.47)
const SHIRT := Color(0.29, 0.55, 0.78)
const PANTS := Color(0.26, 0.28, 0.36)
const HAIR := Color(0.24, 0.16, 0.11)


func _initialize() -> void:
	var root := CharacterBody3D.new()
	root.name = "Player"
	root.set_script(load("res://scripts/player/player_controller.gd"))
	root.set("capture_mouse_on_ready", true)
	# Layered rather than left on the default of `1`.
	#
	# Both masks were `1` — that is, [constant PhysicsLayers.WORLD] — for want of
	# anybody naming them, and nothing noticed until a dropped log had to be picked up
	# by walking over it. [ResourceDrop]'s pickup [Area3D] watches [constant
	# PhysicsLayers.PLAYER], because a pickup volume that also watched the world would
	# report every piece of ground the log was resting on. The player was never on
	# that layer, so nothing was ever reported and the wood simply stayed where it
	# fell. Movement is unchanged: [constant PhysicsLayers.PLAYER_MASK] *is* [constant
	# PhysicsLayers.WORLD].
	#
	# The probe is the other thing this fixes. Its ray includes [constant
	# PhysicsLayers.WORLD], so it used to start inside the player's own capsule and
	# exclude it by hand.
	root.collision_layer = PhysicsLayers.PLAYER
	root.collision_mask = PhysicsLayers.PLAYER_MASK

	# --- Collision -------------------------------------------------------
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	collision.position = Vector3(0, 0.9, 0)
	root.add_child(collision)

	# --- Visual body -----------------------------------------------------
	# Hidden in first person by CameraRig.register_body_mesh().
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.5
	body.mesh = body_mesh
	body.position = Vector3(0, 0.85, 0)
	body.material_override = _mat(PANTS)
	root.add_child(body)

	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.62, 0.62, 0.38)
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 1.18, 0)
	torso.material_override = _mat(SHIRT)
	root.add_child(torso)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.21
	head_mesh.height = 0.44
	head.mesh = head_mesh
	head.position = Vector3(0, 1.62, 0)
	head.material_override = _mat(SKIN)
	root.add_child(head)

	var hair := MeshInstance3D.new()
	hair.name = "Hair"
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.215
	hair_mesh.height = 0.45
	hair.mesh = hair_mesh
	hair.position = Vector3(0, 1.66, 0.01)
	hair.material_override = _mat(HAIR)
	root.add_child(hair)

	# A forward-facing nose wedge gives a readable facing direction, which
	# matters a lot in third person.
	var nose := MeshInstance3D.new()
	nose.name = "FacingMarker"
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.08, 0.08, 0.14)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.6, -0.2)
	nose.material_override = _mat(Color(0.95, 0.75, 0.6))
	root.add_child(nose)

	# --- Camera rig ------------------------------------------------------
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(load("res://scripts/player/camera_rig.gd"))
	rig.position = Vector3(0, 0, 0)
	root.add_child(rig)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 500.0
	rig.add_child(camera)

	# --- Interaction probe ------------------------------------------------
	# A plain Node, not Node3D: it aims from the active camera and has no
	# transform of its own to keep in sync.
	var probe := Node.new()
	probe.name = "InteractionProbe"
	probe.set_script(load("res://scripts/interaction/interaction_probe.gd"))
	probe.set("ray_length", 3.5)
	root.add_child(probe)

	for child: Node in [collision, body, torso, head, hair, nose, rig, camera, probe]:
		child.owner = root

	var err := _save(root)
	if err != OK:
		printerr("[generate_player_scene] failed: %d" % err)
		quit(1)
		return
	print("[generate_player_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.metallic = 0.0
	return m


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)