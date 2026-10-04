extends TestSuite
## World construction - Group 3 follow-up (procedural world integrity).
##
## Guards the specific failure that visual and collision geometry are generated
## from *different* random sequences, which produces visible-but-not-solid trees.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _world: Node3D = null


func is_async() -> bool:
	return true


func setup() -> void:
	_world = null


func teardown() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null


func get_cases() -> Array[StringName]:
	return [
		&"world_builds_expected_regions",
		&"gatherable_visual_and_collider_counts_match",
		&"gatherable_colliders_sit_on_their_own_model",
		&"no_decorative_trees_are_left_in_the_valley",
		&"ground_supports_the_spawn_point",
		&"every_graphics_tier_names_only_properties_that_exist",
		&"the_configured_tier_is_applied_to_the_live_environment",
		&"lowering_the_tier_actually_turns_effects_off",
		&"an_out_of_range_tier_is_clamped_rather_than_treated_as_high",
		&"the_day_night_cycle_still_owns_the_ambient_light",
		&"every_named_surface_has_a_material_and_an_unknown_one_is_null",
		&"every_surface_carries_the_shared_detail_texture",
		&"world_meshes_share_material_instances_rather_than_making_their_own",
		&"the_ground_is_tinted_and_not_one_flat_green",
		&"the_pond_basin_tint_actually_differs_from_the_field",
		&"the_world_is_built_from_the_library_and_not_from_the_old_helper",
		&"every_decoration_is_scattered_at_its_full_count",
		&"the_same_seed_scatters_the_same_scenery_twice",
		&"no_decoration_stands_where_something_already_is",
		&"only_collidable_scenery_has_a_collider",
		&"batched_scenery_costs_one_node_not_one_per_tuft",
		&"no_decoration_is_also_a_gatherable",
	]


func _build() -> Node3D:
	var packed := load(WORLD_SCENE) as PackedScene
	if packed == null:
		return null
	_world = packed.instantiate()
	root().add_child(_world)
	await _step(3)
	return _world


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


## The valley's gatherables.
func _field() -> ResourceField:
	return _find_field(_world)


static func _find_field(from: Node) -> ResourceField:
	if from == null:
		return null
	if from is ResourceField:
		return from as ResourceField
	for child: Node in from.get_children():
		var found := _find_field(child)
		if found != null:
			return found
	return null


## The children of [param node] sitting on [param layer].
static func _bodies_on(node: Node, layer: int) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child: Node in node.get_children():
		if child is StaticBody3D and (child as StaticBody3D).collision_layer == layer:
			out.append(child as StaticBody3D)
	return out


static func _shape_of(body: StaticBody3D) -> Shape3D:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).shape
	return null


## How many visible meshes [param node] draws while it is standing.
##
## Walked rather than counted on direct children, because an imported FBX is a
## [Node3D] root wrapping a [MeshInstance3D] — `ModelArt` keeps that root intact
## because the unit conversion lives on its scale, so a "direct children only" count
## reads zero on a perfectly good model. The first version of this case did exactly
## that and reported a broken valley for 145 correct nodes before failing on the
## first one it could not match.
##
## Inherited visibility is tracked rather than read off each instance, because
## `Node3D.visible` is local: a mesh under a hidden stump still says `visible == true`.
## That is what keeps a depleted tree counting as zero models instead of two.
static func _visual_count(node: Node, inherited_visible: bool = true) -> int:
	var count := 0
	var shown := inherited_visible
	if node is Node3D:
		shown = inherited_visible and (node as Node3D).visible
	if node is MeshInstance3D and shown:
		count += 1
	for child: Node in node.get_children():
		count += _visual_count(child, shown)
	return count


func _t_regions() -> Dictionary:
	var c := &"world_builds_expected_regions"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	for node_name: String in ["Ground", "Pond", "FarmSoil", "VillageWell", "NoticeBoard", "SupplyCrate"]:
		if world.get_node_or_null(NodePath(node_name)) == null:
			return fail(c, "missing region node '%s'" % node_name)
	return succeeded(c, "all regions present")


