class_name Npc
extends CharacterBody3D
## One villager: a body in the valley, a name, and an opinion of the player.
##
## [CharacterBody3D] rather than [Node3D] or [AnimatableBody3D] because a villager has
## to be blocked by a fence and push back when the player walks into them — which is
## the difference between a person and a decoration. There is no
## [NavigationAgent3D] here and no [NavMesh] in the project at all; movement is
## [method _physics_process] plus [method CharacterBody3D.move_and_slide], and group 15
## replaces [method _advance] with a schedule without changing anything above it.
##
## ## This node knows nothing about being interacted with
##
## The collider and the model are built here because this node is what knows its own
## size. The interaction volume and the [NpcInteractable] component are added by
## [NpcManager], exactly as [ResourceField] adds them to a [ResourceNode]. The reason
## is the same one that class documents: a component has to point at the node and the
## node would then have to point back at the component for the prompt, and two type
## references in opposite directions is a `class_name` cycle that GDScript reports as
## a compile error in unrelated files.
##
## ## Deterministic wandering
##
## The wander [RandomNumberGenerator] is seeded from the villager's own id, so Mira
## walks the same loop on every run. This is not a cosmetic choice: a test that
## asserts "she stays inside her radius" is worthless if it passes by luck, and a
## playtester who replays the same day gets the same village. It also means adding a
## seventh villager does not reshuffle the other six.

## Metres per second the villager turns. Deliberately slower than the player: a
## villager who snaps around looks like a turret, and the difference is most of what
## makes a walk cycle read as a person.
const TURN_SPEED := 3.5
## Metres from the target point at which the villager stops and picks a new one.
const ARRIVE_DISTANCE := 0.6
## Seconds a villager stands still after arriving, before choosing a new destination.
const MIN_IDLE_TIME := 0.8
const MAX_IDLE_TIME := 2.6
## Smoothing on the approach, so a villager does not start and stop in one frame.
const MOVE_ACCELERATION := 8.0

## The villager's definition. Required, and assigned before the node enters the tree by
## [NpcManager], because [method _ready] sizes the collider from it.
@export var data: NpcData = null

## The player's standing with this villager. A plain [Friendship] rather than an int
## so the tier rules live in one testable class instead of being re-derived by the
## HUD, the prompt and the save file separately.
var friendship: Friendship = null

## Whether this villager wanders at all. Off in tests that care about something else,
## on in the world; the manager sets it once at spawn.
var wandering: bool = true

## Set while the villager is being spoken to, so they hold still and listen.
var attending: bool = false

var _model: Node3D = null
var _box: AABB = AABB()
var _rng := RandomNumberGenerator.new()
var _wander_target: Vector2 = Vector2.ZERO
var _idle_for: float = 0.0
var _gravity: float = 24.0


func _ready() -> void:
	if data == null:
		# A villager with no definition has no height, no speed and no name, and would
		# stand in the square as a grey capsule. Better a loud refusal than a ghost.
		Log.error("Npc", "%s has no NpcData" % name)
		push_warning("Npc %s has no NpcData" % name)
		return
	collision_layer = PhysicsLayers.NPC
	collision_mask = PhysicsLayers.WORLD
	floor_snap_length = 0.4
	friendship = Friendship.new()
	_rng.seed = hash(String(data.id))
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)
	_box = ModelArt.natural_aabb(data.model)
	_build_collider()
	_build_model()
	_pick_wander_target()
	set_meta(&"npc_id", data.id)


## The capsule the player bumps into, sized from the definition rather than typed in.
##
## Radius is fixed at 0.35 while the height follows [member NpcData.target_height],
## because the height is content and the width is not: a villager who is 2.1 m tall
## should be taller and no wider, and deriving both from the height would make a short
## villager hard to walk into.
func _build_collider() -> void:
	var height: float = maxf(body_height(), 0.4)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = height
	shape_node.shape = capsule
	shape_node.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape_node)


