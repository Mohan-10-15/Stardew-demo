class_name Npc
extends CharacterBody3D
## One villager: a body in the valley, a name, and an opinion of the player.
##
## [CharacterBody3D] rather than [Node3D] or [AnimatableBody3D] because a villager has
## to be blocked by a fence and push back when the player walks into them — which is
## the difference between a person and a decoration. There is no
## [NavigationAgent3D] here and no [NavMesh] in the project at all; movement is
## [method _physics_process] plus [method CharacterBody3D.move_and_slide], and the
## authored day arrives as [method walk_to] rather than as a component bolted onto
## the body.
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
## ## Two ways of moving, one body
##
## [method _advance] chooses between them in this order:
##
## 1. **Stopped.** Being talked to, or a walk speed of zero. Talking wins over
##    everything, because a villager who keeps walking away mid-sentence reads as the
##    player being ignored rather than as a schedule running.
## 2. **Scheduled.** Walking the path [method walk_to] was given, or standing at the
##    end of it. Deliberately independent of [member wandering]: a schedule is a
##    commitment, not a wander, and a test that switches wandering off to observe
##    something else should not also strand a villager three streets from where their
##    day says they are.
## 3. **Wandering.** The seeded disc around home, unchanged.
##
## The seeded disc is what a villager with no authored day does all day, and it is
## what they do between blocks - including all of the time, for anyone whose day is
## only written for some seasons or some weather.
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

## The attachment-stripping notice is per-archetype, not per-villager, and saying it six
## times is how a real warning gets read past.
var _warned_about_props: bool = false
var _box: AABB = AABB()
var _rng := RandomNumberGenerator.new()
var _wander_target: Vector2 = Vector2.ZERO
var _idle_for: float = 0.0
var _gravity: float = 24.0
## Who this villager is currently turned towards, while [member attending]. Empty until
## somebody speaks to them; see [method face_towards].
var _face_point := Vector3.ZERO
var _has_face_point: bool = false
## Schedule and destination state for path following.
##
## [member scheduled_location_id] is the *resolved* place, not a raw block: it is
## whatever [NpcSchedule.location_at] answered for the current clock, and it is what
## makes "the clock ticked but nobody moved" cheap - [NpcManager] compares against it
## and rebuilds a path only when the answer actually changed.
var _schedule: NpcSchedule = null
var scheduled_location_id: StringName = &""
var _path: PackedVector3Array = []
var _path_index: int = 0
var _target_point: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _moving_to_scheduled: bool = false
var _navigation: NpcNavigation = null
## Heading to settle on once the walk is done, or [constant LocationData.FACING_UNSET].
var _scheduled_facing: float = LocationData.FACING_UNSET
var _has_scheduled_facing: bool = false


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
	# `body_aabb`, not `natural_aabb`. A character file in this pack holds the body *and
	# every weapon the archetype carries* under one imported root, so the whole-file box
	# is up to 4.1m wide and about 0.7m too tall. Both uses of `_box` below are wrong
	# with it: the ground offset sinks the villager to the ankles, and the collider grows
	# to swallow a bystander.
	_box = ModelArt.body_aabb(data.model)
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
	_model = ModelArt.instantiate_standing(data.model, body_height())
	if _model == null:
		# The content generator refuses an unloadable model, so this only happens if a
		# definition was authored after it last ran. A villager with no body is better
		# than one that takes the whole square down with it.
		Log.warn("Npc", "%s has no model at %s" % [data.id, data.model])
		return
	_model.name = "Model"
	# Before the tint and before anything reads the tree, so nothing downstream can see a
	# weapon. Every villager was instanced whole and carried the archetype's entire
	# armoury: four shields and three swords for the Knight, a mug and three axes for the
	# Barbarian, two crossbows and a throwable for the Rogue.
	var carried := ModelArt.strip_attachments(_model)
	if carried > 0 and not _warned_about_props:
		_warned_about_props = true
		Log.info("Npc", "%s: dropped %d held props from %s" % [data.id, carried, data.model.get_file()])
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