## One model, one solid collider, one aim volume, one component — per node.
##
## The old version of this case compared multimesh instance counts with capsule
## counts, because that was what the valley used to be made of. It could not survive
## the move to [ResourceField], and the naive port — "does the node have a collider?"
## — would have passed on a node with two, or on a forest with none. So the invariant
## is stated per node and checked on all four axes.
func _t_counts_match() -> Dictionary:
	var c := &"gatherable_visual_and_collider_counts_match"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var field := _field()
	if field == null:
		return fail(c, "world contains no ResourceField")
	if field.count() == 0:
		return fail(c, "ResourceField is empty; the valley has nothing to gather")

	var trees := 0
	for node: ResourceNode in field.nodes:
		if node.data != null and node.data.category == ResourceNodeData.Category.TREE:
			trees += 1
		if _visual_count(node) != 1:
			return fail(c, "%s draws %d models, expected exactly 1" % [
				node.name, _visual_count(node),
			])
		var solid := _bodies_on(node, PhysicsLayers.WORLD)
		if solid.size() != 1:
			return fail(c, "%s has %d solid bodies, expected 1" % [node.name, solid.size()])
		var aim := _bodies_on(node, PhysicsLayers.INTERACTABLE)
		if aim.size() != 1:
			return fail(c, "%s has %d aim volumes, expected 1" % [node.name, aim.size()])
		var components := 0
		for child: Node in aim[0].get_children():
			if child is Interactable:
				components += 1
		if components != 1:
			return fail(c, "%s has %d interaction components, expected 1" % [
				node.name, components,
			])
		if _shape_of(aim[0]) == null or _shape_of(solid[0]) == null:
			return fail(c, "%s has a body with no collision shape" % node.name)

	if trees == 0:
		return fail(c, "no trees were placed; the valley has no wood")
	return succeeded(c, "%d nodes (%d trees), each with 1 model, 1 solid, 1 aim" % [
		field.count(), trees,
	])


## Every collider stands on the artwork it belongs to.
##
## What the multimesh version had to *infer* — nearest-site matching, in case the two
## came from different random sequences — is structural now: a node's collider is its
## own child, so they cannot be placed independently. What is left to check is the
## part that can still go wrong silently, and did, when colliders were authored by
## hand: a collider that floats above the ground, one wider than the model it is
## meant to be, and one the aim volume does not cover.
func _t_colliders_aligned() -> Dictionary:
	var c := &"gatherable_colliders_sit_on_their_own_model"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var field := _field()
	if field == null:
		return fail(c, "world contains no ResourceField")

	for node: ResourceNode in field.nodes:
		if node.data == null:
			return fail(c, "%s has no definition" % node.name)
		if node.footprint() <= 0.0:
			return fail(c, "%s has no measurable model" % node.name)
		var solid := _bodies_on(node, PhysicsLayers.WORLD)[0]
		var aim := _bodies_on(node, PhysicsLayers.INTERACTABLE)[0]
		var solid_shape := _shape_of(solid) as CylinderShape3D
		var aim_shape := _shape_of(aim) as CylinderShape3D
		if solid_shape == null or aim_shape == null:
			return fail(c, "%s is not collider-shaped" % node.name)

		# On the ground, not sunk into it and not floating.
		if absf(solid.position.y) > 0.001:
			return fail(c, "%s solid sits at y=%.3f, expected the ground at 0" % [
				node.name, solid.position.y,
			])
		if solid_shape.height > node.height() + 0.001:
			return fail(c, "%s collider is %.2fm tall for a %.2fm model" % [
				node.name, solid_shape.height, node.height(),
			])
		# Inside the model, never wider than it.
		if solid_shape.radius > node.footprint() * 0.5 + 0.001:
			return fail(c, "%s collider is %.2fm wide for a %.2fm model" % [
				node.name, solid_shape.radius * 2.0, node.footprint(),
			])
		# Aimable. A solid the ray cannot reach is a tree the player can walk into
		# and not swing at.
		if aim_shape.radius < solid_shape.radius:
			return fail(c, "%s aim volume is narrower than its own collider" % node.name)
		if aim_shape.height + 0.001 < solid_shape.height:
			return fail(c, "%s aim volume is shorter than its own collider" % node.name)

		# And standing on the terrain, which for everything outside the pond is y=0.
		if node.position.y > 0.001:
			return fail(c, "%s was placed at y=%.3f" % [node.name, node.position.y])
	return succeeded(c, "all %d colliders sit on their own model" % field.count())


## Nothing in the valley is scenery pretending to be a tree.
##
## The specific regression [Group 12] fixed: a grove of cylinder-and-sphere trees the
## player could see and not touch. Cheap to assert, and it is the failure a player
## would report as "some trees don't work".
func _t_no_decorative_trees() -> Dictionary:
	var c := &"no_decorative_trees_are_left_in_the_valley"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	for legacy: String in ["ForestTrunks", "ForestCanopies"]:
		if world.get_node_or_null(NodePath(legacy)) != null:
			return fail(c, "%s still exists; it draws trees that cannot be gathered" % legacy)
	var field := _field()
	if field == null:
		return fail(c, "world contains no ResourceField")
	var trees := 0
	for node: ResourceNode in field.nodes:
		if node.data != null and node.data.category == ResourceNodeData.Category.TREE:
			trees += 1
	if trees == 0:
		return fail(c, "the valley has no trees at all")
	return succeeded(c, "%d gatherable trees, no decorative ones" % trees)


