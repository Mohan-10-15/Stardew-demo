class_name NpcManager
extends Node3D
## The cast, and every rule about talking to and giving things to it.
##
## Same division of labour as [GatheringService]: the villager holds their own body and
## their own opinion, the [NpcInteractable] component holds the prompt and the press,
## and everything in between — what is in the player's hands, whether the weekly budget
## allows it, what comes out — belongs here, because that is the only part that touches
## both the player's bag and the world.
##
## ## What "talk" is today
##
## [method talk] turns the villager to face the player and publishes
## [signal EventBus.npc_talked]. That is all it does, and the reason is deliberate:
## Group 16 hangs dialogue off that signal rather than this method gaining a `switch`
## over a villager id, which is what "content is data" is protecting against. The
## extension point is the signal, not the code.
##
## ## Placement
##
## Villagers are placed from [member NpcData.home] on every spawn and every day
## rollover, never from a saved position. A save records who the player knows and how
## well; it does not record where six people were standing when they saved. That is
## what keeps a save portable between a village that moved and a save taken before it
## moved.
##
## ## Why there is no navigation here
##
## Group 15. [Npc] walks its own patrol within its own radius and collides with the
## world honestly, which is enough to prove the whole interaction chain. There is no
## [NavMesh] in the project yet and nothing here pretends otherwise.

## Group this node registers under, so [NpcInteractable] can find it.
##
## Duplicated as a literal in that component because a shared constant would need one
## of the two classes to name the other, and that closes a `class_name` cycle.
const SERVICE_GROUP := &"npc_service"

## How close the player must be for the press to count.
##
## Re-checked here rather than trusted from the prompt, because a prompt is not a
## promise about distance — the player can walk backwards between reading it and
## pressing the key. Matches [constant NpcInteractable.REACH].
@export_range(1.0, 6.0, 0.1) var reach: float = 3.0

## Whether the manager spawns the whole cast on ready. Off in tests that want to place
## villagers themselves, on in the world.
@export var spawn_on_ready: bool = true

## Seconds a villager holds still after being spoken to before resuming their patrol.
## Long enough to read a line, short enough that nobody gets stuck behind a conversational
## neighbour.
@export_range(0.0, 10.0, 0.1) var attend_seconds: float = 1.2

var _cast: Node3D = null
var _npcs: Dictionary = {}
var _order: Array[StringName] = []
var _attend_timers: Dictionary = {}


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	_cast = Node3D.new()
	_cast.name = "Cast"
	add_child(_cast)
	# Connected rather than polled, so a day rollover that happens while the game is
	# paused still reaches the cast: the signal is published by the clock regardless of
	# this node's process mode.
	if not EventBus.day_started.is_connected(_on_day_started):
		EventBus.day_started.connect(_on_day_started)
	if spawn_on_ready:
		spawn_all()
	Log.info("Npc", "Ready with %d villagers" % _npcs.size())


## Places every villager in [NpcRegistry], in a stable order.
##
## Idempotent in the sense that matters: spawning twice is safe and keeps the first
## set's friendships, so a caller that re-spawns after loading a save does not wipe
## what the player built up.
func spawn_all() -> Array[Npc]:
	var out: Array[Npc] = []
	for data: NpcData in NpcRegistry.all_npcs():
		var existing := get_npc(data.id)
		if existing != null:
			out.append(existing)
			continue
		var spawned := spawn_npc(data)
		if spawned != null:
			out.append(spawned)
	return out


## Builds one villager at their own front step.
##
## Returns null for a definition that will not load, so one bad `.tres` costs one
## missing villager rather than the whole village.
func spawn_npc(data: NpcData) -> Npc:
	if data == null or data.id.is_empty():
		Log.warn("Npc", "refusing to spawn a villager with no definition")
		return null
	if not ModelArt.can_load(data.model):
		Log.warn("Npc", "villager %s cannot load %s" % [data.id, data.model])
		return null
	var npc := Npc.new()
	npc.name = String(data.id)
	npc.data = data
	# Position before entering the tree: a `global_position` write on a parentless node
	# logs an engine error every single spawn (`AGENTS.md`, trap two).
	npc.position = ground_position(data.home)
	_cast.add_child(npc)
	_npcs[data.id] = npc
	if not _order.has(data.id):
		_order.append(data.id)
	_add_interaction(npc)
	return npc


