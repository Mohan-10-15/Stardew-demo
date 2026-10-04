class_name ModelArt
extends RefCounted
## Instantiates the CC0 nature models and measures them, so a soil tile can draw a
## real crop and a rock can carry a collider sized to its own art, without either
## guessing at scale.
##
## Used to be `CropArt`, and was named for the only caller it had. A gatherable
## tree needs the same two things a crop does — a correctly scaled instance and a
## measurement — and re-implementing that in the gathering lane is how two
## definitions of "how big is this model" end up disagreeing. It lives in `core`
## because both [SoilTile] and the gathering nodes speak it, and `core` is what
## every other layer shares.
##
## ## Why this is not just `load(path).instantiate()` in [SoilTile]
##
## Two problems, both of which produce a silently wrong picture rather than an
## error:
##
## 1. **The importer's scale lives in the node transform.** Quaternius authors in
##    centimetres and Godot's FBX importer converts to metres by scaling nodes in
##    the imported scene. `Mesh.get_aabb()` on such a mesh reports the *pre-scale*
##    bounds — a `BirchTree_1` measures 0.017 units that way and 1.70 metres the
##    way the engine draws it. Pulling the bare mesh out of the imported scene and
##    dropping it into a tile therefore produces a model 100x too big. So the
##    whole imported scene is instanced and kept intact, and only a uniform scale
##    is applied on top.
## 2. **Every tile needs its own copy.** A `Node3D` cannot be shared between
##    tiles, so the cached thing is the [PackedScene] (a refcounted resource) and
##    each tile gets a fresh instance of it.
##
## Measurements are cached per path, so a field of 200 tiles loads and walks each
## distinct model exactly once.

## Cached [PackedScene] per model path. A failed load is cached as `null` too, so
## a typo in a `.tres` does not re-attempt the load on every repaint.
static var _scenes: Dictionary = {}

## Tinted materials, keyed by source material instance id plus tint.
##
## Found by a world-materials test that counted 104 distinct materials across 263
## meshes: [method apply_tint] duplicated one material per *instance*, so a wood of
## eighty trees with the same tint got eighty identical materials and nothing the
## renderer could batch. The duplicate has to exist — the alternative is editing the
## shared resource and tinting every other instance in the valley at once — but it
## only has to exist once per (model, tint) pair.
static var _tints: Dictionary = {}

## Cached measured top height in metres per model path.
static var _heights: Dictionary = {}

## Cached measured bounds in metres per model path.
static var _aabbs: Dictionary = {}

## Cached body-only bounds, with held props excluded. Separate from [_aabbs] because the
## two answer different questions for a character and only one is right.
static var _body_aabbs: Dictionary = {}

## Cached root [member Node3D.scale] as the importer set it, per model path.
##
## A rescale has to *compose* with this rather than replace it, because the
## centimetre-to-metre conversion the importer performs lives here.
static var _root_scales: Dictionary = {}

## Running bounds accumulator while walking one model.
##
## Member state rather than a returned value because [AABB] is a value type in
## GDScript: passing one into a recursive walk and assigning to it discards the
## result silently, which is documented at length in `tools/probe_model_sizes.gd`.
static var _bounds: AABB = AABB()


## Mesh names that are a *prop held or worn by* a KayKit character rather than part of
## its body.
##
## ## Why a list of names, when the pack offers better signals
##
## Two obvious rules were tried against the real files and both are wrong:
##
## * **Keep the meshes whose name starts with the file's name.** Works for four of the
##   five characters and empties `RogueHooded.fbx` completely, because that model reuses
##   `Rogue_` for every one of its parts. It also keeps `Barbarian_Round_Shield`, which is
##   a shield.
## * **Keep the skinned meshes.** The limbs, torso and head are skinned and the
##   attachments are not, which is true and tempting — and it silently deletes the cape,
##   the hat, the helmet and the hood, which are unskinned and are absolutely part of
##   the body. A knight with no helmet is a different character.
##
## So the list is explicit, which means it can rot. It cannot rot silently, because
## `every_character_model_draws_only_its_body` asserts that no attachment mesh survives in
## any character, and `the_attachment_list_still_names_real_meshes` asserts every name
## here still exists somewhere in the pack — so deleting an asset fails a test instead of
## quietly leaving a dead entry behind.
##
## Kept here, in the one place that knows how models turn into nodes, rather than in a
## per-content-type script: [Npc] and [PlayerAvatar] both need it, and two copies of this
## list is how one of them ends up filtering and the other not.
const ATTACHMENT_MESH_NAMES: Array[String] = [
	"1H_Axe", "1H_Axe_Offhand", "2H_Axe",
	"1H_Crossbow", "2H_Crossbow",
	"1H_Sword", "1H_Sword_Offhand", "2H_Sword",
	"1H_Wand", "2H_Staff",
	"Knife", "Knife_Offhand",
	"Mug", "Throwable",
	"Round_Shield", "Rectangle_Shield", "Spike_Shield", "Badge_Shield",
	"Barbarian_Round_Shield",
	"Spellbook", "Spellbook_open",
]


