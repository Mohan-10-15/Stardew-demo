extends SceneTree
## Headless tool: builds the real player and reports what its body actually drew.
##
## Run:
##     godot --headless --path . --script res://tools/playtest_avatar.gd
##
## Exists because every way an avatar can be wrong is invisible from the scene file.
## The tint can be dropped by the packer, the feet can end up below the origin, the
## height can be 100x out, and the body can be missing entirely — and in all four cases
## `player.tscn` loads clean and the suite is green unless something measures it.
##
## Prints the *measured* geometry, not the definition. The definition says what was asked
## for; this says what is there.
##
## `PlayerAvatar` and `CameraRig` are deliberately not named here. Naming a `class_name`
## pulls that script into this tool's compile unit, and both of them log through the
## `Log` autoload, which does not exist yet during a `--script` run — so the tool fails
## to compile with `Identifier not found: Log`. Reached by duck type off the node instead.

const AVATAR_MODE_FIRST := 0
const AVATAR_MODE_THIRD := 1

func _initialize() -> void:
	await process_frame
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		printerr("[playtest_avatar] cannot load the player scene")
		quit(1)
		return
	var player := packed.instantiate()
	root.add_child(player)
	# The controller is live, and it falls. The player drops a couple of hundredths of a
	# metre every frame under gravity, so measuring the avatar's world position while that
	# happens makes the report depend on how many frames this tool happened to await — and
	# it did read `feet y=-0.405` on a body that was perfectly grounded, because the player
	# carrying it was at -0.252. Pinned, the numbers below are comparable to the definition.
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	await process_frame
	await process_frame

	print("[playtest_avatar] player=%s children=%d" % [player.name, player.get_child_count()])
	for child: Node in player.get_children():
		print("   child: %s (%s)" % [child.name, child.get_class()])

	var avatar := player.get_node_or_null(^"Model")
	if avatar == null:
		printerr("[playtest_avatar] the player has no Model node")
		quit(1)
		return
	if not avatar.has_method("get_definition") or not avatar.has_method("get_model"):
		printerr("[playtest_avatar] the Model node does not carry a PlayerAvatar (class %s)" % avatar.get_class())
		quit(1)
		return

	var definition := avatar.call("get_definition") as Resource
	print("[playtest_avatar] definition: model=%s tint=%s height=%.2f" % [
		definition.get("model"), definition.get("model_tint"), float(definition.get("target_height")),
	])
	var model := avatar.call("get_model") as Node3D
	if model == null:
		printerr("[playtest_avatar] the avatar did not build")
		quit(1)
		return
	print("[playtest_avatar] model scale=%s offset_y=%.3f" % [model.scale, model.position.y])

	var meshes := _meshes(model)
	var tinted := 0
	var untinted: Array[String] = []
	for mesh: MeshInstance3D in meshes:
		if mesh.material_override != null:
			tinted += 1
		else:
			untinted.append(String(mesh.name))

	print("[playtest_avatar] meshes=%d tinted=%d" % [meshes.size(), tinted])
	# Per mesh, because a merged total cannot tell "the character is too big" apart from
	# "one of the twelve meshes is a 4m mistake", and those have different fixes. These are
	# authored sizes: a skinned mesh's own box is in bone-local space, so a head reads as
	# ~1.1 units wide here and is not drawn that wide.
	for mesh: MeshInstance3D in meshes:
		print("   mesh %-24s local_size=%-28s world_size=%s" % [
			String(mesh.name), str(mesh.get_aabb().size),
			str((mesh.global_transform * mesh.get_aabb()).size),
		])
	if not untinted.is_empty():
		print("[playtest_avatar] untinted meshes: %s" % ", ".join(untinted))

	# The drawn extent, measured the way the engine actually places a skinned mesh: from
	# the posed rig, in world space. Merging `get_aabb()` over the meshes instead would
	# report a 2.1m-tall figure with its feet 0.9m underground, which is the trap
	# `ModelArt._bone_bounds` documents — so this deliberately does not do that, and a
	# model that turns out to have no skeleton at all is reported rather than measured
	# wrongly.
	var drawn := _bone_bounds_world(model)
	# The chain that put the bones where they are, printed because a placement bug shows
	# up as a body that is the right shape in the wrong place, and the only way to tell
	# which transform is responsible is to see all of them.
	var skeleton := _find_skeleton(model)
	print("[playtest_avatar] avatar node origin=%s" % (avatar as Node3D).global_transform.origin)
	print("[playtest_avatar] model origin=%s scale=%s" % [model.global_transform.origin, model.scale])
	if skeleton != null:
		print("[playtest_avatar] skeleton origin=%s" % skeleton.global_transform.origin)
		print("[playtest_avatar] model-space bone min_y=%+.4f" % [
			_model_space_min_y(skeleton, model),
		])
	if drawn.size == Vector3.ZERO:
		printerr("[playtest_avatar] the avatar carries no Skeleton3D, so a skinned body cannot be measured")
	else:
		print("[playtest_avatar] drawn bounds: pos=%s size=%s" % [drawn.position, drawn.size])
		print("[playtest_avatar] feet y=%.3f crown y=%.3f height=%.3f (wanted %.2f)" % [
			drawn.position.y, drawn.position.y + drawn.size.y, drawn.size.y,
			float(definition.get("target_height")),
		])

	# The two height conventions side by side, because only one of them sizes a character
	# and the difference between them is the 0.09m this rig hangs below its origin. A crop
	# grows up out of a tile and wants `natural_height`; a figure stands on the ground and
	# wants the box's own size. Printed both ways because picking the wrong one produces a
	# body that is 1.84m when it was asked for 1.75m, with no error anywhere.
	var path: String = definition.get("model")
	var box := ModelArt.body_aabb(path)
	print("[playtest_avatar] crop-convention height=%.3f, standing height=%.3f, asked for %.2f" % [
		ModelArt.natural_height(path), box.size.y, float(definition.get("target_height")),
	])

	var rig := player.get_node_or_null(^"CameraRig")
	if rig == null:
		printerr("[playtest_avatar] the player has no CameraRig")
		quit(1)
		return
	print("[playtest_avatar] camera mode=%s" % rig.call("get_mode"))
	print("[playtest_avatar] hidden in first person: %d of %d" % [_visible_count(meshes, false), meshes.size()])
	rig.call("set_mode", AVATAR_MODE_THIRD, true)
	await process_frame
	print("[playtest_avatar] visible in third person: %d of %d" % [_visible_count(meshes, true), meshes.size()])

	player.free()
	quit(0)