## The interaction volume and its component, added here rather than by [Npc].
##
## The component has to point at the villager, and a villager that also pointed at the
## component for its prompt would be a `class_name` cycle — the reason
## [method ResourceField._add_interaction] exists in the gathering system. Same split,
## same reasoning, and the aim volume sits between the two because the ray has to hit a
## sibling of the component.
func _add_interaction(npc: Npc) -> void:
	var aim := StaticBody3D.new()
	aim.name = "AimVolume"
	aim.collision_layer = PhysicsLayers.INTERACTABLE
	aim.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	var width := npc.aim_radius() * 2.0
	box.size = Vector3(width, maxf(npc.aim_height(), 0.5), width)
	shape.shape = box
	# Centred on the body, so the ray finds the villager whether the player is aiming
	# at their face or their boots. Aiming at a node's origin points the camera at the
	# ground instead, which is the bug `Interactable.get_aim_point` documents.
	shape.position = Vector3(0.0, npc.aim_height() * 0.5, 0.0)
	aim.add_child(shape)
	var component := NpcInteractable.new()
	component.name = "Interactable"
	# `bind` before `add_child`, so the component's `_ready` already knows its villager.
	component.bind(npc)
	aim.add_child(component)
	npc.add_child(aim)


func get_npc(id: StringName) -> Npc:
	return _npcs.get(id) as Npc


## Everyone, in id order.
func npcs() -> Array[Npc]:
	var out: Array[Npc] = []
	for id: StringName in _order:
		var npc := get_npc(id)
		if npc != null:
			out.append(npc)
	return out


## How many villagers are placed.
func count() -> int:
	return _npcs.size()


func _physics_process(delta: float) -> void:
	_release_attending(delta)


## Lets go of villagers whose conversation has run out.
##
## A timer rather than a flag because "attending" has to end on its own: a villager
## frozen mid-patrol for the rest of the day is a worse bug than a villager who cuts
## you off, and group 16 replaces the fixed length with the length of a real line.
func _release_attending(delta: float) -> void:
	if _attend_timers.is_empty():
		return
	for id: StringName in _attend_timers.keys():
		var left := float(_attend_timers[id]) - delta
		if left > 0.0:
			_attend_timers[id] = left
			continue
		_attend_timers.erase(id)
		var npc := get_npc(id)
		if npc != null:
			npc.attending = false


## Says hello.
##
## Turns the villager to face [param actor] and publishes [signal EventBus.npc_talked].
## A missing or unusable [param actor] is *not* a refusal — there is simply nothing to
## turn towards, and a greeting that still happened is more useful than one that
## refused over a position. Every real refusal publishes
## [signal EventBus.npc_talk_failed] with a reason and returns false, because a keypress
## that does nothing and says nothing is a bug the player reports as a crash.
func talk(npc: Npc, actor: Node) -> bool:
	var id := _id_of(npc)
	if npc == null:
		EventBus.npc_talk_failed.emit(id, &"no_npc")
		return false
	if npc.data == null:
		EventBus.npc_talk_failed.emit(id, &"nothing_to_say")
		return false
	npc.attending = true
	_attend_timers[id] = attend_seconds
	if actor is Node3D:
		npc.face_towards((actor as Node3D).global_position, 0.2)
	EventBus.npc_talked.emit(id)
	Log.debug("Npc", "Talked to %s" % id)
	return true


