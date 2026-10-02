class_name ResourceField
extends Node3D
## Every gatherable thing in the world, and the interaction volumes that make them
## usable.
##
## The container [WorldBuilder] scatters into, and the save boundary for "which oaks
## have been cut down". It owns the nodes and does three things with them: it builds
## the aim volume and the [ResourceNodeInteractable] component for each, it counts
## days down at midnight, and it serialises the whole set as one list.
##
## ## Why the aim volumes live here and not on the node
##
## The component has to point at the node it belongs to, and the node would then
## have to point back at the component for the prompt. Two type references in
## opposite directions is a class cycle, and the symptom — as the header of this
## project has been at pains to record — is a compile error in a script that has
## nothing to do with either of them.
##
## So the node builds itself and the field wires it up. That also makes the
## invariant the world test asserts *structural* rather than a convention: every
## node in here has exactly one solid collider and exactly one interaction volume,
## and walking the children proves it.

## Emitted when a node stands back up at midnight. Carries the node so a listener
## can put a sound on the stump that is now a tree.
signal node_respawned(node: ResourceNode)
## Emitted when the day rolls over, after every node has been counted down.
signal day_passed()

## Placed nodes, in placement order. The order is the save order, and it is stable
## because [WorldBuilder] places in [ResourceNodeRegistry.spawnable_nodes] order.
var nodes: Array[ResourceNode] = []


func _ready() -> void:
	# The farm grid listens for the same signal to advance crops. One subscription,
	# one direction: nothing in this node knows that crops exist.
	if not EventBus.day_started.is_connected(_on_day_started):
		EventBus.day_started.connect(_on_day_started)


## Stands up a node of [param data] at [param position] and wires it up.
##
## Returns the node, or `null` when [param data] is unusable. Placement itself
## belongs to [WorldBuilder]; this method is deliberately the only thing that knows
## how a node becomes interactable, so there is exactly one way it can be wrong.
func add_node(data: ResourceNodeData, position: Vector3) -> ResourceNode:
	if data == null:
		return null
	var node := ResourceNode.new()
	node.name = "%s_%d" % [data.id, nodes.size()]
	node.build(data, nodes.size())
	node.position = position
	add_child(node)
	_add_interaction(node)
	nodes.append(node)
	return node


## The aim volume and its component.
##
## Two separate bodies, and the split is the point:
##
## - **Solid** — the node's own, on [constant PhysicsLayers.WORLD]. What the player
##   walks into.
## - **Aim** — this one, on [constant PhysicsLayers.INTERACTABLE], and taller and
##   wider than the solid part. The player must be able to hit a tree's crown from
##   three metres away, and the probe ray is what finds it. Nothing solid is ever
##   placed on that layer, so standing in it does nothing.
##
## Both are children of the node, so the whole thing moves and saves as a unit.
func _add_interaction(node: ResourceNode) -> void:
	var aim := StaticBody3D.new()
	aim.name = "AimVolume"
	aim.collision_layer = PhysicsLayers.INTERACTABLE
	aim.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = node.aim_radius()
	cylinder.height = node.aim_height()
	shape.shape = cylinder
	# Centred on the model's own height, so the ray finds it whether the player is
	# aiming at the trunk or the top of the canopy.
	shape.position = Vector3(0.0, node.aim_height() * 0.5, 0.0)
	aim.add_child(shape)
	var component := ResourceNodeInteractable.new()
	component.name = "Interactable"
	component.bind(node)
	aim.add_child(component)
	node.add_child(aim)


func count() -> int:
	return nodes.size()


func get_node_by_site(site: int) -> ResourceNode:
	for node: ResourceNode in nodes:
		if node.site_index == site:
			return node
	return null


## Nodes of one kind, for a test or a "what is left in this wood" query.
func nodes_of(data: ResourceNodeData) -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	for node: ResourceNode in nodes:
		if node.data != null and node.data.id == data.id:
			out.append(node)
	return out


## How many of each id are standing right now. Used by the world tests to assert the
## valley kept its rocks, and by a save check to prove nothing was lost.
func standing_counts() -> Dictionary:
	var out: Dictionary = {}
	for node: ResourceNode in nodes:
		var key := String(node.data.id) if node.data != null else ""
		if node.depleted:
			continue
		out[key] = int(out.get(key, 0)) + 1
	return out


func _on_day_started(_day: int) -> void:
	for node: ResourceNode in nodes:
		if node.on_new_day():
			node_respawned.emit(node)
	day_passed.emit()


## Every node's state, in placement order, plus anything lying on the ground.
##
## The drops belong to [GatheringService], so they are handed in rather than looked
## up: the field knows what is standing, the service knows what fell off it, and
## neither has to reach into the other to answer this.
func to_dict(drops: Array = []) -> Dictionary:
	var states: Array[Dictionary] = []
	for node: ResourceNode in nodes:
		states.append(node.to_dict())
	var fallen: Array[Dictionary] = []
	for drop: Variant in drops:
		if drop is ResourceDrop:
			fallen.append((drop as ResourceDrop).to_dict())
	return {"nodes": states, "drops": fallen}


## Restores from [method to_dict], matching by placement index.
##
## By index and not by id, because two oaks have the same id and a save that
## restored "the first oak" would heal the wrong tree after a placement change.
func from_dict(state: Dictionary, drops: Array = []) -> void:
	var states: Array = state.get("nodes", [])
	for entry: Dictionary in states:
		var node := get_node_by_site(int(entry.get("site", -1)))
		if node != null:
			node.apply_save(entry)
	var fallen: Array = state.get("drops", drops)
	# Re-created rather than restored: the drops are rigid bodies, and a rigid body
	# saved as a transform and a velocity is a different amount of work than
	# spawning a new one and letting it fall. Group 26 wires this to a real spawn.
	for entry: Dictionary in fallen:
		if entry.has("item_id"):
			Log.info("ResourceField", "drop %s restored at rest" % entry.get("item_id", ""))


## Every node in this field, and the world they were part of.
func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if nodes.is_empty():
		out.append("ResourceField has no nodes, so nothing in this world can be gathered.")
	return out