static func _visible_count(meshes: Array[MeshInstance3D], want: bool) -> int:
	var n := 0
	for mesh: MeshInstance3D in meshes:
		if mesh.visible == want:
			n += 1
	return n


## The posed rig's extent in world space, or an empty box when there is no rig.
##
## Deliberately a copy of [code]ModelArt._bone_bounds[/code] rather than a call to it:
## that one is private, it works in model space, and this one has to measure a node that
## is already parented and scaled — which is the only version of the question that can
## catch a grounding offset applied at the wrong scale.
static func _bone_bounds_world(from: Node) -> AABB:
	var skeleton := _find_skeleton(from)
	if skeleton == null:
		return AABB()
	var box := AABB()
	var found := false
	for index: int in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		var pose := skeleton.get_bone_global_pose(index)
		for point: Vector3 in [pose.origin, pose * (rest.basis * rest.origin)]:
			var world := skeleton.global_transform * point
			box = AABB(world, Vector3.ZERO) if not found else box.expand(world)
			found = true
	return box


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## The lowest bone point in [param model]'s own space, which is the number the ground
## offset is supposed to cancel. Comparing it with the world-space feet in the report is
## what separates "the offset is wrong" from "the offset was applied to the wrong node".
static func _model_space_min_y(skeleton: Skeleton3D, model: Node3D) -> float:
	var lowest := INF
	for index: int in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		var pose := skeleton.get_bone_global_pose(index)
		for point: Vector3 in [pose.origin, pose * (rest.basis * rest.origin)]:
			var local: Vector3 = model.global_transform.affine_inverse() * (skeleton.global_transform * point)
			lowest = minf(lowest, local.y)
	return lowest


static func _meshes(from: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if from == null:
		return out
	if from is MeshInstance3D:
		out.append(from as MeshInstance3D)
	for child: Node in from.get_children():
		out.append_array(_meshes(child))
	return out
