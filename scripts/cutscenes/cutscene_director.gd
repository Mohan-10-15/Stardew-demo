class_name CutsceneDirector
extends Node
## Plays data-authored cutscenes and owns the single player lock.
##
## Built against `docs/CUTSCENE_GUIDE.md`: playwrights, snapshot, unconditional
## restoration, and skipping that still applies the flags and rewards of the
## events it cuts past. The director never knows what a quest is; an event's
## `params` carry the id and the gameplay services do the work.

const SERVICE_GROUP := &"cutscene_service"
const REGISTRY_SCRIPT := "res://scripts/cutscenes/cutscene_registry.gd"
const OVERLAY_SCENE := "res://scenes/cutscenes/cutscene_overlay.tscn"

signal started(id: StringName)
signal finished(id: StringName)
signal skipped(id: StringName)

## Flags applied by the last cutscene, kept after restoration so a test (or a
## later quest) can ask what the cutscene changed without holding the context.
var applied_flags: Dictionary = {}

var _current: CutscenePlayer = null
var _context: CutsceneContext = null
var _overlay: CanvasLayer = null
var _skipping: bool = false
var _running: bool = false
var _required_hold: bool = false
var _required_index: int = -1


static func find(start: Node) -> CutsceneDirector:
	if start == null:
		return null
	if start is CutsceneDirector:
		return start as CutsceneDirector
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	# The game is paused while a cutscene owns the screen; without this the
	# director would pause itself along with everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus != null:
		bus.cutscene_requested.connect(play)
	_ensure_overlay()
	Log.info("Cutscene", "Director ready")


func _exit_tree() -> void:
	var bus := _bus()
	if bus != null and bus.cutscene_requested.is_connected(play):
		bus.cutscene_requested.disconnect(play)
	if _running:
		_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	if _running and not _skipping and event.is_action_pressed(InputActions.INTERACT):
		get_viewport().set_input_as_handled()
		skip()


func play(id: StringName) -> bool:
	if _running:
		Log.warn("Cutscene", "'%s' requested while '%s' is playing" % [
			id, _current.id if _current != null else "none",
		])
		return false
	var registry_script := load(REGISTRY_SCRIPT) as GDScript
	var cutscene: CutscenePlayer = registry_script.call("cutscene_for", id)
	if cutscene == null:
		Log.warn("Cutscene", "no cutscene named '%s'" % id)
		return false
	_current = cutscene
	_context = CutsceneContext.new()
	_context.capture(get_tree().get_root(), id)
	_skipping = false
	_running = true
	_lock_player(true)
	var bus := _bus()
	if bus != null:
		bus.cutscene_started.emit(id)
	started.emit(id)
	_run()
	return true


func _run() -> void:
	var count := _current.events.size()
	for i: int in range(count):
		if not _running:
			return
		_context.reached_index = i
		var event: CutsceneEvent = _current.events[i]
		if _skipping:
			if event.skip_mode == CutsceneEvent.SkipMode.SKIP_REQUIRED:
				_required_hold = true
				_required_index = i
				_skipping = false
			elif event.skip_mode == CutsceneEvent.SkipMode.SKIP_APPLY:
				_apply_effect(event)
			continue
		await _run_event(event)
	# A skip requested on a required event stops playback here; the required
	# event is replayed before finishing.
	if _required_hold and _required_index >= 0 and _required_index < count:
		_required_hold = false
		var index := _required_index
		_required_index = -1
		await _run_event(_current.events[index])
	_finish(false)


func _run_event(event: CutsceneEvent) -> void:
	_apply_effect(event)
	match event.kind:
		&"wait", &"dialogue":
			if event.kind == &"dialogue":
				_set_text(String(event.text))
			await _wait(event.seconds)
			if event.kind == &"dialogue":
				_set_text("")
		&"camera_move":
			var camera := _camera()
			if camera != null and event.params.has("position"):
				camera.global_position = event.params["position"]
			await _wait(0.1)
		&"fade":
			_set_fade(float(event.params.get("alpha", 0.0)))
			await _wait(event.seconds)
		_:
			pass


func _apply_effect(event: CutsceneEvent) -> void:
	match event.kind:
		&"flag":
			_context.set_flag(StringName(event.params.get("name", &"")),
				bool(event.params.get("value", true)))
		&"play_sound":
			var audio := _audio()
			if audio != null:
				audio.call("play_sfx", StringName(event.params.get("id", &"")))
		&"play_music":
			var audio := _audio()
			if audio != null:
				audio.call("play_music", StringName(event.params.get("id", &"")))
		&"letterbox":
			_show_letterbox(bool(event.params.get("show", true)))


## Skipping is a completion with a shortcut. Effects the guide marks
## `SKIP_APPLY` still land; camera flourishes and sounds do not.
func skip() -> void:
	if not _running or _skipping:
		return
	_skipping = true


func _finish(was_interrupted: bool) -> void:
	if not _running:
		return
	_running = false
	_lock_player(false)
	_set_text("")
	_set_fade(0.0)
	_show_letterbox(false)
	if _context != null:
		applied_flags = _context.flags.duplicate()
		_context.restore(get_tree().get_root())
	var id: StringName = _current.id if _current != null else &""
	var bus := _bus()
	if bus != null:
		if was_interrupted or _skipping:
			bus.cutscene_skipped.emit(id)
			skipped.emit(id)
		else:
			bus.cutscene_finished.emit(id)
			finished.emit(id)
	_context = null
	_current = null


func _lock_player(lock: bool) -> void:
	var state := _find_named(get_tree().get_root(), "GameState")
	if state == null:
		return
	if lock:
		state.call("set_paused", true)
	else:
		state.call("set_paused", false)
		var player := _find_named(get_tree().get_root(), "Player")
		if player != null and _context != null and _context.was_phase != -1:
			player.set("velocity", Vector3.ZERO)


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return
	# process_always: the cutscene clock is not game time and must advance
	# while GameState has the rest of the tree paused.
	await get_tree().create_timer(seconds, true, false, true).timeout


func _ensure_overlay() -> void:
	if not ResourceLoader.exists(OVERLAY_SCENE):
		return
	var packed := load(OVERLAY_SCENE) as PackedScene
	if packed == null:
		return
	_overlay = packed.instantiate() as CanvasLayer
	_overlay.name = "CutsceneOverlay"
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().get_root().add_child(_overlay)


func _set_text(value: String) -> void:
	if _overlay == null:
		return
	var label := _overlay.get_node_or_null(^"Panel/Column/Text") as Label
	if label != null:
		label.text = value


func _show_letterbox(value: bool) -> void:
	if _overlay == null:
		return
	var bars := _overlay.get_node_or_null(^"Bars")
	if bars != null:
		bars.visible = value


func _set_fade(alpha: float) -> void:
	if _overlay == null:
		return
	var fade := _overlay.get_node_or_null(^"Fade") as ColorRect
	if fade != null:
		var color := fade.color
		color.a = clampf(alpha, 0.0, 1.0)
		fade.color = color


func _camera() -> Camera3D:
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


func _audio() -> Node:
	var manager := _find_named(get_tree().get_root(), "AudioManager")
	return manager


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
