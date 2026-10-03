class_name ResourceNode
extends Node3D
## One gatherable thing standing in the world: an oak, a boulder, a berry bush.
##
## The node owns its *art* and its *solid* collider and nothing else. It does not
## build its own interaction volume, because the component that does has to name this
## type and naming a type in both directions is how two scripts end up unable to
## load each other — [ResourceField] adds the aim volume and the component instead,
## which also keeps the counting honest: one node, one collider, one interactable,
## and a test can walk the tree and say so.
##
## ## What "depleted" looks like
##
## A node is never removed from the world. It swaps to [member ResourceNodeData.depleted_model]
## — a stump for a tree, nothing at all for forage — and keeps its aim volume, so
## the player can still aim at the stump and be told it is regrowing. Removing it
## would leave the player pressing E at empty air with no explanation, and the
## failure event that is supposed to explain it would have no node to name.
##
## The solid collider is switched off while depleted. A trunk-sized cylinder left
## standing where the trunk is not is a wall the player cannot see the reason for.

## Emitted when a swing lands but does not break the node.
signal hit_registered(hits_left: int, hits_max: int)
## Emitted when the node gives out. Carries the world position so listeners can put
## a sound or a burst of splinters where the tree actually was.
signal depleted_at(position: Vector3)
## Emitted when the node comes back on its own timer.
signal respawned()

## What kind of thing this is. Null only in the window between construction and
## [method build], which nothing observes.
var data: ResourceNodeData = null

## Which placed copy of [member data] this is. Zero-based within the field, and the
## only thing that tells two oaks apart in a save.
var site_index: int = -1

## Swings landed against it so far. Persisted, so a save taken two swings into a
## four-swing oak does not heal it.
var hits_taken: int = 0

## Whole days until it returns. Zero while it is standing.
var respawn_days_left: int = 0

## Where it is depleted, i.e. standing as a stump or not there at all.
var depleted: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _solid: StaticBody3D = null
var _solid_shape: CollisionShape3D = null
var _model: Node3D = null
var _depleted_model: Node3D = null
var _box: AABB = AABB()


## Builds the node from [param definition], as placed copy number [param index].
##
## Called by [ResourceField] before the node enters the tree, so that a caller who
## adds it gets a fully formed node in one step and a test can build a node without
## a field at all.
func build(definition: ResourceNodeData, index: int) -> void:
	data = definition
	site_index = index
	if data == null:
		# Nothing sensible to stand up. The field logs the real problem; this node
		# just refuses to pretend.
		return
	# Seeded from the node's own identity rather than from a shared stream, so a
	# node's drops do not change when a *different* node is added to the field, and
	# the same world rebuilt from the same seed drops the same wood every time.
	_rng.seed = int(hash("%s#%d" % [data.id, site_index]))
	_box = ModelArt.natural_aabb(data.model)
	_build_model()
	_build_solid()
	set_meta(&"resource_node_id", data.id)


## Builds [method data]'s model, standing on this node's origin.
##
## Offset by the measured box rather than trusted to be centred already: the nature
## pack's pivots are inconsistent about where they sit, and a tree hovering a
## centimetre above the ground with its trunk hovering to one side is the sort of
## thing nobody reports and everybody sees.
func _build_model() -> void:
	_model = ModelArt.instantiate(data.model)
	if _model == null:
		# The content test asserts the path loads, so this only happens if a
		# definition was authored after the tests ran.
		Log.warn("Gathering", "node %s has no model at %s" % [data.id, data.model])
		return
	_model.name = "Model"
	if _box.size != Vector3.ZERO:
		_model.position = -_box.position
	if not ModelArt.is_white(data.model_tint):
		ModelArt.apply_tint(_model, data.model_tint)
	add_child(_model)