## Whether a mesh of this name is a held or worn prop rather than a character's body.
static func is_attachment(mesh_name: String) -> bool:
	return ATTACHMENT_MESH_NAMES.has(mesh_name)


## Deletes every attachment mesh under [param root] and returns how many went.
##
## Takes the node apart, so only ever call it on a fresh [method instantiate] — the
## cached [PackedScene] is shared and must not be edited.
##
## ## What this was hiding
##
## `Rogue.fbx` is not one mesh. It is a 1.25m character *and five weapons* — a 1H
## crossbow, a 2H crossbow, two knives and a throwable — all parented under the same
## imported root. Instanced whole, every villager carries the entire armoury, and the
## bounds measured for the body come out 4.1m wide and 2.4m tall, which is what put the
## ground offset 0.7m off and had the character standing with its ankles buried.
##
## [method tools/probe_model_meshes.gd] is what found it, by listing the contents of
## every model in the project rather than trusting the filenames.
static func strip_attachments(root: Node) -> int:
	var removed := 0
	for child: Node in root.get_children():
		if child is MeshInstance3D and is_attachment(String((child as MeshInstance3D).name)):
			root.remove_child(child)
			child.free()
			removed += 1
			continue
		removed += strip_attachments(child)
	return removed


## The bounds of a model's *body*, in metres, ignoring any attachment meshes.
##
## Separate from [method natural_aabb] rather than a parameter on it, because the two
## answer different questions and only one is right most of the time. A rock has no
## attachments and the two agree; a character does not, and measuring the whole file gives
## a box that includes the weapons and is therefore not a body.
static func body_aabb(path: String) -> AABB:
	return _measure(path, true)


## Measures [param path] once, caching under whichever of the two tables matches
## [param body_only].
##
## Dictionaries are reference types in GDScript, so binding the cache to a local and
## writing through it writes to the static table. That is deliberate: one function, two
## caches, and no chance of the two paths drifting apart in how they measure.
static func _measure(path: String, body_only: bool) -> AABB:
	var cache: Dictionary = _body_aabbs if body_only else _aabbs
	if cache.has(path):
		return cache[path]
	var box := AABB()
	var packed := scene(path)
	if packed != null:
		var node := packed.instantiate()
		if node != null:
			if body_only:
				strip_attachments(node)
			# Seed with the root's own transform. Starting from identity and only
			# composing the *children* misses a scale set on the root, which is precisely
			# where the FBX importer puts the centimetre-to-metre conversion.
			var root_xform := Transform3D.IDENTITY
			if node is Node3D:
				root_xform = (node as Node3D).transform
			var skeleton := _find_skeleton(node)
			if skeleton != null:
				box = _bone_bounds(root_xform, skeleton)
			else:
				_bounds = AABB()
				_walk(node, root_xform)
				box = _bounds
			# A PackedScene node is not refcounted, so it has to be freed by hand.
			node.free()
	cache[path] = box
	return box


