extends SceneTree
## ClassDB ground truth for Update 2. Run:
##   Godot --headless --path . --script res://tools/probe_engine.gd
## Never guess whether a 4.5 class or setting exists — run this instead.

func _initialize() -> void:
	for p: Dictionary in ProjectSettings.get_property_list():
		if str(p.name) == "physics/3d/physics_engine":
			print("physics_engine options: ", p.hint_string)
	for cls: String in ["SpringBoneSimulator3D", "SpringBoneCollisionCapsule3D", "GridMap", "SkeletonProfileHumanoid",
			"BoneMap", "RetargetModifier3D", "LookAtModifier3D", "AnimationTree", "AudioStreamInteractive",
			"AudioStreamPlaylist", "AudioStreamSynchronized", "AudioStreamRandomizer", "AccessibilityServer"]:
		print(cls, ": ", ClassDB.class_exists(cls))
	for pr: Dictionary in ClassDB.class_get_property_list("BaseMaterial3D"):
		if str(pr.name).begins_with("stencil"):
			print("stencil property: ", pr.name)
	quit()