func _t_ground_supports_spawn() -> Dictionary:
	var c := &"ground_supports_the_spawn_point"
	var world := await _build()
	if world == null:
		return fail(c, "could not instantiate world scene")
	var world_root := world as WorldRoot
	if world_root == null:
		return fail(c, "world scene root is not a WorldRoot")
	var spawn: Vector3 = world_root.get_spawn_point()

	# Cast down from above the spawn and require it to hit the ground rather
	# than falling through the world.
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return fail(c, "no physics space")
	var query := PhysicsRayQueryParameters3D.create(
		spawn + Vector3.UP * 5.0, spawn + Vector3.DOWN * 50.0, 1
	)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fail(c, "nothing under the spawn point %s - the player would fall" % spawn)
	# The ground top sits at y=0.
	if absf(hit["position"].y) > 0.5:
		return fail(c, "ground under spawn is at y=%.2f, expected ~0" % hit["position"].y)
	return succeeded(c, "spawn %s rests on ground at y=%.2f" % [spawn, hit["position"].y])


# --- Graphics quality -----------------------------------------------------
#
# The tier table is the one place in the project that decides what "high" means.
# Every failure below is a table typo, a property that no longer exists after a
# Godot upgrade, or a value silently not reaching the renderer. All three look
# identical in-game: the setting changes and nothing happens.


func _graphics() -> Node:
	if _world == null:
		return null
	return _world.get_node_or_null(^"Graphics")


func _world_environment() -> Environment:
	if _world == null:
		return null
	var node := _world.get_node_or_null(^"Environment") as WorldEnvironment
	return node.environment if node != null else null


## Every key in every tier must be a real property on the environment, the sun,
## or the one viewport key we handle by name.
##
## The probe light is freed explicitly, and only the light: a [DirectionalLight3D] is
## not a [Resource], so constructing one allocates a renderer light instance
## immediately, even outside the scene tree, and leaving it to the exit-time leak check
## is how a suite that asserts "nothing leaked" becomes the thing that leaks — failing
## `check.ps1` on a line nobody can attribute to anything they wrote that day. The
## [Environment] is refcounted and simply goes out of scope; `free()` on it is an
## error, not a tidy-up.
func _t_tier_keys_exist() -> Dictionary:
	var c := &"every_graphics_tier_names_only_properties_that_exist"
	var known := {}
	var missing := ""
	var sun := DirectionalLight3D.new()
	known = _property_names(Environment.new())
	var sun_known := _property_names(sun)
	known["msaa"] = true
	for tier: int in GraphicsQuality.TIERS:
		for key: String in GraphicsQuality.TIERS[tier]:
			if not (known.has(key) or sun_known.has(key)):
				missing = "tier %s names '%s', which no node has" % [
					GraphicsQuality.tier_name(tier), key
				]
				break
		if not missing.is_empty():
			break
	sun.free()
	if not missing.is_empty():
		return fail(c, missing)
	return succeeded(c, "all three tiers name only real properties (%d checked)" % _tier_key_count())


static func _tier_key_count() -> int:
	var count := 0
	for tier: int in GraphicsQuality.TIERS:
		count += (GraphicsQuality.TIERS[tier] as Dictionary).size()
	return count


static func _property_names(target: Object) -> Dictionary:
	var names := {}
	for property: Dictionary in target.get_property_list():
		names[String(property["name"])] = true
	return names


## The tier a fresh world boots into must actually be on its environment — not
## merely present in the table. This is the case that catches "applied to the
## wrong object" and "applied before the environment existed".
func _t_tier_applied() -> Dictionary:
	var c := &"the_configured_tier_is_applied_to_the_live_environment"
	await _build()
	var quality := _graphics() as GraphicsQuality
	if quality == null:
		return fail(c, "the world has no Graphics node - was the world scene regenerated?")
	if not quality.is_configured():
		return fail(c, "Graphics found no Environment to configure")
	var env := _world_environment()
	if env == null:
		return fail(c, "the world has no environment")
	var expected: Dictionary = GraphicsQuality.TIERS[quality.current_tier()]
	if not bool(expected["ssao_enabled"]) and env.ssao_enabled:
		return fail(c, "tier %s leaves SSAO off but the environment has it on" % quality.current_tier())
	if bool(expected["ssao_enabled"]) and not env.ssao_enabled:
		return fail(c, "tier %s wants SSAO but the environment does not have it" % quality.current_tier())
	if not bool(expected["glow_enabled"]) and env.glow_enabled:
		return fail(c, "tier %s leaves glow off but the environment has it on" % quality.current_tier())
	# The tonemap is the one value that is on at every tier, so it can be asserted
	# outright rather than only in the negative.
	if env.tonemap_mode != Environment.TONE_MAPPER_ACES:
		return fail(c, "tonemap is %d, expected ACES" % env.tonemap_mode)
	return succeeded(c, "tier %s is live on the environment" % GraphicsQuality.tier_name(quality.current_tier()))