## Builds the tinted CC0 model, standing on this node's origin.
##
## [method ModelArt.instantiate] does the scale correction from the imported model's
## measured height rather than trusting the importer's unit conversion, and the tint is
## applied per instance so five shared bodies can carry a cast of six.
func _build_model() -> void:
	_model = ModelArt.instantiate(data.model, body_height())
	if _model == null:
		# The content generator refuses an unloadable model, so this only happens if a
		# definition was authored after it last ran. A villager with no body is better
		# than one that takes the whole square down with it.
		Log.warn("Npc", "%s has no model at %s" % [data.id, data.model])
		return
	_model.name = "Model"
	if not ModelArt.is_white(data.model_tint):
		ModelArt.apply_tint(_model, data.model_tint)
	# The character pack's pivots sit at the feet, but a pack that changes its mind
	# should stand on the ground rather than hover or sink, so the measured box
	# decides — the same correction `ResourceNode` makes.
	if _box.size != Vector3.ZERO:
		_model.position.y = -_box.position.y * _model.scale.y
	add_child(_model)


func _physics_process(delta: float) -> void:
	if data == null:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	_advance(delta)
	move_and_slide()


## Steers towards the current wander target, or stands still.
##
## Split from [method _physics_process] so a test can call the movement directly at a
## fixed delta without a physics tick, which is the difference between asserting a
## villager walks and asserting it does not leave its radius.
func _advance(delta: float) -> void:
	var speed: float = data.walk_speed
	if attending or not wandering or speed <= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_ACCELERATION * speed * delta)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_ACCELERATION * speed * delta)
		return

	var offset := _wander_target - _home_position_xz()
	var distance := offset.length()
	if distance > ARRIVE_DISTANCE:
		var direction := offset / distance
		velocity.x = move_toward(velocity.x, direction.x * speed, MOVE_ACCELERATION * speed * delta)
		velocity.z = move_toward(velocity.z, direction.y * speed, MOVE_ACCELERATION * speed * delta)
		_turn_towards(atan2(direction.x, direction.y), delta)
		return

	# Arrived: stand about still, then pick somewhere new to be.
	velocity.x = move_toward(velocity.x, 0.0, MOVE_ACCELERATION * speed * delta)
	velocity.z = move_toward(velocity.z, 0.0, MOVE_ACCELERATION * speed * delta)
	_idle_for -= delta
	if _idle_for <= 0.0:
		_pick_wander_target()


## Points [param yaw_target] radians about Y, at [constant TURN_SPEED].
##
## Turning rather than snapping is the entire reason a villager reads as a person, and
## it costs one [method @GlobalScope.lerp_angle] call.
func _turn_towards(yaw_target: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, yaw_target, clampf(TURN_SPEED * delta, 0.0, 1.0))


## Turns to look at a world point, and holds still while doing it.
##
## Called by [NpcManager] when the player actually speaks, using the actor the
## interaction already resolved. Deliberately not automatic — "every villager in the
## square swivels to stare at you the moment you come within four metres" would be a
## chorus of heads tracking the camera and would read as a bug.
func face_towards(point: Vector3, delta: float) -> void:
	var offset := point - global_position
	if offset.length_squared() < 0.01:
		return
	_turn_towards(atan2(offset.x, offset.z), delta)


## Chooses a new place to stand, inside [member NpcData.wander_radius] of home.
##
## A disc rather than a square, so the distribution does not favour the corners, and
## never the exact centre: a villager who wanders to their own front step and stops
## there is standing where they started, which is not wandering.
func _pick_wander_target() -> void:
	if data == null:
		return
	var angle := _rng.randf_range(0.0, TAU)
	# sqrt so the points spread evenly over the area rather than clustering in the
	# middle, which is what `randf_range` on the radius would do.
	var radius := sqrt(_rng.randf()) * data.wander_radius * 0.85
	_wander_target = _home_position_xz() + Vector2(cos(angle), sin(angle)) * radius
	_idle_for = _rng.randf_range(MIN_IDLE_TIME, MAX_IDLE_TIME)


## Puts the villager back on their own doorstep.
##
## Called on the day rollover, so a villager saved at the far edge of the valley wakes
## up at home rather than resuming yesterday's errand at first light.
func go_home() -> void:
	position.x = data.home.x
	position.z = data.home.y
	velocity = Vector3.ZERO
	_pick_wander_target()