## Hands [param item_id] to [param npc].
##
## The order here is the whole design: **check, then take, then score**. The preview is
## asked before the item leaves the bag so a refusal costs nothing, and the points are
## awarded only after the removal actually succeeded so a stack that would not leave the
## bag never scores. A gift that scores without being given is the kind of bug a player
## discovers by giving a present, watching their friendship go up, and finding the
## present still in their bag.
##
## Returns false for every refusal, each publishing
## [signal EventBus.npc_gift_failed] with a reason.
func give_gift(npc: Npc, item_id: StringName, actor: Node) -> bool:
	var id := _id_of(npc)
	if npc == null:
		EventBus.npc_gift_failed.emit(id, item_id, &"no_npc")
		return false
	if npc.data == null:
		EventBus.npc_gift_failed.emit(id, item_id, &"nothing_to_do")
		return false
	var state := PlayerStateService.find()
	if state == null or state.inventory == null or state.hotbar == null:
		EventBus.npc_gift_failed.emit(id, item_id, &"no_player_state")
		return false

	var stack := state.hotbar.get_selected_stack()
	if stack == null or stack.is_empty():
		EventBus.npc_gift_failed.emit(id, item_id, &"no_item_held")
		return false
	if stack.id != item_id:
		# The player swapped slots between reading the prompt and pressing the key.
		EventBus.npc_gift_failed.emit(id, stack.id, &"nothing_to_do")
		return false
	var item := ItemRegistry.get_item(stack.id)
	if item == null:
		EventBus.npc_gift_failed.emit(id, stack.id, &"no_item")
		return false

	var preview := npc.gift_preview(item)
	if not bool(preview.get("ok", false)):
		EventBus.npc_gift_failed.emit(id, item.id, StringName(preview.get("reason", &"nothing_to_do")))
		return false

	# `remove_stack`, not `remove`. `remove` spends the lowest quality first, so it
	# could consume a silver berry while the one in the player's hand was normal — the
	# same reason `PlayerStateService.spend_tool_durability` uses this.
	if state.inventory.remove_stack(stack, 1) <= 0:
		EventBus.npc_gift_failed.emit(id, item.id, &"nothing_to_do")
		return false

	var reaction := StringName(preview.get("reaction", &""))
	var tier_before := npc.friendship.tier_name() if npc.friendship != null else ""
	var delta := npc.award_gift(reaction)
	if npc.friendship != null and npc.friendship.tier_name() != tier_before:
		EventBus.npc_friendship_changed.emit(id, npc.friendship.hearts(), npc.friendship.tier_name())
	EventBus.npc_gifted.emit(id, item.id, reaction)
	Log.info("Npc", "Gave %s to %s (%s, +%d)" % [
		item.id, id, reaction, delta,
	])
	return true


## The whole cast's saveable state, as one dictionary.
##
## Keyed by villager id rather than an array, because the next group will add villagers
## to the middle of the cast and a positional list would silently reassign every
## relationship to the wrong person on load.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _order:
		var npc := get_npc(id)
		if npc != null and npc.friendship != null:
			out[id] = npc.friendship.to_dict()
	return out


## Restores every villager's standing, spawning any the save mentions but the content
## does not have.
##
## A villager in the save who is not in `resources/npc/npcs/` is skipped rather than
## reported as an error: content gets cut between builds and a removed villager should
## not make an old save unloadable.
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	for id: StringName in data.keys():
		var npc := get_npc(id)
		if npc == null:
			Log.info("Npc", "save mentions %s, who is not in the content" % id)
			continue
		npc.from_dict({"friendship": data[id]})
	_log_summary()


## Day rollover: everyone goes home, daily gift limits clear, and the weekly budget
## clears on the first of the month.
##
## The week boundary is [code]day == 1[/code] and nothing else, because a month is 28
## days — exactly four weeks — so the first of the month *is* Monday. Inventing a
## day-of-week for the sake of one reset would be a calendar feature the rest of the
## game does not have yet, and it would have to be saved, versioned and migrated.
func _on_day_started(day: int) -> void:
	var new_week := day <= 1
	for npc: Npc in npcs():
		if npc.friendship == null:
			continue
		npc.friendship.new_day()
		if new_week:
			npc.friendship.new_week()
		npc.go_home()
	Log.info("Npc", "Day %d: %d villagers home%s" % [
		day, count(), " (new week)" if new_week else "",
	])


func _log_summary() -> void:
	for npc: Npc in npcs():
		Log.info("Npc", "%s: %s" % [npc.data.id, npc.friendship.describe()])


func _id_of(npc: Npc) -> StringName:
	return npc.data.id if npc != null and npc.data != null else &""


## The ground height at an XZ position, with the villager's feet on it.
##
## `WorldBuilder.terrain_height` is the same function the terrain mesh was built from,
## so a villager stands on the ground rather than hovering above it or sinking into it.
## The `home` vector's `y` is the world's Z, which is spelled out here because
## `home.y` meaning "z" is the kind of thing that is silently wrong.
static func ground_position(home: Vector2) -> Vector3:
	var x := home.x
	var z := home.y
	return Vector3(x, WorldBuilder.terrain_height(x, z), z)