## Dropping the tier must switch things *off*, not merely change a number. A
## tier table where "low" is high with smaller numbers is the classic failure,
## and it is invisible unless something is asserted after the change.
func _t_tier_lowers_effects() -> Dictionary:
	var c := &"lowering_the_tier_actually_turns_effects_off"
	await _build()
	var quality := _graphics() as GraphicsQuality
	if quality == null or not quality.is_configured():
		return fail(c, "no configured Graphics node to drive")
	var env := _world_environment()
	var config := autoload(&"Config")
	var previous: int = int(config.settings.graphics_quality)
	config.settings.graphics_quality = GraphicsQuality.Tier.HIGH
	quality.apply()
	if not env.ssao_enabled or not env.glow_enabled:
		return fail(c, "high should have both SSAO and glow on, got ssao=%s glow=%s" % [
			env.ssao_enabled, env.glow_enabled
		])
	config.settings.graphics_quality = GraphicsQuality.Tier.LOW
	quality.apply()
	if env.ssao_enabled:
		return fail(c, "low left SSAO on")
	if env.glow_enabled:
		return fail(c, "low left glow on")
	if env.fog_enabled:
		return fail(c, "low left fog on")
	config.settings.graphics_quality = previous
	quality.apply()
	return succeeded(c, "high had SSAO+glow+fog, low had none of the three")


## A config file is a text file a person can edit. A typo'd 7 must not resolve
## to the last entry in the table and turn on everything.
func _t_tier_clamped() -> Dictionary:
	var c := &"an_out_of_range_tier_is_clamped_rather_than_treated_as_high"
	await _build()
	var quality := _graphics() as GraphicsQuality
	if quality == null:
		return fail(c, "no Graphics node to ask")
	var config := autoload(&"Config")
	var previous: int = int(config.settings.graphics_quality)
	config.settings.graphics_quality = 7
	if quality.current_tier() != GraphicsQuality.Tier.HIGH:
		return fail(c, "7 did not clamp to high, got %d" % quality.current_tier())
	config.settings.graphics_quality = -3
	if quality.current_tier() != GraphicsQuality.Tier.LOW:
		return fail(c, "-3 did not clamp to low, got %d" % quality.current_tier())
	config.settings.graphics_quality = previous
	return succeeded(c, "7 -> high, -3 -> low")


## [GraphicsQuality] must not write anything the day/night cycle also owns, or
## the two overwrite each other every frame and the valley flickers.
func _t_ambient_left_alone() -> Dictionary:
	var c := &"the_day_night_cycle_still_owns_the_ambient_light"
	for tier: int in GraphicsQuality.TIERS:
		var table: Dictionary = GraphicsQuality.TIERS[tier]
		for contested: String in [
			"ambient_light_energy",
			"ambient_light_source",
			"background_mode",
			"sky",
			"background_energy_multiplier",
		]:
			if table.has(contested):
				return fail(c, "tier %s writes '%s', which DayNightCycle owns" % [
					GraphicsQuality.tier_name(tier), contested
				])
	return succeeded(c, "no tier writes a property DayNightCycle owns")


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"world_builds_expected_regions":
			return await _t_regions()
		&"gatherable_visual_and_collider_counts_match":
			return await _t_counts_match()
		&"gatherable_colliders_sit_on_their_own_model":
			return await _t_colliders_aligned()
		&"no_decorative_trees_are_left_in_the_valley":
			return await _t_no_decorative_trees()
		&"ground_supports_the_spawn_point":
			return await _t_ground_supports_spawn()
		&"every_graphics_tier_names_only_properties_that_exist":
			return _t_tier_keys_exist()
		&"the_configured_tier_is_applied_to_the_live_environment":
			return await _t_tier_applied()
		&"lowering_the_tier_actually_turns_effects_off":
			return await _t_tier_lowers_effects()
		&"an_out_of_range_tier_is_clamped_rather_than_treated_as_high":
			return await _t_tier_clamped()
		&"the_day_night_cycle_still_owns_the_ambient_light":
			return _t_ambient_left_alone()
		&"every_named_surface_has_a_material_and_an_unknown_one_is_null":
			return _t_surfaces_resolve()
		&"every_surface_carries_the_shared_detail_texture":
			return _t_surfaces_have_detail()
		&"world_meshes_share_material_instances_rather_than_making_their_own":
			return await _t_materials_shared()
		&"the_ground_is_tinted_and_not_one_flat_green":
			return await _t_ground_is_tinted()
		&"the_pond_basin_tint_actually_differs_from_the_field":
			return _t_basin_tint_differs()
		&"the_world_is_built_from_the_library_and_not_from_the_old_helper":
			return await _t_world_uses_the_library()
		&"every_decoration_is_scattered_at_its_full_count":
			return await _t_decorations_place_in_full()
		&"the_same_seed_scatters_the_same_scenery_twice":
			return await _t_decorations_deterministic()
		&"no_decoration_stands_where_something_already_is":
			return await _t_decorations_clear_of_reserved()
		&"only_collidable_scenery_has_a_collider":
			return await _t_decoration_colliders()
		&"batched_scenery_costs_one_node_not_one_per_tuft":
			return await _t_decorations_batched()
		&"no_decoration_is_also_a_gatherable":
			return _t_decorations_are_not_gatherables()
	return fail(case, "no case implementation for %s" % case)