## Height used for the collider, the aim volume and the model's scale.
##
## Falls back to a plausible person if a definition somehow has a zero, so one bad
## number produces a small villager rather than an invisible one and a divide by zero.
func body_height() -> float:
	if data == null:
		return 1.8
	if data.target_height > 0.0:
		return data.target_height
	return 1.8


## Half-width of the aim volume, for [NpcManager]'s collision shape.
func aim_radius() -> float:
	return 0.55


## Centre height of the aim volume, for the interaction ray.
##
## The middle of the body rather than the origin: a villager's origin is on the
## ground, so aiming there points the camera at the dirt and the ray finds the terrain
## instead of the person. See [method Interactable.get_aim_point].
func aim_height() -> float:
	return body_height()


func home_position() -> Vector2:
	return data.home if data != null else Vector2.ZERO


## The village square this villager belongs to, for a minimap later.
func is_at_home() -> bool:
	if data == null:
		return false
	return _home_position_xz().distance_to(data.home) < data.wander_radius * 0.5


## "Mira (Friend, 2 hearts)" — name and standing in one string.
func describe() -> String:
	if data == null:
		return "Nobody"
	if friendship == null:
		return data.display_name
	return data.describe_standing(friendship)


## What would happen if [param item] were handed over right now.
##
## The prompt reads this and the transaction checks it, so a prompt cannot promise a
## gift the press then refuses — the same one-source-of-truth bargain
## [ResourceNodeInteractable] makes with [GatheringService]. Deliberately pure: no
## signals, no inventory, no side effects, so every refusal reason is testable without
## a scene tree.
##
## Returns `{"ok": bool, "reason": StringName, "reaction": StringName}`. A refusal
## still carries the reaction it *would* have been, because "you already gave them one
## of those today" and "they love that" are the two halves of the message a player
## needs.
func gift_preview(item: ItemDefinition) -> Dictionary:
	var reaction := NpcData.REACTION_NEUTRAL
	if data != null:
		reaction = data.reaction_to(item.id if item != null else &"")
	if friendship == null:
		return _preview(false, &"nothing_to_do", reaction)
	if not NpcData.is_giftable(item):
		# A tool is not a present, and a definition that will not load is not a gift.
		# The two are different failures and say so.
		if item == null:
			return _preview(false, &"no_item", reaction)
		if item.is_tool():
			return _preview(false, &"not_giftable", reaction)
		return _preview(false, &"not_giftable", reaction)
	if reaction == NpcData.REACTION_LOVED and not friendship.can_gift_loved_today():
		return _preview(false, &"already_gifted_today", reaction)
	if not friendship.can_gift_today():
		return _preview(false, &"gift_limit_reached", reaction)
	return _preview(true, &"", reaction)


## Takes the gift: awards the points and counts it. Returns the points that landed.
##
## The caller removes the item. Doing it in that order means an item that fails to
## leave the bag never scores — see [NpcManager.give_gift], which removes first for
## exactly that reason.
func award_gift(reaction: StringName) -> int:
	if friendship == null:
		friendship = Friendship.new()
	return friendship.award(reaction)


func _preview(ok: bool, reason: StringName, reaction: StringName) -> Dictionary:
	return {"ok": ok, "reason": reason, "reaction": reaction}


## This villager's share of the save file.
##
## Position is deliberately absent. Villagers are placed from
## [member NpcData.home] on every load, so persisting a coordinate would mean a save
## from a different valley layout put people inside walls.
func to_dict() -> Dictionary:
	return {
		"id": data.id if data != null else &"",
		"friendship": friendship.to_dict() if friendship != null else {},
	}


## Restores the player's standing from [method to_dict].
func from_dict(state: Dictionary) -> void:
	if friendship == null:
		friendship = Friendship.new()
	var stored: Dictionary = state.get("friendship", {})
	if stored.is_empty():
		return
	friendship.from_dict(stored)


func _home_position_xz() -> Vector2:
	return Vector2(position.x, position.z)