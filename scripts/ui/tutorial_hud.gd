extends CanvasLayer
## A single non-blocking hint at the bottom of the screen. It never takes
## focus, never pauses, and disappears when the chain is done or skipped.

@onready var _label: Label = get_node_or_null(^"Panel/Hint") as Label

var _service: TutorialService = null


func _ready() -> void:
	layer = 13
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = TutorialService.find(get_tree().get_root())
	var bus := _bus()
	if bus != null:
		bus.input_device_changed.connect(_on_device)
		bus.settings_applied.connect(_on_settings)
	if _service != null:
		if not _service.step_changed.is_connected(_on_step):
			_service.step_changed.connect(_on_step)
		_on_step(_service.current_step())


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.input_device_changed.is_connected(_on_device):
		bus.input_device_changed.disconnect(_on_device)
	if bus.settings_applied.is_connected(_on_settings):
		bus.settings_applied.disconnect(_on_settings)


func _on_device(_device: int) -> void:
	if _service != null:
		_on_step(_service.current_step())


func _on_settings() -> void:
	if _service != null:
		_on_step(_service.current_step())


func _on_step(step: TutorialStep) -> void:
	if _label == null or _service == null:
		return
	if step == null or not _service.enabled:
		_label.text = ""
		visible = false
		return
	visible = true
	_label.text = "TIP  " + _service.hint_for(step)


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
