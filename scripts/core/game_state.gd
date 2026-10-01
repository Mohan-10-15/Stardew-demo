extends Node
## Autoload: `GameState`
##
## Global game flow / runtime state. Owns the current scene, pause handling and
## scene transitions. Feature systems (farming, time, NPCs, ...) do *not* hang
## off this node; they register themselves with `EventBus`.

enum Phase { BOOTING, TITLE, LOADING, PLAYING, PAUSED, GAME_OVER }

var phase: Phase = Phase.BOOTING
var current_scene: Node = null
var paused: bool = false

var _transition_layer: CanvasLayer = null
var _fade: ColorRect = null
const FADE_TIME := 0.35


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_transition_layer()
	Log.info("GameState", "Initialised")


func _build_transition_layer() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "TransitionLayer"
	_transition_layer.layer = 128
	_transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_transition_layer)

	_fade = ColorRect.new()
	_fade.name = "FadeRect"
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(_fade)


func set_phase(new_phase: Phase) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	Log.info("GameState", "Phase -> %s" % Phase.keys()[new_phase])


func is_playing() -> bool:
	return phase == Phase.PLAYING


func get_phase_name(value: Variant = null) -> String:
	var idx := int(phase) if value == null else int(value)
	if idx < 0 or idx >= Phase.size():
		return "UNKNOWN"
	return Phase.keys()[idx]


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	get_tree().paused = value
	if not value:
		set_phase(Phase.PLAYING)
	EventBus.game_paused.emit(value)
	Log.info("GameState", "Paused: %s" % value)


func toggle_pause() -> void:
	if phase == Phase.PLAYING:
		set_phase(Phase.PAUSED)
		set_paused(true)
	elif phase == Phase.PAUSED:
		set_paused(false)


## Swaps the active gameplay scene with a fade. Returns once loaded.
func change_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		Log.error("GameState", "Cannot change to missing scene: %s" % scene_path)
		return
	set_phase(Phase.LOADING)
	await fade_out()
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		Log.error("GameState", "change_scene_to_file failed (%d) for %s" % [err, scene_path])
	current_scene = get_tree().current_scene
	await fade_in()
	set_phase(Phase.PLAYING)
	EventBus.world_loaded.emit()


func register_current_scene(scene: Node) -> void:
	current_scene = scene


func fade_out(duration: float = FADE_TIME) -> void:
	if _fade == null:
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, duration)
	await tw.finished


func fade_in(duration: float = FADE_TIME) -> void:
	if _fade == null:
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, duration)
	await tw.finished


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		EventBus.game_quitting.emit()