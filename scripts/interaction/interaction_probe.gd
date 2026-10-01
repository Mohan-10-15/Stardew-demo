class_name InteractionProbe
extends Node
## Finds what the player is looking at and performs interactions on it.
##
## Lives on the player (as a plain [Node], so it has no transform of its own)
## and is the only thing in the project that knows the `E` key exists. The
## player never hears about [Interactable] directly, and interactables never
## hear about the player - everything goes through here and [EventBus].
##
## The ray starts at the *camera* rather than the player's chest so the
## crosshair is the source of truth. That also works in third person, where the
## camera sits behind the body: the player's own collider is excluded from the
## query so the ray passes through it.

## Emitted whenever the focused target changes, including to null.
signal focus_changed(target: Interactable)
## Emitted after a successful interaction, with the target that was used.
signal interacted(target: Interactable, actor: Node)

## Seconds the interaction ray may travel. Also bounds how far the prompt
## appears while standing back from something.
@export var ray_length: float = 3.5
## Action used to interact. Configurable so a future remap needs no code.
@export var interact_action: StringName = InputActions.INTERACT
## Optional explicit camera. Left empty the active viewport camera is used,
## which keeps working when the camera is reparented by the camera rig.
@export var camera_path: NodePath
## Optional explicit actor. Left empty the parent node is used.
@export var actor_path: NodePath
## Debug: draw the focus ray.
@export var draw_debug_ray: bool = false

var _focus: Interactable = null
var _hold_elapsed: float = 0.0
var _hold_target: Interactable = null
var _last_ray_length: float = 0.0


func _physics_process(delta: float) -> void:
	update_focus()
	_process_action(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton):
		return
	# Consumed here so gameplay code does not also react to the same press.
	if event.is_action_pressed(interact_action):
		get_viewport().set_input_as_handled()


## Recomputes the focused interactable from the current aim. Safe to call from
## tests; runs every physics frame at runtime.
func update_focus() -> void:
	var found := _find_target()
	_set_focus(found)


## Attempts to interact with the current focus. Returns true when something
## actually happened, which is what tests assert on.
func try_interact() -> bool:
	if _focus == null:
		return false
	var actor := get_actor()
	if not _focus.interact(actor):
		return false
	interacted.emit(_focus, actor)
	EventBus.interaction_performed.emit(_focus)
	# A one-shot target becomes unavailable immediately; drop focus so the
	# prompt disappears on the same frame instead of lingering.
	if not _focus.is_available(actor):
		_set_focus(null)
	return true


func get_focus() -> Interactable:
	return _focus


func get_actor() -> Node:
	if not actor_path.is_empty():
		return get_node_or_null(actor_path)
	return get_parent()


func get_camera() -> Camera3D:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as Camera3D
	return get_viewport().get_camera_3d()


## Label for the key, read from the InputMap so a remap shows up in the HUD
## without any code change.
func get_action_label() -> String:
	if not InputMap.has_action(interact_action):
		return key_hint_default()
	var events := InputMap.action_get_events(interact_action)
	for event: InputEvent in events:
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
			if code != 0:
				return OS.get_keycode_string(code)
	return key_hint_default()


func key_hint_default() -> String:
	return "E"


func _find_target() -> Interactable:
	var camera := get_camera()
	if camera == null or not is_inside_tree():
		return null
	# `get_world_3d()` is Node3D-only and this probe is a plain Node, so the
	# viewport is the correct source of the 3D world.
	var world := get_viewport().world_3d
	if world == null:
		return null
	var space := world.direct_space_state
	if space == null:
		return null

	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * ray_length, _world_mask()
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _exclude_rids()

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null

	_last_ray_length = origin.distance_to(hit["position"])

	var target := Interactable.resolve(hit["collider"] as Node)
	if target == null:
		return null
	return _accept(target)


## Applies the gates that are not the raycast itself: availability and reach.
func _accept(target: Interactable) -> Interactable:
	var actor := get_actor()
	if not target.is_available(actor):
		return null
	if actor is Node3D:
		var distance := (actor as Node3D).global_position.distance_to(target.get_focus_point())
		if distance > target.max_distance:
			return null
	return target


func _exclude_rids() -> Array[RID]:
	# Without this the ray starts inside the player's own capsule in third
	# person and immediately hits it.
	var out: Array[RID] = []
	var actor := get_actor()
	if actor is CollisionObject3D:
		out.append((actor as CollisionObject3D).get_rid())
	return out


## Which physics layers the aim ray looks for.
##
## World *and* interaction, because the two are not alternatives. The farm's aim
## volumes sit on the interaction layer precisely so they can be aimable without
## being solid — a world-only ray would miss every tile and the plot would be
## unfarmable.
##
## The volumes are kept short instead of being filtered out here. Filtering by
## height in the probe sounds tidier and is not: it rejects genuinely tall props
## standing on the same ground, and it behaves differently in each camera mode,
## where the camera sits at a different height. Short volumes fix the problem at
## the source. See [member FarmGrid.aim_height].
func _world_mask() -> int:
	return PhysicsLayers.INTERACTION_MASK


func _process_action(delta: float) -> void:
	if not Input.is_action_pressed(interact_action):
		_hold_elapsed = 0.0
		_hold_target = null
		return
	if _focus == null:
		return

	var required := _focus.hold_seconds
	if required <= 0.0:
		# Instant action: fire once on the press, then wait for a release.
		if _hold_target != _focus:
			_hold_target = _focus
			_hold_elapsed = 0.0
			try_interact()
		return

	if _hold_target != _focus:
		# Switching targets restarts the hold instead of carrying progress over.
		_hold_target = _focus
		_hold_elapsed = 0.0
	_hold_elapsed += delta
	if _hold_elapsed >= required:
		_hold_elapsed = 0.0
		try_interact()


func _set_focus(target: Interactable) -> void:
	if _focus == target:
		return
	if _focus != null and is_instance_valid(_focus):
		_focus.set_focused(false)
	_focus = target
	if _focus != null:
		_focus.set_focused(true)
		EventBus.interactable_focused.emit(_focus)
	else:
		EventBus.interactable_unfocused.emit(null)
	# Changing target always restarts any hold progress.
	_hold_elapsed = 0.0
	_hold_target = null
	focus_changed.emit(_focus)


## Drops focus, e.g. when the world is paused or the player teleports.
func clear_focus() -> void:
	_set_focus(null)


func get_last_ray_length() -> float:
	return _last_ray_length


## Fraction of the current target's hold requirement that has elapsed, for the
## HUD's progress bar.
func get_hold_progress() -> float:
	if _focus == null or _focus.hold_seconds <= 0.0:
		return 0.0
	return clampf(_hold_elapsed / _focus.hold_seconds, 0.0, 1.0)