class_name Interactable
extends Node
## Reusable "this thing can be used with E" component.
##
## The point of this class is that *nothing* about interaction is hard-coded into
## the player. Any node in the world can become interactable by having an
## [Interactable] somewhere in its subtree - usually as a direct child of the
## physics body the player will actually hit with the interaction ray:
##
##     StaticBody3D          <- what the ray hits (has the collision shape)
##     |-- CollisionShape3D
##     `-- Interactable      <- add this component, optionally subclass it
##
## Subclasses override [method can_interact] and [method interact] and nothing
## else. They do not touch input, the HUD, or the player.
##
## Discovery is pull-based via [method resolve] rather than a global registry:
## a registry would need a central list to keep in sync with free()/reparent and
## would create a dependency from every interactable to a singleton.

## Emitted after a successful [method interact].
signal interacted(actor: Node)
## Emitted when the player starts aiming at this target.
signal focus_gained()
## Emitted when the player stops aiming at this target.
signal focus_lost()
## Emitted when [member enabled] changes, so a prompt can refresh immediately.
signal availability_changed()

## Shown before the prompt text, e.g. "E". Kept as a hint because the probe
## normally derives the real label from the InputMap.
@export var key_hint: String = "E"
## Verb shown in the prompt, e.g. "Look into the well".
@export var prompt_text: String = "Interact"
## Disabling hides the prompt without removing the component.
@export var enabled: bool = true
## Seconds the action must be held before it fires. 0 means instant.
@export var hold_seconds: float = 0.0
## After one successful interaction this becomes unavailable.
@export var one_shot: bool = false
## Furthest the actor may stand from [method get_focus_point].
@export var max_distance: float = 3.0
## How far above its origin [method get_aim_point] sits by default. Roughly chest
## height, which is where a crosshair naturally rests when looking at a
## waist-high prop.
@export var default_aim_height: float = 0.9

var _focused: bool = false
var _used: bool = false


func _ready() -> void:
	if get_parent() == null:
		# Without a parent there is no collision body for the probe to resolve
		# from, so the component would be silently inert.
		Log.warn("Interactable", "%s has no parent and can never be reached" % name)


## Walks up from a hit collider and returns the first [Interactable] found.
##
## Checks children of the collider itself, then children of each ancestor, so
## both layouts work:
##   body > Interactable          (component on the body)
##   prop > body > Interactable   (component above the body)
static func resolve(from: Node) -> Interactable:
	var node: Node = from
	while node != null:
		for child: Node in node.get_children():
			if child is Interactable:
				return child
		node = node.get_parent()
	return null


## Cheap gate the probe uses before bothering with distance checks.
## Subclasses should override this rather than [method can_interact] when the
## condition does not need the actor.
func is_available(_actor: Node) -> bool:
	if not enabled:
		return false
	return not (one_shot and _used)


## Whether [method interact] would succeed right now. Override for conditions
## that need the actor (inventory space, friendship, quest state, ...).
func can_interact(actor: Node) -> bool:
	return is_available(actor)


## Performs the interaction. Override in subclasses; call
## [method super] to keep the shared bookkeeping.
func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	if one_shot:
		_used = true
	interacted.emit(actor)
	return true


## Text shown in the HUD prompt. Override to react to state, e.g.
## "Open" vs "Locked" or a friendship-dependent line.
func get_prompt(_actor: Node) -> String:
	return prompt_text


## World point the probe measures distance from.
##
## Deliberately the *body's origin*, not the middle of the object's geometry. The
## probe uses this for its reach check, and reach is about how far the actor is
## from the thing they are interacting with; measuring to the origin is stable no
## matter how big or how oddly shaped the mesh is.
func get_focus_point() -> Vector3:
	var parent := get_parent()
	if parent is Node3D:
		return (parent as Node3D).global_position
	return Vector3.ZERO


## World point a *test* or an aim-assist should point the camera at.
##
## Separate from [method get_focus_point] on purpose. Conflating the two is what
## made the reach check and the aim target disagree: aiming a camera at the
## origin of a mailbox sitting on the ground points it at the dirt underneath,
## the ray hits the terrain, and the prop reads as unreachable when it is not.
## Components override this when their aimable surface is not at their origin —
## the farm's tiles aim at the middle of their aim volume.
func get_aim_point() -> Vector3:
	return get_focus_point() + Vector3(0.0, default_aim_height, 0.0)


## Force-enables/disables and notifies anything showing a prompt.
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	availability_changed.emit()


func is_focused() -> bool:
	return _focused


## Called by the probe. Not meant to be called by gameplay code.
func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	if _focused:
		focus_gained.emit()
	else:
		focus_lost.emit()


func has_been_used() -> bool:
	return _used


## Clears the one-shot latch so an interactable can be reused, e.g. when a
## chest is emptied and restocked.
func reset() -> void:
	_used = false
	availability_changed.emit()