## Steers towards the current scheduled waypoint, or the current wander target.
##
## Split from [method _physics_process] so a test can call the movement directly at a
## fixed delta without a physics tick, which is the difference between asserting a
## villager walks and asserting it does not leave its radius.
func _advance(delta: float) -> void:
	var speed: float = data.walk_speed
	if attending or speed <= 0.0:
		_stop_moving(delta, speed)
		# Keep turning towards whoever is being spoken to until they are actually facing
		# them. One turn from [method face_towards] covers most of the arc and then stops,
		# which leaves a villager standing at ninety degrees to the conversation — and a
		# test that only watches the yaw change cannot tell that from facing them.
		if attending and _has_face_point:
			face_towards(_face_point, delta)
		return
	if _moving_to_scheduled:
		_follow_schedule(delta, speed)
		return
	if not wandering:
		_stop_moving(delta, speed)
		return

	var offset := _wander_target - _home_position_xz()
	var distance := offset.length()
	if distance > ARRIVE_DISTANCE:
		var direction := offset / distance
		velocity.x = move_toward(velocity.x, direction.x * speed, MOVE_ACCELERATION * speed * delta)
		velocity.z = move_toward(velocity.z, direction.y * speed, MOVE_ACCELERATION * speed * delta)
		_turn_towards(_yaw_towards(direction.x, direction.y), delta)
		return

	# Arrived: stand about still, then pick somewhere new to be.
	velocity.x = move_toward(velocity.x, 0.0, MOVE_ACCELERATION * speed * delta)
	velocity.z = move_toward(velocity.z, 0.0, MOVE_ACCELERATION * speed * delta)
	_idle_for -= delta
	if _idle_for <= 0.0:
		_pick_wander_target()


## Walks the path [method walk_to] laid down, or stands at the end of it.
##
## A villager who has arrived does **not** fall back to wandering: standing at the
## place their day sent them *is* what the rest of that block means. The walk is only
## replaced when [NpcManager] resolves a different location, which is why the path is
## left in place here rather than cleared on arrival.
func _follow_schedule(delta: float, speed: float) -> void:
	if _path_index >= _path.size():
		_stop_moving(delta, speed)
		if _has_scheduled_facing:
			_turn_towards(_scheduled_facing, delta)
		return
	_target_point = _path[_path_index]
	_has_target = true
	var flat := _target_point - global_position
	flat.y = 0.0
	var distance := flat.length()
	if distance <= ARRIVE_DISTANCE:
		_path_index += 1
		if _path_index >= _path.size():
			_has_target = false
		return
	var direction := flat / distance
	velocity.x = move_toward(velocity.x, direction.x * speed, MOVE_ACCELERATION * speed * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, MOVE_ACCELERATION * speed * delta)
	_turn_towards(_yaw_towards(direction.x, direction.z), delta)


## Coasts to a stop, keeping gravity handled by [method _physics_process].
func _stop_moving(delta: float, speed: float) -> void:
	var rate: float = MOVE_ACCELERATION * speed
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


## Gives this villager the walkability grid, or null for a straight-line fallback.
func set_navigation(nav: NpcNavigation) -> void:
	_navigation = nav


func set_schedule(schedule: NpcSchedule) -> void:
	_schedule = schedule
	if schedule == null:
		clear_scheduled_walk()


func get_schedule() -> NpcSchedule:
	return _schedule


## Lays a path from here to [param point] and starts walking it.
##
## Returns false when the grid exists and says there is no way there - an unwalkable
## destination that nothing can snap to - and true otherwise. With no grid at all it
## falls back to a single straight-line segment: a villager in a test rig, or one
## whose grid failed to build, still reaches the place, they simply do not go around
## anything on the way.
##
## [param facing] is applied once the last waypoint is reached, so an arriving
## villager ends up looking at the thing they came for rather than backwards along
## the path they walked. [constant LocationData.FACING_UNSET] leaves the arrival
## heading alone.
func walk_to(point: Vector3, facing: float = LocationData.FACING_UNSET) -> bool:
	_scheduled_facing = facing
	_has_scheduled_facing = not is_inf(facing)
	_path = PackedVector3Array()
	_path_index = 0
	_has_target = false
	_moving_to_scheduled = false
	if _navigation != null:
		_path = _navigation.find_path(global_position, point)
		if _path.is_empty():
			Log.warn("Npc", "%s: no path to %s" % [name, str(point)])
			return false
	else:
		_path.append(point)
	_moving_to_scheduled = true
	return true


## Drops any walk in progress. The villager resumes wandering from where it stands.
func clear_scheduled_walk() -> void:
	_moving_to_scheduled = false
	_path = PackedVector3Array()
	_path_index = 0
	_has_target = false
	_has_scheduled_facing = false


## Whether this villager is committed to a scheduled destination: still walking, or
## already standing at it.
##
## The distinction from [member wandering] matters to a caller asking "are they doing
## what their day says", because a villager who has arrived is holding position and
## still counts - clearing the walk on arrival would make them wander away from the
## place they were sent to.
func is_walking_to_post() -> bool:
	return _moving_to_scheduled


## Points [param yaw_target] radians about Y, at [constant TURN_SPEED].
##
## Turning rather than snapping is the entire reason a villager reads as a person, and
## it costs one [method @GlobalScope.lerp_angle] call.
func _turn_towards(yaw_target: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, yaw_target, clampf(TURN_SPEED * delta, 0.0, 1.0))


