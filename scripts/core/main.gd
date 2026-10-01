extends Node
## Main game scene root.
##
## Responsibilities are deliberately thin:
##   * build the boot sequence
##   * own global pause / camera-switch input
##   * register itself with [GameState]
##
## Feature systems (farming, time, NPCs, ...) are added by later groups and
## communicate only through `EventBus`.

const WorldScene := "res://scenes/world/world.tscn"
const PlayerScene := "res://scenes/player/player.tscn"
const HudScene := "res://scenes/ui/interaction_hud.tscn"

@export var world_scene_path: String = WorldScene
@export var player_scene_path: String = PlayerScene
@export var hud_scene_path: String = HudScene
@export var load_world: bool = true
@export var load_player: bool = true
@export var load_hud: bool = true

var world: WorldRoot = null
var player: PlayerController = null
var hud: CanvasLayer = null


func _ready() -> void:
	GameState.register_current_scene(self)
	Log.info("Main", "Boot sequence starting")

	# Global input handling that must work while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_boot()


func _exit_tree() -> void:
	Log.info("Main", "Shutting down")


func _boot() -> void:
	EventBus.game_paused.connect(func(p: bool): Log.info("Main", "game paused=%s" % p))
	await get_tree().process_frame

	if load_world:
		_spawn_world()
	if load_player:
		_spawn_player()
	if load_hud:
		_spawn_hud()

	GameState.set_phase(GameState.Phase.PLAYING)
	EventBus.game_ready.emit()
	Log.info("Main", "Boot sequence complete")


## The HUD needs the player to exist first: it locates the interaction probe at
## runtime, so spawning it earlier would leave it without a target.
func _spawn_hud() -> void:
	if not ResourceLoader.exists(hud_scene_path):
		Log.error("Main", "HUD scene missing at %s" % hud_scene_path)
		return
	var packed := load(hud_scene_path) as PackedScene
	if packed == null:
		Log.error("Main", "Failed to load HUD scene")
		return
	hud = packed.instantiate() as CanvasLayer
	if hud == null:
		Log.error("Main", "HUD scene root is not a CanvasLayer")
		return
	# Must keep drawing while the game is paused so the pause menu can show.
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	Log.info("Main", "Spawned HUD")


func _spawn_world() -> void:
	if not ResourceLoader.exists(world_scene_path):
		Log.error("Main", "World scene missing at %s" % world_scene_path)
		return
	var packed := load(world_scene_path) as PackedScene
	if packed == null:
		Log.error("Main", "Failed to load world scene")
		return
	world = packed.instantiate() as WorldRoot
	if world == null:
		Log.error("Main", "World scene root is not a WorldRoot")
		return
	add_child(world)
	Log.info("Main", "Spawned world")


func _spawn_player() -> void:
	if world == null:
		Log.error("Main", "Cannot spawn player without a world")
		return
	if not ResourceLoader.exists(player_scene_path):
		Log.error("Main", "Player scene missing at %s" % player_scene_path)
		return
	var packed := load(player_scene_path) as PackedScene
	if packed == null:
		Log.error("Main", "Failed to load player scene")
		return
	player = packed.instantiate() as PlayerController
	if player == null:
		Log.error("Main", "Player scene root is not a PlayerController")
		return
	# Position must be applied after the node enters the tree: writing
	# `global_position` on a parentless node makes the engine log an
	# "!is_inside_tree()" error every boot.
	add_child(player)
	player.global_position = world.get_spawn_point()
	Log.info("Main", "Spawned player at %s" % player.global_position)


func _unhandled_input(event: InputEvent) -> void:
	# Camera switching is owned solely by [CameraRig]. Handling it here as well
	# raced the rig for the same action and could consume the press without
	# toggling anything.
	if event.is_action_pressed(InputActions.PAUSE):
		GameState.toggle_pause()
		# Releasing the cursor on pause lets the player reach the menu.
		if player != null:
			player.set_mouse_captured(not GameState.paused)
		get_viewport().set_input_as_handled()