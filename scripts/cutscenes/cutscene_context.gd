class_name CutsceneContext
extends RefCounted
## The snapshot of everything a cutscene is about to change.
##
## Restoration is unconditional and driven by this object, never by how far
## playback got. A cutscene that errors on its first step restores exactly as
## one that finished, which is the single hardest rule in the guide.

var cutscene_id: StringName = &""
var was_paused: bool = false
var was_phase: int = 0
var camera_path: NodePath = NodePath()
var camera_transform: Transform3D = Transform3D.IDENTITY
var flags_before: Dictionary = {}
var flags: Dictionary = {}
var reached_index: int = 0
var catchup_done: bool = false


func capture(world: Node, id: StringName) -> void:
	cutscene_id = id
	var state := _find(world, "GameState")
	if state != null:
		was_paused = bool(state.get("paused"))
		was_phase = int(state.get("phase"))
	var camera := _find_camera(world)
	if camera != null:
		camera_path = camera.get_path()
		camera_transform = camera.global_transform


func set_flag(name: StringName, value: bool = true) -> void:
	if not flags_before.has(name):
		flags_before[name] = false
	flags[name] = value


func restore(world: Node) -> void:
	var state := _find(world, "GameState")
	if state != null:
		if was_paused:
			state.call("set_paused", true)
		else:
			state.call("set_paused", false)
			state.call("set_phase", was_phase)
	if not camera_path.is_empty():
		var camera := world.get_node_or_null(camera_path)
		if camera is Node3D:
			(camera as Node3D).global_transform = camera_transform
	for name: StringName in flags_before:
		# Flags a cutscene sets persist through a skip (catch-up), but the
		# director replays them explicitly; restoration only removes the
		# transient camera/phase changes, never gameplay progress.
		pass


static func _find(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


static func _find_camera(node: Node) -> Camera3D:
	if node == null:
		return null
	if node is Camera3D and (node as Camera3D).current:
		return node as Camera3D
	for child: Node in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null
