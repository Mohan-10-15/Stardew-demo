extends TestSuite
## The title screen: Continue must only be offered when a save exists, and both
## buttons must announce intent rather than reaching into `main.gd`.

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const SAVE_STUB := "res://tests/helpers/save_stub.gd"

var _rig: Node3D = null
var _new_game := 0
var _continue := 0


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"continue_needs_a_save",
		&"both_buttons_announce_intent",
	]


func setup() -> void:
	_rig = null
	_new_game = 0
	_continue = 0


func teardown() -> void:
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"continue_needs_a_save":
			return await _t_continue_gate()
		&"both_buttons_announce_intent":
			return await _t_buttons()
	return fail(case, "no case implementation for %s" % case)


func _build(has_save: bool) -> Dictionary:
	_reset_rig()
	var packed := load(TITLE_SCENE) as PackedScene
	var stub_script := load(SAVE_STUB) as GDScript
	if packed == null or stub_script == null:
		return {}
	_ensure_rig()
	var stub: Node = stub_script.new()
	stub.name = "SaveService"
	stub.set("has_save_value", has_save)
	stub.add_to_group(&"save_service")
	_rig.add_child(stub)
	var title: CanvasLayer = packed.instantiate() as CanvasLayer
	_rig.add_child(title)
	await _step(2)
	return {"title": title, "stub": stub}


func _t_continue_gate() -> Dictionary:
	var c := &"continue_needs_a_save"
	var empty := await _build(false)
	if empty.is_empty():
		return fail(c, "could not build the title")
	var button: Button = empty["title"].get_node_or_null(^"Panel/Column/Continue") as Button
	if button == null or not button.disabled:
		return fail(c, "Continue is offered without a save")
	var saved := await _build(true)
	var enabled: Button = saved["title"].get_node_or_null(^"Panel/Column/Continue") as Button
	if enabled == null or enabled.disabled:
		return fail(c, "Continue stayed disabled with a save present")
	return succeeded(c, "Continue tracks the presence of a save")


func _t_buttons() -> Dictionary:
	var c := &"both_buttons_announce_intent"
	var built := await _build(true)
	if built.is_empty():
		return fail(c, "could not build the title")
	var title: CanvasLayer = built["title"]
	title.new_game_requested.connect(_on_new)
	title.continue_requested.connect(_on_continue)
	var new_button: Button = title.get_node_or_null(^"Panel/Column/NewGame") as Button
	var continue_button: Button = title.get_node_or_null(^"Panel/Column/Continue") as Button
	new_button.pressed.emit()
	continue_button.pressed.emit()
	if _new_game != 1 or _continue != 1:
		return fail(c, "%d new, %d continue signals" % [_new_game, _continue])
	return succeeded(c, "each button publishes exactly one intent")


func _on_new() -> void: _new_game += 1
func _on_continue() -> void: _continue += 1


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "TitleTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