# --- Materials -------------------------------------------------------------
#
# Every one of these asserts on the *shared library* rather than on the values
# a particular mesh ended up with. The failure this guards against is the quiet
# one: a surface that keeps its flat colour because the call site was rewritten to
# the old helper and nobody opened the game.


## Every declared surface resolves, and a name that does not exist does not.
##
## Null rather than a fallback: a typo returning wood where the author meant glass
## is exactly the kind of bug that is invisible until someone plays it.
func _t_surfaces_resolve() -> Dictionary:
	var c := &"every_named_surface_has_a_material_and_an_unknown_one_is_null"
	var names := WorldMaterials.surface_names()
	if names.is_empty():
		return fail(c, "the surface table is empty")
	for surface: StringName in names:
		var m := WorldMaterials.surface(surface)
		if m == null:
			return fail(c, "surface '%s' is declared but resolves to null" % surface)
		if m.albedo_texture == null:
			return fail(c, "surface '%s' has no albedo texture" % surface)
	if WorldMaterials.surface(&"not_a_surface") != null:
		return fail(c, "an unknown surface name returned a material instead of null")
	return succeeded(c, "%d surfaces resolve, unknown names return null" % names.size())


## One shared detail texture, not one per surface: nine simultaneous 256x256
## generations at world build for a difference nobody can see.
func _t_surfaces_have_detail() -> Dictionary:
	var c := &"every_surface_carries_the_shared_detail_texture"
	var shared := WorldMaterials.detail_texture()
	if shared == null:
		return fail(c, "no shared detail texture")
	if not shared.seamless:
		return fail(c, "the detail texture is not seamless; it will tile visibly")
	for surface: StringName in WorldMaterials.surface_names():
		var m := WorldMaterials.surface(surface)
		if m.albedo_texture != shared:
			return fail(c, "surface '%s' has its own texture instead of the shared one" % surface)
		if m.uv1_scale.x <= 0.0:
			return fail(c, "surface '%s' has a uv1_scale of %f, so the texture cannot tile" % [surface, m.uv1_scale.x])
	return succeeded(c, "%d surfaces share one seamless detail texture" % WorldMaterials.surface_names().size())


## Repeated instances of one mesh must not each own a private material.
##
## The first version of this asserted a ratio of distinct materials to meshes, and
## failed at 104 across 263. That was the assertion being wrong, not the world: a
## valley built from twenty imported CC0 models legitimately has ~20 sets of authored
## materials, and 96 is about right. The defect it was *meant* to catch is a
## per-instance duplicate — the tint path in [ModelArt] was making one copy per tree,
## so a wood of eighty identical trees owned eighty identical materials.
##
## So this counts per *mesh resource*: if five or more meshes share one mesh, they
## must share one material.
func _t_materials_shared() -> Dictionary:
	var c := &"world_meshes_share_material_instances_rather_than_making_their_own"
	await _build()
	var by_mesh: Dictionary = {}
	for mesh: MeshInstance3D in _collect_meshes(_world):
		if mesh.mesh == null:
			continue
		var material := mesh.material_override
		if material == null and mesh.mesh.get_surface_count() > 0:
			material = mesh.mesh.surface_get_material(0)
		if material == null:
			continue
		var id := mesh.mesh.get_instance_id()
		if not by_mesh.has(id):
			by_mesh[id] = {"meshes": 0, "materials": {}}
		by_mesh[id]["meshes"] += 1
		by_mesh[id]["materials"][material.get_instance_id()] = true
	var duplicated := 0
	var checked := 0
	for id: int in by_mesh:
		var group: Dictionary = by_mesh[id]
		if int(group["meshes"]) < 5:
			continue
		checked += 1
		if (group["materials"] as Dictionary).size() > 1:
			duplicated += 1
	if by_mesh.is_empty():
		return fail(c, "no mesh in the world has a material at all")
	if checked == 0:
		return fail(c, "no mesh is instanced five or more times, so this asserts nothing")
	if duplicated > 0:
		return fail(c, "%d of %d repeated meshes own more than one material between them" % [duplicated, checked])
	return succeeded(c, "%d repeated meshes, none duplicating its material (%d distinct meshes overall)" % [checked, by_mesh.size()])