## Turns to look at a world point, and keeps looking at it while attending.
##
## Called by [NpcManager] when the player actually speaks, using the actor the
## interaction already resolved. Deliberately not automatic — "every villager in the
## square swivels to stare at you the moment you come within four metres" would be a
## chorus of heads tracking the camera and would read as a bug.
##
## The point is remembered so [method _advance] can finish the turn over the next few
## ticks: turning at [constant TURN_SPEED] from an arbitrary heading takes longer than one
## call, and a villager who stops a quarter of the way round is not facing the player.
func face_towards(point: Vector3, delta: float) -> void:
	var offset := point - global_position
	if offset.length_squared() < 0.01:
		return
	_face_point = point
	_has_face_point = true
	_turn_towards(_yaw_towards(offset.x, offset.z), delta)


## The yaw that points this node's forward at an XZ offset.
##
## Godot's forward is -Z, hence the negated components — the same arithmetic
## `PlayerController._update_facing` uses, and negated for the same reason. Without it a
## villager walks backwards down the lane and turns its back on the player it was just
## spoken to, and neither is visible to a test that only asserts a number moved.
static func _yaw_towards(x: float, z: float) -> float:
	return atan2(-x, -z)


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
## up at home rather than resuming yesterday's errand at first light. Any walk in
## progress is dropped for the same reason: the path was laid from where they stood
## yesterday, and following it from home would walk them back out to where they were.
func go_home() -> void:
	clear_scheduled_walk()
	position.x = home_position().x
	position.z = home_position().y
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


## A runtime override for the home. Set when the villager marries and moves to the
## farm, cleared by [method clear_home_override]. Stored as a Vector2 (XZ) because
## the nav, the wander disc and the prompt only ever use XZ. The height is not part
## of a "place" identity.
var _home_override_pos: Vector2 = Vector2.ZERO
var _has_home_override: bool = false
var _home_override_location: StringName = &""


## Overrides the home used for [method home_position], wander disc and scheduled
## "home" blocks while this villager is a spouse. [param location_id] may be empty
## — the manager still records it if a listener wants to know why, but nothing else
## requires it. The override is a *cache* applied by [NpcManager], not persisted
## here.
func set_home_override(pos: Vector2, location_id: StringName = &"") -> void:
	_home_override_pos = pos
	_has_home_override = true
	_home_override_location = location_id


## Removes the override, restoring [member NpcData.home].
func clear_home_override() -> void:
	_has_home_override = false
	_home_override_location = &""


## The location id that the marriage record points to, if any. Empty when using the
## authored home. A spouse is expected to live at `farm_home`; nobody else should have
## an override in a normal save. Keeping it on the node means a UI can show a note
## without a second lookup.
func home_location_id() -> StringName:
	if _has_home_override:
		return _home_override_location
	if data == null:
		return &""
	# The authored home is the villager's own cottage. The content uses the pattern
	# `<id>_cottage`; exposing it is cheap and lets [NpcManager._refresh_schedule]
	# tell a spouse's schedule to stop pulling the authored cottage without a second
	# field.
	return StringName("%s_cottage" % data.id)


func home_position() -> Vector2:
	if _has_home_override:
		return _home_override_pos
	return data.home if data != null else Vector2.ZERO


## The village square this villager belongs to, for a minimap later.
func is_at_home() -> bool:
	if data == null:
		return false
	return _home_position_xz().distance_to(home_position()) < data.wander_radius * 0.5


## "Mira (Friend, 2 hearts)" — name and standing in one string.
func describe() -> String:
	if data == null:
		return "Nobody"
	if friendship == null:
		return data.display_name
	return data.describe_standing(friendship)


## What would happen if [param item_id] were handed over right now.
##
## The id rather than an [ItemDefinition] because that is what a gift *is*: one unit out
## of a bag slot, and a harvested crop is in the bag under its crop id with no definition
## behind it. Taking a definition here would have made every crop ungiftable.
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
func gift_preview(item_id: StringName) -> Dictionary:
	var reaction := NpcData.REACTION_NEUTRAL
	if data != null:
		reaction = data.reaction_to(item_id)
	if friendship == null:
		return _preview(false, &"nothing_to_do", reaction)
	if not NpcData.is_known_item(item_id):
		# A tool is not a present, and a definition that will not load is not a gift.
		# The two are different failures and say so.
		return _preview(false, &"no_item", reaction)
	if not NpcData.is_giftable_id(item_id):
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
## Position is deliberately absent. Villagers are placed from [member NpcData.home]
## on every load, so persisting a coordinate would mean a save from a different valley
## layout put people inside walls. A marriage home override is a runtime consequence
## of the relationship: it is applied by [NpcManager] when loading a save (or when a
## proposal succeeds), and at day rollover, rather than being written into the
## per-villager save blob.
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