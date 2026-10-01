extends SceneTree
## Boot verification: launches the main scene headlessly and asserts it reaches
## a playable state with no script errors.
##
## Run:
##     godot --headless --path . --script res://tools/boot_check.gd
##
## NOTE: autoload singletons are *not* available as global identifiers in a
## `--script` run (the script compiles before autoloads register), so they are
## fetched from the tree root by name instead.
##
## Exits 0 on success, 1 on failure.

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TIMEOUT_SECONDS := 6.0

var _timer: SceneTreeTimer = null
var _saw_game_ready := false
var _saw_world_loaded := false


func _initialize() -> void:
	var scene := root.get_node_or_null(^"Main")
	if scene == null:
		var packed := load(MAIN_SCENE) as PackedScene
		if packed == null:
			_fail("main scene failed to load: %s" % MAIN_SCENE)
			return
		scene = packed.instantiate()
		root.add_child(scene)

	var bus := root.get_node_or_null(^"EventBus")
	if bus == null:
		_fail("EventBus autoload missing")
		return

	if not bus.game_ready.is_connected(_on_game_ready):
		bus.game_ready.connect(_on_game_ready)
	if not bus.world_loaded.is_connected(_on_world_loaded):
		bus.world_loaded.connect(_on_world_loaded)

	print("[boot_check] running main scene headlessly (max %.0fs)" % TIMEOUT_SECONDS)
	# SceneTree has no _process(); a timer is the reliable polling mechanism.
	_timer = create_timer(TIMEOUT_SECONDS)
	_timer.timeout.connect(_finish)


func _on_game_ready() -> void:
	_saw_game_ready = true
	print("[boot_check] EventBus.game_ready fired")


func _on_world_loaded() -> void:
	_saw_world_loaded = true
	print("[boot_check] EventBus.world_loaded fired")


func _fail(reason: String) -> void:
	printerr("[boot_check] FAIL: %s" % reason)
	quit(1)


func _finish() -> void:
	if not _saw_game_ready:
		_fail("EventBus.game_ready never fired")
		return

	var main := root.get_node_or_null(^"Main")
	if main == null:
		_fail("Main node missing from the tree after boot")
		return

	var game_state := root.get_node_or_null(^"GameState")
	if game_state == null:
		_fail("GameState autoload missing after boot")
		return

	var phase: int = game_state.phase
	if phase == 0:
		_fail("GameState stuck in BOOTING")
		return

	# A dependency that fails to parse (e.g. WorldBuilder) makes main.tscn
	# instantiate as a bare Node3D with no script. Its autoloads still exist and
	# GameState can still leave BOOTING, so the checks above would all pass and
	# report a green boot for a scene that does nothing. Assert the script is
	# really attached.
	if not (main is Node):
		_fail("Main is not a Node")
		return
	if main.get_script() == null:
		_fail("Main has no script attached - a dependency failed to parse")
		return

	# The subsystems main builds are the actual deliverable of a boot, so
	# require them by type rather than by name (the HUD's node name comes from
	# its own scene, not from main).
	var found_world := false
	var found_player := false
	var found_hud := false
	for child: Node in main.get_children():
		if child is WorldRoot:
			found_world = true
		elif child is PlayerController:
			found_player = true
		elif child is CanvasLayer:
			found_hud = true
	if not found_world:
		_fail("Main did not build a WorldRoot child")
		return
	if not found_player:
		_fail("Main did not build a PlayerController child")
		return
	if not found_hud:
		_fail("Main did not build a CanvasLayer (HUD) child")
		return

	# Sanity-check the autoload wiring survives a real scene boot.
	for name: StringName in [&"EventBus", &"Log", &"Config", &"GameState", &"Debug"]:
		if root.get_node_or_null(NodePath(String(name))) == null:
			_fail("autoload '%s' missing after boot" % name)

	print("[boot_check] OK: booted, phase=%s, main children=%d, config=%s" % [
		game_state.get_phase_name(phase), main.get_child_count(),
		str(_node(&"Config").settings != null),
	])
	quit(0)


func _node(name: StringName) -> Node:
	return root.get_node_or_null(NodePath(String(name)))


func _init() -> void:
	# _initialize() runs after autoloads are attached; nothing to do here.
	pass