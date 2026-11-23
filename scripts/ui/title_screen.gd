extends CanvasLayer
## The front door. Tells the player what the game is before asking them to
## play, and offers every menu a keyboard, mouse or pad user needs.
##
## The world is already built behind this screen — building a second valley
## for a menu would mean two valleys, two clocks and two sets of listeners.
## The title owns no game state; it asks `main.gd` to start or continue through
## signals, and opens the other panels by finding them in the tree.

signal new_game_requested()
signal continue_requested()

const SAVE_SERVICE_GROUP := &"save_service"

@onready var _continue: Button = get_node_or_null(^"Panel/Column/Continue") as Button

var _camera_rig: Node3D = null
var _camera_base_yaw := 0.0
var _drift := 0.0
var _drift_active := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_wire("NewGame", _on_new_game)
	_wire("Continue", _on_continue)
	_wire("About", _open_about)
	_wire("HowToPlay", _open_how_to_play)
	_wire("Settings", _open_settings)
	_wire("Credits", _open_credits)
	_wire("Quit", _on_quit)
	if OS.get_name() == "Web":
		var quit := get_node_or_null(^"Panel/Column/Quit")
		if quit != null:
			quit.visible = false
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var bus := (loop as SceneTree).root.get_node_or_null(^"EventBus")
		if bus != null and not bus.input_device_changed.is_connected(_refresh_glyphs):
			bus.input_device_changed.connect(_refresh_glyphs)
	_refresh_glyphs()
	refresh()
	var first := get_node_or_null(^"Panel/Column/NewGame") as Button
	if first != null:
		first.grab_focus()


func _wire(node_name: String, handler: Callable) -> void:
	var button := get_node_or_null("Panel/Column/" + node_name) as Button
	if button != null and not button.pressed.is_connected(handler):
		button.pressed.connect(handler)


func _process(delta: float) -> void:
	if not visible or not _drift_active or _camera_rig == null:
		return
	# A slow drift over the live valley. The rig's base yaw is captured when
	# the title opens and restored exactly when it closes — a cinematic idle
	# must never leave the player facing a new direction on New Game.
	_drift += delta
	_camera_rig.rotation.y = _camera_base_yaw + sin(_drift * 0.18) * 0.09


## Enables Continue only when a save actually exists.
func refresh() -> void:
	if _continue == null:
		return
	var save := _find_service()
	_continue.disabled = save == null or not bool(save.call("has_save"))


func show_title() -> void:
	visible = true
	refresh()
	_camera_rig = _find_named(get_tree().root, &"CameraRig") as Node3D
	if _camera_rig != null:
		_camera_base_yaw = _camera_rig.rotation.y
		_drift = 0.0
		_drift_active = true


func hide_title() -> void:
	if _drift_active and _camera_rig != null and is_instance_valid(_camera_rig):
		_camera_rig.rotation.y = _camera_base_yaw
	_drift_active = false
	visible = false


func _refresh_glyphs(_device: int = 0) -> void:
	var hint := get_node_or_null(^"Panel/Column/Hint") as Label
	if hint == null:
		return
	hint.text = "%s saves  •  %s loads" % [
		InputGlyphs.label_for(InputActions.SAVE_GAME),
		InputGlyphs.label_for(InputActions.LOAD_GAME),
	]


func _on_new_game() -> void:
	hide_title()
	new_game_requested.emit()


func _on_continue() -> void:
	hide_title()
	continue_requested.emit()


func _panel(name: String) -> Node:
	return _find_named(get_tree().root, name)


func _open_about() -> void:
	var panel := _panel(&"AboutPanel")
	if panel != null and panel.has_method("open"):
		panel.call("open", true)


func _open_how_to_play() -> void:
	var panel := _panel(&"AboutPanel")
	if panel != null and panel.has_method("open"):
		panel.call("open", true, &"how_to_play")


func _open_settings() -> void:
	var panel := _panel(&"SettingsUI")
	if panel != null and panel.has_method("open_panel"):
		panel.call("open_panel")


func _open_credits() -> void:
	var panel := _panel(&"CreditsPanel")
	if panel != null and panel.has_method("open"):
		panel.call("open")


func _on_quit() -> void:
	get_tree().quit(0)


func _find_service() -> Node:
	return _find_group(get_tree().root, SAVE_SERVICE_GROUP)


func _find_group(node: Node, group: StringName) -> Node:
	if node == null:
		return null
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _find_group(child, group)
		if found != null:
			return found
	return null


func _find_named(node: Node, wanted: StringName) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
