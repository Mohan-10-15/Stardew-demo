extends SceneTree
## Headless tool: generates `scenes/player/player.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_player_scene.gd
##
## The body is drawn at runtime from `resources/player/player_avatar.tres` by
## `scripts/player/player_avatar.gd`, on a bare `Model` node carrying that script.
## It used to be five primitive meshes — a capsule, a box, two spheres and a nose wedge
## — which is what a body looks like when nobody has decided what it is yet.

const OUTPUT_PATH := "res://scenes/player/player.tscn"


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
	# An empty node with a script on it. The model itself is built at runtime by
	# `PlayerAvatar`, not baked in here — see that script for why baking it silently
	# loses the tint.
	var avatar := Node3D.new()
	avatar.name = "Model"
	avatar.set_script(load("res://scripts/player/player_avatar.gd"))
	root.add_child(avatar)

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

	for child: Node in [collision, avatar, rig, camera, probe]:
		child.owner = root

	var err := _save(root)
	# Freed before quitting, which this generator did not used to need. Packing does
	# not release the tree, and the tree now holds a real imported model with meshes,
	# materials and textures, so leaving it alive dumps a screenful of RID-leak errors
	# at exit — and a generator that emits ERROR lines fails the pipeline that runs it.
	root.free()
	if err != OK:
		printerr("[generate_player_scene] failed: %d" % err)
		quit(1)
		return
	print("[generate_player_scene] wrote %s" % OUTPUT_PATH)
	quit(0)


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return ERR_CANT_CREATE
	return ResourceSaver.save(packed, OUTPUT_PATH)