## A cylinder over the lower part of the artwork, on the solid world layer.
##
## Sized from [method ModelArt.natural_aabb] rather than typed into the `.tres`, and
## capped in height, because a collider that follows a 4 m oak all the way up is an
## invisible wall at head height. Trees get a trunk-sized pillar; boulders get all of
## themselves.
func _build_solid() -> void:
	var footprint := maxf(_box.size.x, _box.size.z)
	if footprint <= 0.0:
		return
	var radius := maxf(footprint * 0.5 * data.collider_radius_scale, 0.05)
	var height := clampf(minf(_box.size.y, 1.25), 0.2, 4.0)
	_solid = StaticBody3D.new()
	_solid.name = "Solid"
	_solid.collision_layer = PhysicsLayers.WORLD
	_solid.collision_mask = 0
	_solid_shape = CollisionShape3D.new()
	# Named rather than left blank. `add_child` accepts an unnamed node and Godot
	# invents nothing for it, so `Solid/CollisionShape3D` does not resolve — which
	# matters because that is the path the world test and the save checks walk, and a
	# path that silently resolves to nothing reports a healthy node as having no
	# collider.
	_solid_shape.name = "CollisionShape3D"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	_solid_shape.shape = cylinder
	_solid_shape.position = Vector3(0.0, height * 0.5, 0.0)
	_solid.add_child(_solid_shape)
	add_child(_solid)


func _ready() -> void:
	# `build` runs before the node is parented, by [ResourceField], so there is
	# nothing to do here. Deliberately empty rather than absent: a node in this
	# project that has no `_ready` reads like an oversight, and the next person to
	# add one wants to know this was considered.
	pass


## The solid collider's radius, or 0 when the node has no geometry to size one from.
func solid_radius() -> float:
	return _solid_shape.shape.radius if _solid_shape != null and _solid_shape.shape is CylinderShape3D else 0.0


## Height of the solid part. Deliberately not the model's full height; see
## [method _build_solid].
func solid_height() -> float:
	return _solid_shape.shape.height if _solid_shape != null and _solid_shape.shape is CylinderShape3D else 0.0


## How wide the interaction volume should be. Wider than the solid part on purpose:
## you should be able to aim at a canopy without standing inside the trunk.
func aim_radius() -> float:
	var footprint := maxf(_box.size.x, _box.size.z)
	if footprint <= 0.0:
		return 0.5
	return maxf(footprint * 0.5 * data.aim_radius_scale, 0.15)


## How tall the interaction volume is: the whole model, so the ray can find a tree
## from its crown.
func aim_height() -> float:
	return maxf(_box.size.y, 0.3)


## The width of the model, for tests and for spacing checks.
func footprint() -> float:
	return maxf(_box.size.x, _box.size.z)


## The measured model height, for the same reason.
func height() -> float:
	return _box.size.y


func hits_required(tier: int = 0) -> int:
	return data.hits_required(tier) if data != null else 1


func hits_left(tier: int = 0) -> int:
	return maxi(hits_required(tier) - hits_taken, 0)


## Whether a tool of [param tier] may work on this node at all.
func accepts(tier: int) -> bool:
	return data.accepts_tier(tier) if data != null else false


## Lands one swing from a tool of [param tier].
##
## Returns `{applied, broke, hits_left, hits_max}`:
## - `applied` — whether the swing counted. False for a depleted node or one that
##   refuses this tier, which is how [GatheringService] knows to refund the stamina
##   it already charged.
## - `broke` — whether this was the swing that emptied it.
##
## Publishing happens here rather than in the service, because "this node ran out of
## hits" is a fact about the node and a node that could go broke without saying so
## would depend on every caller remembering.
func hit(tier: int = 0) -> Dictionary:
	var needed := hits_required(tier)
	if depleted or needed <= 0 or not accepts(tier):
		return {"applied": false, "broke": false, "hits_left": hits_left(tier), "hits_max": needed}
	hits_taken += 1
	var left := maxi(needed - hits_taken, 0)
	if left > 0:
		hit_registered.emit(left, needed)
		EventBus.resource_hit.emit(data.id, left, needed)
		return {"applied": true, "broke": false, "hits_left": left, "hits_max": needed}
	deplete()
	return {"applied": true, "broke": true, "hits_left": 0, "hits_max": needed}


## Takes the node down: swaps in the stump, drops the collider, starts the clock.
func deplete() -> void:
	if depleted:
		return
	depleted = true
	hits_taken = 0
	respawn_days_left = data.respawn_days
	if _solid_shape != null:
		_solid_shape.set_deferred(&"disabled", true)
	if _model != null:
		_model.visible = false
	_ensure_depleted_model()
	if _depleted_model != null:
		_depleted_model.visible = true
	depleted_at.emit(global_position)
	EventBus.resource_depleted.emit(data.id, global_position)