## The ground must carry per-vertex tint, and the tint must actually vary.
##
## The first version of this ramped on elevation, which is 0.0 at all but the pond
## basin - a gradient that exists in the code and cannot be seen. So the assertion is
## on the *spread* of the colours, not merely on the array being present.
func _t_ground_is_tinted() -> Dictionary:
	var c := &"the_ground_is_tinted_and_not_one_flat_green"
	await _build()
	var ground := _world.get_node_or_null(^"Ground") as StaticBody3D
	if ground == null:
		return fail(c, "the world has no Ground body")
	var mesh := ground.get_node_or_null(^"GroundMesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return fail(c, "the ground has no mesh")
	var array := mesh.mesh.surface_get_arrays(0)
	if array.is_empty():
		return fail(c, "the ground mesh has no surface arrays")
	var colors: PackedColorArray = array[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		return fail(c, "the ground mesh has no vertex colours, so it is still one flat green")
	var lowest := Color(9, 9, 9, 9)
	var highest := Color(-9, -9, -9, -9)
	for value: Color in colors:
		lowest = Color(minf(lowest.r, value.r), minf(lowest.g, value.g), minf(lowest.b, value.b), 1.0)
		highest = Color(maxf(highest.r, value.r), maxf(highest.g, value.g), maxf(highest.b, value.b), 1.0)
	if lowest.is_equal_approx(highest):
		return fail(c, "all %d ground vertices share the colour %s" % [colors.size(), lowest])
	if not (lowest.r <= 1.0 and highest.r >= 1.0):
		return fail(c, "the tint never straddles white, so it is a shift not a modulation: %s..%s" % [lowest, highest])
	return succeeded(c, "%d vertices tinted from %s to %s" % [colors.size(), lowest, highest])


## The shoreline gradient has to differ from open field, or the pond is a green field
## with a blue disc dropped on it.
func _t_basin_tint_differs() -> Dictionary:
	var c := &"the_pond_basin_tint_actually_differs_from_the_field"
	var field := WorldBuilder.ground_tint(60.0, 60.0, WorldBuilder.GROUND_LEVEL)
	var deep := WorldBuilder.ground_tint(
		WorldBuilder.REGION_POND.x, WorldBuilder.REGION_POND.y, WorldBuilder.POND_FLOOR_DEPTH
	)
	var shallow := WorldBuilder.ground_tint(
		WorldBuilder.REGION_POND.x + WorldBuilder.POND_RADIUS * 0.6,
		WorldBuilder.REGION_POND.y,
		WorldBuilder.terrain_height(
			WorldBuilder.REGION_POND.x + WorldBuilder.POND_RADIUS * 0.6, WorldBuilder.REGION_POND.y
		),
	)
	if deep.is_equal_approx(field):
		return fail(c, "the pond floor is tinted exactly like the field")
	if shallow.is_equal_approx(deep):
		return fail(c, "the pond slope is one flat tint from rim to floor")
	if deep.get_luminance() >= shallow.get_luminance():
		return fail(c, "the deep floor is not darker than the slope (%.3f vs %.3f)" % [
			deep.get_luminance(), shallow.get_luminance()
		])
	return succeeded(c, "field %s, slope %s, floor %s" % [field, shallow, deep])


## Every [MeshInstance3D] under a node, at any depth.
static func _collect_meshes(from: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if from == null:
		return out
	if from is MeshInstance3D:
		out.append(from as MeshInstance3D)
	for child: Node in from.get_children():
		out.append_array(_collect_meshes(child))
	return out

## The primitives the builder makes must be wearing the library's materials, not a
## hand-rolled one from the old helper.
##
## The library's surfaces are the only materials in this project with a detail
## texture on them, so "has the shared detail texture" is exactly "came from the
## library". This is the test that catches a call site being left behind during the
## rewrite - the kind of thing that leaves one flat fence post in an otherwise
## textured valley and is genuinely hard to spot by playing.
func _t_world_uses_the_library() -> Dictionary:
	var c := &"the_world_is_built_from_the_library_and_not_from_the_old_helper"
	await _build()
	var shared := WorldMaterials.detail_texture()
	var checked := 0
	var bare: Array[String] = []
	for mesh: MeshInstance3D in _collect_meshes(_world):
		# Imported CC0 models bring their own authored materials and are meant to.
		if mesh.mesh == null or not (mesh.mesh is PrimitiveMesh):
			continue
		var material := mesh.material_override
		if material == null:
			bare.append(mesh.name)
			continue
		checked += 1
		var standard := material as StandardMaterial3D
		if standard == null:
			bare.append(mesh.name)
		elif standard.albedo_texture != shared:
			bare.append(mesh.name)
	if bare.is_empty():
		return succeeded(c, "all %d primitives use the library" % checked)
	return fail(c, "%d primitives are not on the library, e.g. %s" % [bare.size(), ", ".join(bare.slice(0, 5))])

# --- Scenery ---------------------------------------------------------------
#
# Decoration is the easiest system in the project to get quietly wrong: nothing
# breaks, nothing errors, and a valley with no scenery is still a working valley.
# So these assert on counts, determinism and keep-outs rather than on "some
# nodes appeared".


func _scenery() -> DecorationField:
	return _world.get_node_or_null(^"DecorationField") as DecorationField if _world != null else null


## Every definition asks for a count. A definition that asks for twelve and places
## zero is a defect that logs one line and looks like a design choice.
##
## Two real ones were found by reading the boot log rather than by looking at the
## valley: the willows' region was the pond, which is entirely keep-out, and the
## ground cover was registering itself in the occupancy list and rejecting every
## willow as "too close to a blade of grass".
func _t_decorations_place_in_full() -> Dictionary:
	var c := &"every_decoration_is_scattered_at_its_full_count"
	await _build()
	var field := _scenery()
	if field == null:
		return fail(c, "the world has no DecorationField - was the world scene regenerated?")
	var short: Array[String] = []
	for data: DecorationData in DecorationRegistry.scatterable_decorations():
		var placed := 0
		if data.batched:
			var batch := field.batch(data.id)
			placed = batch.multimesh.instance_count if batch != null else 0
		else:
			placed = _count_children_named(field, "%s_" % data.id)
		if placed != data.spawn_count:
			short.append("%s placed %d of %d" % [data.id, placed, data.spawn_count])
	if short.is_empty():
		return succeeded(c, "every decoration placed its full count (%d props total)" % field.placed_count())
	return fail(c, "%d short: %s" % [short.size(), ", ".join(short)])


## Scenery is only reproducible if the generator's stream is. Placement is not saved,
## so a world rebuilt from a save would otherwise grow a different valley.
func _t_decorations_deterministic() -> Dictionary:
	var c := &"the_same_seed_scatters_the_same_scenery_twice"
	await _build()
	var first := _scenery_positions()
	# Build a second field from the same seed, next to the first rather than instead of
	# it, so the comparison is between two live fields.
	var second := DecorationField.new()
	second.name = "DecorationFieldProbe"
	second.seed_value = _scenery().seed_value
	root().add_child(second)
	await tree.process_frame
	var reread := _scenery_positions_of(second)
	second.queue_free()
	if first.size() != reread.size():
		return fail(c, "first build had %d props, second had %d" % [first.size(), reread.size()])
	for i: int in first.size():
		if not (first[i] as Vector3).is_equal_approx(reread[i] as Vector3):
			return fail(c, "prop %d moved between builds: %s vs %s" % [
				i, first[i], reread[i],
			])
	return succeeded(c, "%d props in identical positions across two builds" % first.size())


func _scenery_positions() -> Array[Vector3]:
	return _scenery_positions_of(_scenery())


## Every prop position under a field, batches included, in a stable order.
func _scenery_positions_of(field: DecorationField) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if field == null:
		return out
	for child: Node in _sorted_children(field):
		if child is MultiMeshInstance3D:
			var multimesh := (child as MultiMeshInstance3D).multimesh
			if multimesh != null:
				for i: int in multimesh.instance_count:
					# `.origin`, not the whole transform: this array is positions, and
					# pushing a Transform3D into it fails *silently* — the typed array
					# rejects the element and the batch's props quietly never get
					# compared, so the determinism test passed while checking 103 of
					# 831 props.
					out.append(
						((child as MultiMeshInstance3D).global_transform * multimesh.get_instance_transform(i)).origin
					)
		else:
			out.append((child as Node3D).global_position)
	return out


static func _sorted_children(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in from.get_children():
		out.append(child)
	out.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	return out


## Scenery must not stand where the player needs to be: not in the pond, not on a
## path, not inside the farm plot, and not inside a tree.
func _t_decorations_clear_of_reserved() -> Dictionary:
	var c := &"no_decoration_stands_where_something_already_is"
	await _build()
	var field := _scenery()
	if field == null:
		return fail(c, "no DecorationField")
	var gatherables: Array[Vector2] = []
	var resource_field := _world.get_node_or_null(^"ResourceField")
	if resource_field is ResourceField:
		for node: ResourceNode in (resource_field as ResourceField).nodes:
			gatherables.append(Vector2(node.position.x, node.position.z))
	# Only props that reserve space need to clear the gatherables; ground cover with
	# zero spacing is explicitly allowed to lie next to anything.
	var collidable: Array[Vector3] = []
	var names := {"thicket": true, "berry_bramble": true, "young_birch": true, "young_pine": true,
		"willow": true, "sapling_oak": true, "fallen_log": true}
	for child: Node3D in _decorated_props(field):
		if not names.has(String(child.name).replace("_prop", "")):
			continue
		collidable.append(child.global_position)
	var problems: Array[String] = []
	for at: Vector3 in collidable:
		var flat := Vector2(at.x, at.z)
		if WorldBuilder.is_reserved(flat):
			problems.append("%s is in a reserved zone at %s" % [at, flat])
		for other: Vector2 in gatherables:
			if flat.distance_to(other) < 0.5:
				problems.append("a prop at %s is inside a gatherable" % flat)
				break
	if problems.is_empty():
		return succeeded(c, "%d collidable props, none in a keep-out or inside a gatherable" % collidable.size())
	return fail(c, "%d problems, e.g. %s" % [problems.size(), problems[0]])


## A collider on grass is a wall you trip over at knee height; no collider on a tree
## is a wall you walk through. Both are the kind of thing only a test catches.
func _t_decoration_colliders() -> Dictionary:
	var c := &"only_collidable_scenery_has_a_collider"
	await _build()
	var field := _scenery()
	if field == null:
		return fail(c, "no DecorationField")
	var wrong: Array[String] = []
	var checked := 0
	for data: DecorationData in DecorationRegistry.scatterable_decorations():
		if data.batched:
			continue
		for child: Node in field.get_children():
			if not String(child.name).begins_with("%s_" % data.id):
				continue
			checked += 1
			var body := child as StaticBody3D
			var has_shape := false
			for grandchild: Node in child.get_children():
				if grandchild is CollisionShape3D:
					has_shape = true
			if data.collides and not has_shape:
				wrong.append("%s collides but has no shape" % data.id)
			if not data.collides and has_shape:
				wrong.append("%s does not collide but has a shape" % data.id)
	if checked == 0:
		return fail(c, "no non-batched props found to check")
	if wrong.is_empty():
		return succeeded(c, "%d props match their definition's collider flag" % checked)
	return fail(c, "%d wrong: %s" % [wrong.size(), ", ".join(wrong.slice(0, 4))])


## Batching is the difference between a few hundred nodes and a few. Asserted by
## counting nodes, because "the batch exists" says nothing about whether the
## non-batched path is still being taken.
func _t_decorations_batched() -> Dictionary:
	var c := &"batched_scenery_costs_one_node_not_one_per_tuft"
	await _build()
	var field := _scenery()
	if field == null:
		return fail(c, "no DecorationField")
	var batched_props := 0
	var batch_nodes := 0
	for data: DecorationData in DecorationRegistry.scatterable_decorations():
		if not data.batched:
			continue
		batched_props += data.spawn_count
		batch_nodes += 1
	var total_children := field.get_child_count()
	# The unbatched props are one node each; the batched ones are one node per kind.
	var unbatched_props := 0
	for data: DecorationData in DecorationRegistry.scatterable_decorations():
		if not data.batched:
			unbatched_props += data.spawn_count
	if total_children != unbatched_props + batch_nodes:
		return fail(c, "the field has %d nodes; expected %d unbatched props plus %d batches" % [
			total_children, unbatched_props, batch_nodes,
		])
	return succeeded(c, "%d batched props cost %d nodes; %d unbatched props cost %d" % [
		batched_props, batch_nodes, unbatched_props, unbatched_props,
	])


static func _decorated_props(field: DecorationField) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if field == null:
		return out
	for child: Node in field.get_children():
		if child is Node3D:
			out.append(child as Node3D)
	return out


static func _count_children_named(parent: Node, prefix: String) -> int:
	var count := 0
	for child: Node in parent.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
	return count


## Scenery must not be harvestable, and must not reuse a harvestable's model. A
## shared model makes the same tree both choppable and scenery, and which one the
## player gets depends on which builder runs second.
func _t_decorations_are_not_gatherables() -> Dictionary:
	var c := &"no_decoration_is_also_a_gatherable"
	var harvestable: Dictionary = {}
	for data: ResourceNodeData in ResourceNodeRegistry.all_nodes():
		harvestable[data.model] = true
		harvestable[data.depleted_model] = true
	for data: DecorationData in DecorationRegistry.all_decorations():
		if harvestable.has(data.model):
			return fail(c, "'%s' uses %s, which a gatherable also draws" % [data.id, data.model.get_file()])
		if not data.is_valid():
			return fail(c, "'%s' is not a valid definition" % data.id)
		# A scenery definition with a tool action would be a harvestable in everything
		# but name.
		if "yields" in data:
			return fail(c, "'%s' carries yields, so it is not scenery" % data.id)
	return succeeded(c, "%d decorations, none sharing a gatherable's model" % DecorationRegistry.all_decorations().size())