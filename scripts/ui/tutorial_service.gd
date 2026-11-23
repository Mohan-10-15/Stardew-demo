class_name TutorialService
extends Node
## A non-blocking first-day hint chain. It never locks input, never opens a
## modal, and each step completes on a real EventBus signal (or a real input
## action where no signal exists). Skippable forever in Settings; the current
## step is saved so reload does not restart the tutorial.

const DIR := "res://resources/ui/tutorial/"
const SERVICE_GROUP := &"tutorial_service"

signal step_changed(step: TutorialStep)
signal tutorial_completed()
signal tutorial_skipped()

var steps: Array[TutorialStep] = []
var current: int = 0
var enabled: bool = true
var _connected: Array[StringName] = []


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	_load_steps()
	enabled = bool(Config.settings.tutorial_enabled)
	_connect_signals()
	_emit_current()


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	for signal_name: StringName in _connected:
		if bus.has_signal(signal_name) and bus.is_connected(signal_name, _on_signal):
			bus.disconnect(signal_name, _on_signal)


func _load_steps() -> void:
	steps.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var step := ResourceLoader.load(DIR + entry) as TutorialStep
			if step != null and step.is_valid():
				steps.append(step)
	steps.sort_custom(func(a: TutorialStep, b: TutorialStep) -> bool: return a.order < b.order)


func _connect_signals() -> void:
	var bus := _bus()
	if bus == null:
		return
	for step: TutorialStep in steps:
		var signal_name := step.completion_signal
		if signal_name == &"" or _connected.has(signal_name):
			continue
		if not bus.has_signal(signal_name):
			push_warning("[Tutorial] EventBus has no signal %s" % signal_name)
			continue
		bus.connect(signal_name, _on_signal)
		_connected.append(signal_name)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or current >= steps.size() or event.is_echo():
		return
	var action := steps[current].completion_action
	if action != &"" and event.is_action_pressed(action):
		_advance()


func _on_signal(_a = null, _b = null, _c = null) -> void:
	_advance()


func _advance() -> void:
	if not enabled or current >= steps.size():
		return
	current += 1
	if current >= steps.size():
		tutorial_completed.emit()
		_emit_current()
	else:
		_emit_current()


func _emit_current() -> void:
	if current < steps.size():
		step_changed.emit(steps[current])
	else:
		step_changed.emit(null)


static func find(start: Node) -> TutorialService:
	if start == null:
		return null
	if start is TutorialService:
		return start as TutorialService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func current_step() -> TutorialStep:
	if current < steps.size():
		return steps[current]
	return null


func hint_for(step: TutorialStep) -> String:
	return _substitute(step.hint) if step != null else ""


func current_hint() -> String:
	if not enabled or current >= steps.size():
		return ""
	return _substitute(steps[current].hint)


func _substitute(text: String) -> String:
	var pairs := {
		"{move}": InputGlyphs.label_for(InputActions.MOVE_FORWARD),
		"{look}": InputGlyphs.label_for(InputActions.LOOK_RIGHT),
		"{interact}": InputGlyphs.label_for(InputActions.INTERACT),
		"{use}": InputGlyphs.label_for(InputActions.USE),
		"{hotbar}": InputGlyphs.label_for(InputActions.HOTBAR_1),
		"{inventory}": InputGlyphs.label_for(InputActions.INVENTORY),
	}
	for key: String in pairs:
		text = text.replace(key, pairs[key])
	return text


func skip() -> void:
	if not enabled:
		return
	enabled = false
	Config.set_value(&"accessibility", "tutorial_enabled", false)
	tutorial_skipped.emit()
	step_changed.emit(null)


func to_dict() -> Dictionary:
	return {"current": current, "enabled": enabled}


func from_dict(data: Dictionary) -> void:
	current = clampi(int(data.get("current", 0)), 0, steps.size())
	enabled = bool(data.get("enabled", enabled))


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
