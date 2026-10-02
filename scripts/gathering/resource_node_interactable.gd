extends Interactable
class_name ResourceNodeInteractable
## Makes one [ResourceNode] usable by aiming at it and pressing the interact key.
##
## A component like every other interactable. The player does not learn that trees
## exist, and a tree does not learn what the interact key is. The layout is the same
## one the farm grid uses, with the aim volume between them because the component
## has to be a sibling of the collider the ray actually hits:
##
##     ResourceNode
##     |-- Solid            <- on the solid world layer, what you walk into
##     |-- Model
##     |-- DepletedModel
##     `-- AimVolume        <- on the interaction-only layer, what the ray finds
##         |-- CollisionShape3D
##         `-- ResourceNodeInteractable
##
## ## The prompt is the rule check
##
## [method get_prompt] asks [GatheringService] what would happen and renders the
## answer, and [method interact] asks the same service and performs it. One source of
## truth means the prompt cannot promise something the press then refuses — which is
## the failure this whole class exists to make impossible. See
## [SoilTileInteractable] for the same idea applied to four farming verbs.

## The node this component acts on. Assigned by [ResourceField] before the component
## enters the tree, and settable directly so a test can pair a node and a component
## without building a whole field.
var _node: ResourceNode = null

## Group [GatheringService] registers under, and this component searches for.
##
## Duplicated as a literal rather than shared: the constant would have to live on one
## of the two classes, and naming the other to reach it is the `class_name` cycle
## this lookup exists to avoid. [method _find_service] has the long version of that
## argument; `soil_tile_interactable_finds_the_real_farm_service`'s sibling case
## fails loudly if the two drift.
const SERVICE_GROUP := &"gathering_service"

## How close the player has to stand. A tree is a bigger thing than a soil tile, so
## this is a little further out than the farm's 2.6 — enough to swing at a trunk
## without standing inside it.
const REACH := 3.0


func _ready() -> void:
	super()
	if _node == null:
		_node = _find_ancestor_node(self)
	_refresh()
	set_meta(&"resource_node_interactable", true)


## Pairs this component with [param value] and re-derives its availability.
func bind(value: ResourceNode) -> void:
	_node = value
	_refresh()


func get_node_ref() -> ResourceNode:
	return _node


## The middle of the aim volume, not the node's origin.
##
## A node's origin is on the ground, so aiming there points the camera at the dirt
## and the ray hits the terrain instead of the volume. See
## [method Interactable.get_aim_point] and
## [method SoilTileInteractable.get_aim_point] for the long version of why these two
## are not the same thing.
func get_aim_point() -> Vector3:
	if _node == null:
		return super()
	return _node.global_position + Vector3(0.0, _node.aim_height() * 0.5, 0.0)


## Re-derives the hold time from the node's definition.
##
## Driven by the node's `state_changed`-equivalent signals as well as being called
## directly, so a prompt that says "2 left" does not keep saying it after the third
## swing. Taking an optional argument because it is called both ways.
func _refresh(_changed: Variant = null) -> void:
	one_shot = false
	enabled = _node != null
	if _node != null and _node.data != null:
		# The hold time is content, not a constant: foraging is instant and an oak is
		# not, and hard-coding either here would mean every node pays for the
		# slowest one.
		hold_seconds = _node.data.hit_hold_seconds
	max_distance = REACH
	availability_changed.emit()


## A depleted node stays *available* on purpose.
##
## It is not available in the sense of "this will do something" — [method interact]
## will refuse it. It is available in the sense of "keep showing me this". Removing
## the prompt the moment a tree falls would leave the player holding E at a stump
## with nothing happening and nothing said, and the failure event that should
## explain it would have nothing to attach to.
func is_available(_actor: Node) -> bool:
	if _node == null:
		return false
	return enabled


func can_interact(actor: Node) -> bool:
	return is_available(actor)


## What this node would yield, for the prompt.
func get_node_yield_text() -> String:
	return _node.describe_yield() if _node != null else ""


## The node's id, for an event payload.
func node_id_of() -> StringName:
	return _node.data.id if _node != null and _node.data != null else &""


## "Chop the Oak (3 left)", "Pick the Berry Bush", "Oak - regrowing (2d)".
##
## Delegated to [GatheringService], which is the only thing that knows what the
## player is holding. The component is not asking whether the press will work — it
## is asking what to *say*, and the service's answer is the same one the press
## checks against.
func get_prompt(actor: Node) -> String:
	if _node == null or _node.data == null:
		return "Nothing here"
	var service := _find_service()
	if service == null:
		return "%s the %s" % [_node.data.describe_action(), _node.data.describe()]
	var status: Dictionary = service.call("status_for", _node, actor)
	return String(status.get("prompt", _node.data.describe()))


## Performs the action the prompt named.
##
## Returns false for every refusal, and each one publishes
## [signal EventBus.gathering_failed] from inside the service with a reason. A silent
## no-op is the one thing this component must never do: a player who swings a hoe at
## a pine needs to be told "that needs an axe", not left holding a key that does
## nothing.
func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	if _node == null:
		EventBus.gathering_failed.emit(&"", &"none", &"no_target")
		return false
	var service := _find_service()
	if service == null:
		EventBus.gathering_failed.emit(node_id_of(), _verb(), &"no_gathering_service")
		return false
	# `call`, not `service.gather(...)`. Naming the service type here would close a
	# cycle: the service knows about ResourceNode, and ResourceNode's own component
	# would then know about the service.
	if bool(service.call("gather", _node, actor)):
		_refresh()
		interacted.emit(actor)
		return true
	_refresh()
	return false


func _verb() -> StringName:
	return _node.data.verb() if _node != null and _node.data != null else &"none"


## The [GatheringService], found by group from the tree root.
##
## Typed as a bare [Node] and called dynamically, for the reason spelled out at
## length in [method SoilTileInteractable._find_service]: naming the service here
## makes `GatheringService -> ResourceNode -> ResourceNodeInteractable ->
## GatheringService`, and GDScript reports that as errors in unrelated files.
static func _find_service() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search_for_service(scene_root)


static func _search_for_service(node: Node) -> Node:
	if node.is_in_group(SERVICE_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _search_for_service(child)
		if found != null:
			return found
	return null


## Nearest [ResourceNode] at or above [param from].
##
## Walks up rather than searching the subtree: the children of a node are meshes and
## colliders, and a *sibling* oak is not this component's business. Upwards is the
## only direction where "is this mine?" has a definite answer.
static func _find_ancestor_node(from: Node) -> ResourceNode:
	var node := from
	while node != null:
		if node is ResourceNode:
			return node as ResourceNode
		node = node.get_parent()
	return null