## The first [Skeleton3D] at or under [param node], or `null` for a static model.
static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## The extent of a posed rig: every bone's head *and* tail, in root space.
##
## ## Why the bones and not the meshes
##
## The mesh walk in [method _walk] is the right answer for the Quaternius nature pack and
## the wrong one for the KayKit characters, and it fails in a way that looks like a
## plausible number rather than an error.
##
## A skinned mesh's own [method VisualInstance3D.get_aabb] is its geometry in *bone-local*
## space, because the vertices are authored around the joint and the skeleton is what
## carries them into place. Every limb of `Rogue.fbx` therefore reports a box near the
## origin — a leg is 0.24 x 0.53 x 0.40 as authored — and composing them all gives a union
## 2.13m tall with the feet 0.88m below the root, when the character is really 1.30m tall
## standing on its own origin. Scaled by the 1.75m target that error is the difference
## between a villager standing on the ground and hovering a metre above it, which is why
## this had to be fixed before the avatar looked right rather than after.
##
## Both ends of each bone are used, not just the head: the head bone's tail is the crown
## and the foot bone's tail is the toe, so the tails are where a height that matches the
## artwork actually comes from. Bones have no width, which is fine — every caller wants
## the floor and the ceiling, and the horizontal extent of a character comes from its
## [member NpcData.target_height] instead.
static func _bone_bounds(root_xform: Transform3D, skeleton: Skeleton3D) -> AABB:
	var to_world := root_xform * _chain_to_root(skeleton)
	var box := AABB()
	var found := false
	for index: int in skeleton.get_bone_count():
		# A bone is a segment, not a point, and Godot 4's Transform3D has no `tail`
		# member to read one from: the far end is the head's own offset rotated into the
		# bone's axes, which is the convention the engine itself uses to draw a rig. So
		# the tail is recomposed rather than looked up, and a bone with no offset collapses
		# to its head and contributes nothing.
		var rest := skeleton.get_bone_rest(index)
		var pose := skeleton.get_bone_global_pose(index)
		for point: Vector3 in [pose.origin, pose * (rest.basis * rest.origin)]:
			var world := to_world * point
			box = AABB(world, Vector3.ZERO) if not found else box.expand(world)
			found = true
	return box