## A stump, built on first need and then reused for the rest of the node's life.
func _ensure_depleted_model() -> void:
	if _depleted_model != null or data.depleted_model.is_empty():
		return
	_depleted_model = ModelArt.instantiate(data.depleted_model)
	if _depleted_model == null:
		return
	_depleted_model.name = "DepletedModel"
	var box := ModelArt.natural_aabb(data.depleted_model)
	if box.size != Vector3.ZERO:
		_depleted_model.position = -box.position
	add_child(_depleted_model)
	_depleted_model.visible = false


## Midnight. Counts a day off and stands the node back up if it is due.
##
## Returns whether it came back, so a container can log it without every node
## logging for itself on a night nothing regrew.
func on_new_day() -> bool:
	if not depleted:
		return false
	if data == null or data.respawn_days <= 0:
		return false
	respawn_days_left -= 1
	if respawn_days_left > 0:
		return false
	regrow()
	return true


## Puts it back exactly as it was.
func regrow() -> void:
	depleted = false
	hits_taken = 0
	respawn_days_left = 0
	if _solid_shape != null:
		_solid_shape.set_deferred(&"disabled", false)
	if _model != null:
		_model.visible = true
	if _depleted_model != null:
		_depleted_model.visible = false
	respawned.emit()
	EventBus.resource_respawned.emit(data.id if data != null else &"")


## The drop table rolled out, as `[{item_id, amount}, ...]`.
##
## Rolled from a generator seeded to this node's identity rather than consumed from
## a shared stream, so [method preview_yield] and [method take_yield] cannot drift
## apart and a save can be checked against what the node promised.
func take_yield() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.seed
	return _roll(rng)


## What [method take_yield] would produce, without producing it. For a prompt: "this
## will give you 3 Wood".
func preview_yield() -> Array[Dictionary]:
	return take_yield()


func _roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data == null:
		return out
	for line: GatherYield in data.yields:
		if line != null and line.is_valid():
			out.append({"item_id": line.item_id, "amount": line.roll(rng)})
	return out


## "3 Wood", for a prompt or a debug line.
func describe_yield() -> String:
	if data == null or data.yields.is_empty():
		return ""
	var parts: Array[String] = []
	for entry: Dictionary in preview_yield():
		var label := ItemRegistry.display_name_of(StringName(entry.get("item_id", &"")))
		var amount := int(entry.get("amount", 0))
		parts.append(label if amount == 1 else "%d %s" % [amount, label])
	return ", ".join(parts)


## What is left to do here, in words. The prompt's problem, but it is a fact about
## this node and the component should not have to recompute it.
func progress_text(tier: int = 0) -> String:
	if depleted:
		if data != null and data.respawn_days > 0:
			return "Regrowing (%dd)" % respawn_days_left
		return "Gone for good"
	return "%d left" % hits_left(tier)


func to_dict() -> Dictionary:
	return {
		"site": site_index,
		"id": data.id if data != null else &"",
		"hits": hits_taken,
		"depleted": depleted,
		"respawn": respawn_days_left,
	}


## Restores from [method to_dict].
##
## Rebuilds the visual state too rather than trusting the loader to have called
## [method deplete]: the swap is what makes a stump visible, and a reloaded save with
## a full-grown tree standing where a stump should be is worse than no save at all.
func apply_save(state: Dictionary) -> void:
	hits_taken = int(state.get("hits", 0))
	if bool(state.get("depleted", false)):
		respawn_days_left = int(state.get("respawn", 0))
		if not depleted:
			depleted = true
			if _solid_shape != null:
				_solid_shape.set_deferred(&"disabled", true)
			if _model != null:
				_model.visible = false
			_ensure_depleted_model()
			if _depleted_model != null:
				_depleted_model.visible = true
	else:
		depleted = false
		respawn_days_left = 0
		if _solid_shape != null:
			_solid_shape.set_deferred(&"disabled", false)
		if _model != null:
			_model.visible = true
		if _depleted_model != null:
			_depleted_model.visible = false