## The transform carrying [param node]'s own space up to its root's local space,
## excluding the root's own transform.
static func _chain_to_root(node: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current.get_parent() != null:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## The imported scene for [param path], or `null` if it cannot be loaded.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scenes.has(path):
		return _scenes[path]
	var packed := load(path) as PackedScene
	_scenes[path] = packed
	if packed == null:
		printerr("[ModelArt] cannot load model %s" % path)
	return packed


## Whether [param path] names a model that will actually load.
##
## Used by the content tests, so a bad path in a crop `.tres` fails the suite
## rather than showing up as an empty field.
static func can_load(path: String) -> bool:
	return scene(path) != null


## The model's bounds in metres, as imported: an [AABB] whose `position` is the
## lowest corner and whose `size` is the drawn extent.
##
## One walk serves every measurement here, so asking for the bounds and the height
## costs the same single pass. A path that will not load, or a model with no
## geometry, reports an empty box at the origin rather than something arbitrary, and
## callers treat a zero size as "leave the model at native size".
##
## A skinned model is measured from its bones instead of its meshes — see
## [method _bone_bounds] for why the mesh walk cannot be trusted on a character — while a
## static one is walked as before, which is what keeps the importer's unit conversion
## intact for the whole nature pack.
##
## The gatherable nodes size their colliders from this, which is what keeps a rock's
## hitbox inside its own artwork instead of near the authored size somebody typed
## into a `.tres` and never revisited.
static func natural_aabb(path: String) -> AABB:
	return _measure(path, false)


## How tall the model at [param path] stands, in metres, as imported.
##
## The top of [method natural_aabb]'s box, which is what makes this agree with what
## the renderer draws rather than with the raw mesh bounds. Returns 0.0 for a path
## that will not load.
static func natural_height(path: String) -> float:
	if _heights.has(path):
		return _heights[path]
	var box := natural_aabb(path)
	var measured := maxf(box.position.y + box.size.y, 0.0)
	_heights[path] = measured
	return measured


## The root scale the FBX importer gave the model at [param path].
##
## Multiply this by a wanted/natural ratio to resize a model without losing the
## importer's unit conversion. Cached, and safe to call every frame.
static func root_scale(path: String) -> Vector3:
	if _root_scales.has(path):
		return _root_scales[path]
	var packed := scene(path)
	if packed == null:
		_root_scales[path] = Vector3.ONE
		return Vector3.ONE
	var probe := packed.instantiate() as Node3D
	if probe == null:
		_root_scales[path] = Vector3.ONE
		return Vector3.ONE
	var s := probe.scale
	probe.free()
	_root_scales[path] = s
	return s


## A fresh instance of the model at [param path] at its natural size.
##
## Pass a non-positive [param target_height] to get the model unscaled and resize
## it yourself with [method root_scale]; that is what [SoilTile] does, so a
## nightly growth repaint re-scales one node instead of rebuilding a scene.
##
## Returns `null` rather than an empty node when the path will not load, so the
## caller can fall back to the procedural plant instead of parenting nothing.
static func instantiate(path: String, target_height: float = 0.0) -> Node3D:
	var packed := scene(path)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		printerr("[ModelArt] %s is not a Node3D scene" % path)
		return null
	if target_height > 0.0:
		var natural := natural_height(path)
		if natural > 0.0:
			node.scale = node.scale * (target_height / natural)
	return node


## A fresh instance of [param path] scaled to *stand* [param target_height] tall, feet on
## the imported origin.
##
## ## Why this is not [method instantiate] with a target height
##
## [method natural_height] answers "how far is the top of this model above its origin",
## which is the right question for a crop growing out of a soil tile and the wrong one for
## a character. A KayKit rig is authored with its root at the hips, so 0.09m of the figure
## hangs below the origin: dividing by the height-above-origin and then grounding the result
## produces a body that stands 1.84m when it was asked for 1.75m, every time, by exactly
## the amount it sank. A standing height is the box's own size, so that is what this
## divides by.
##
## The soil tiles and the gatherables keep using [method natural_height], where the
## offset-free reading is the one they want. Both conventions stay because both callers
## exist, and collapsing them into one flag is how a rock ends up sunk into the terrain.
static func instantiate_standing(path: String, target_height: float) -> Node3D:
	var node := instantiate(path)
	if node == null:
		return null
	var box := body_aabb(path)
	if target_height > 0.0 and box.size.y > 0.0:
		node.scale = node.scale * (target_height / box.size.y)
	return node


## Folds the geometry under [param xform] into the running bounds.
static func _walk(node: Node, xform: Transform3D) -> void:
	for child: Node in node.get_children():
		var local := xform
		if child is Node3D:
			local = xform * (child as Node3D).transform
		if child is VisualInstance3D:
			var box := local * (child as VisualInstance3D).get_aabb()
			if _bounds.size == Vector3.ZERO:
				_bounds = box
			else:
				_bounds = _bounds.merge(box)
		_walk(child, local)


## Whether [param tint] would make a model look different.
##
## A content author leaving a tint blank means "no tint", and white is the default of
## every tint field in the project. Calling [method apply_tint] with it would still be
## *correct* — multiplying by one changes nothing — but it duplicates every material on
## the model to achieve that, so callers ask first. Both channels are compared because
## alpha is ignored: a fully transparent tint is a bug, not a request to hide the model.
static func is_white(tint: Color) -> bool:
	return is_equal_approx(tint.r, 1.0) and is_equal_approx(tint.g, 1.0) \
		and is_equal_approx(tint.b, 1.0)


## Multiplies every material's albedo under [param root] by [param tint].
##
## How one model becomes several: an iron vein is the same grey boulder in another
## colour, and a villager is one of five CC0 bodies recoloured.
##
## [member GeometryInstance3D.material_override] rather than editing the shared
## resource, because the same model is instanced many times over — one rock per
## boulder, one Knight per knight — and overwriting the shared material would tint
## every other instance in the valley at once. The per-surface duplicate is what
## makes tinting one instance cheap and local, and it is cached by (source, tint) so
## that eighty trees of one kind share one duplicated material instead of owning
## eighty identical copies.
##
## A white tint is treated as "no tint" by the caller rather than here, because
## duplicating every material to multiply it by one is pure cost.
static func apply_tint(root: Node, tint: Color) -> void:
	if root == null:
		return
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			var geometry := child as GeometryInstance3D
			# `mesh.surface_get_material`, not something on the instance: the instance
			# holds no surfaces, it draws the ones its Mesh has.
			var source := geometry.material_override
			if source == null and geometry.mesh != null and geometry.mesh.get_surface_count() > 0:
				source = geometry.mesh.surface_get_material(0)
			if source is StandardMaterial3D:
				geometry.material_override = _tinted(source as StandardMaterial3D, tint)
		apply_tint(child, tint)


## The tinted counterpart of [param source], shared between every instance that
## wants the same tint.
static func _tinted(source: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var key := "%d_%s" % [source.get_instance_id(), tint.to_html(true)]
	if _tints.has(key):
		return _tints[key]
	var copy := source.duplicate() as StandardMaterial3D
	copy.albedo_color = source.albedo_color * tint
	copy.resource_local_to_scene = true
	_tints[key] = copy
	return copy


## Drops the caches. Only for tests that assert on cache behaviour or that need a
## model re-measured after changing an import setting.
static func clear_cache() -> void:
	_scenes.clear()
	_heights.clear()
	_aabbs.clear()
	_body_aabbs.clear()
	_root_scales.clear()
	_tints.clear()