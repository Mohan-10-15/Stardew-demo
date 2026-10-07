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
const ClockHudScene := "res://scenes/ui/clock_hud.tscn"
const StatusHudScene := "res://scenes/ui/player_status_hud.tscn"
const HotbarHudScene := "res://scenes/ui/hotbar_hud.tscn"
const QuestTrackerScene := "res://scenes/ui/quest_tracker.tscn"
const ShopUiScene := "res://scenes/ui/shop_ui.tscn"
const LogPanelScene := "res://scenes/ui/log_panel.tscn"
const DialogueUiScene := "res://scenes/ui/dialogue_panel.tscn"

@export var world_scene_path: String = WorldScene
@export var player_scene_path: String = PlayerScene
@export var hud_scene_path: String = HudScene
@export var clock_hud_scene_path: String = ClockHudScene
@export var status_hud_scene_path: String = StatusHudScene
@export var hotbar_hud_scene_path: String = HotbarHudScene
@export var quest_tracker_scene_path: String = QuestTrackerScene
@export var shop_ui_scene_path: String = ShopUiScene
@export var log_panel_scene_path: String = LogPanelScene
@export var dialogue_ui_scene_path: String = DialogueUiScene
## The in-game log. Not read by anything yet — it is spawned, toggled by `F3` and
## otherwise left alone, which is the point: it has to exist before there is a reason
## to want it.
@export var log_panel: CanvasLayer = null
@export var load_world: bool = true
@export var load_player: bool = true
@export var load_hud: bool = true
@export var load_clock_hud: bool = true
@export var load_status_hud: bool = true
@export var load_hotbar_hud: bool = true
@export var load_quest_tracker: bool = true
@export var load_shop_ui: bool = true
@export var load_dialogue_ui: bool = true
@export var load_log_panel: bool = true
@export var load_npcs: bool = true

var world: WorldRoot = null
var player: PlayerController = null
var hud: CanvasLayer = null
var clock_hud: CanvasLayer = null
var status_hud: CanvasLayer = null
var hotbar_hud: CanvasLayer = null
var quest_tracker: CanvasLayer = null
var shop_ui: CanvasLayer = null
var player_state: PlayerStateService = null
var farm_service: FarmService = null
var gathering_service: GatheringService = null
var economy_service: EconomyService = null
var npc_manager: NpcManager = null
var quest_service: QuestService = null
var dialogue_service: DialogueService = null
var dialogue_ui: CanvasLayer = null
var _time_service: TimeService = null


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
	# Before the farm and the economy, because both read the bag, the purse and the
	# stamina through it. It needs no world and no player, so it goes first of the
	# three.
	_spawn_player_state()
	# Between world and player: it needs the world's grid to attach, and the
	# player to exist before it hands out a starting loadout.
	if load_world:
		_spawn_farm_service()
		_spawn_gathering_service()
		_spawn_economy_service()
		_spawn_npc_manager()
		_spawn_quest_service()
		# After the NPC manager: it grants hearts and reads friendship through the
		# manager's group. Both lookups degrade to "nobody home" rather than
		# failing, so the order is a courtesy — but it is the order the real game
		# runs in, and the one a boot should exercise.
		_spawn_dialogue_service()
	if load_player:
		_spawn_player()
	if load_hud:
		_spawn_hud()
	# After the world, because the clock lives inside it and the HUD finds it by
	# walking the tree. Spawning this first would leave the readout disabled.
	if load_clock_hud:
		_spawn_clock_hud()
	# Both of these need `PlayerStateService`, so after the player — and they read
	# it by walking the tree, so they must come after `_spawn_player`.
	if load_status_hud:
		_spawn_status_hud()
	if load_hotbar_hud:
		_spawn_hotbar_hud()
	# After the quest service, and for the same reason as the two above: the tracker
	# walks the tree for it, and a tracker spawned before the service exists would paint
	# an empty panel and never learn there was work to do. It repaints on the quest
	# signals, so an acceptance the player already made is not missed either way.
	if load_quest_tracker:
		_spawn_quest_tracker()
	# Listens on `EventBus.shop_opened`, so it is order-independent: a counter the
	# player opened before this existed would be missed, and it walks the tree for
	# a shop to open if so.
	if load_shop_ui:
		_spawn_shop_ui()
	# Same bargain as the shop panel: a pure listener on the dialogue signals that
	# walks the tree for the service when a conversation starts. Spawned after the
	# service only because that is the order they are used in, not because it has
	# to be.
	if load_dialogue_ui:
		_spawn_overlay(dialogue_ui_scene_path, "dialogue panel", "dialogue_ui")
	# Last, and because it reads nothing but the log: it is the one piece of UI whose
	# subject is the boot itself, so it is the one piece that wants to exist after
	# everything it might report on.
	if load_log_panel:
		_spawn_overlay(log_panel_scene_path, "log panel", "log_panel")

	# The player is up and their state exists, so the opening tool is ready for the
	# first click rather than a frame later.
	if player_state != null:
		player_state.grant_starter_loadout()
		if player_state.wallet != null:
			player_state.wallet.set_gold(player_state.starting_gold)

	GameState.set_phase(GameState.Phase.PLAYING)
	EventBus.game_ready.emit()
	Log.info("Main", "Boot sequence complete")


## The owner of the bag, hotbar, purse and stamina.
##
## Spawned unconditionally and before anything that needs it, because every later
## system looks this node up by group. Making it conditional on `load_world` would
## mean a headless boot with no world silently has no player either.
func _spawn_player_state() -> void:
	player_state = PlayerStateService.new()
	player_state.name = "PlayerState"
	add_child(player_state)
	Log.info("Main", "Spawned player state")


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


func _spawn_clock_hud() -> void:
	if not ResourceLoader.exists(clock_hud_scene_path):
		Log.error("Main", "Clock HUD scene missing at %s" % clock_hud_scene_path)
		return
	var packed := load(clock_hud_scene_path) as PackedScene
	if packed == null:
		Log.error("Main", "Failed to load Clock HUD scene")
		return
	clock_hud = packed.instantiate() as CanvasLayer
	if clock_hud == null:
		Log.error("Main", "Clock HUD scene root is not a CanvasLayer")
		return
	clock_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(clock_hud)
	Log.info("Main", "Spawned clock HUD")


## Spawns a HUD scene as a `CanvasLayer`, or logs and carries on.
##
## One helper for all five rather than five near-copies. They differed only in the
## label they logged, and a copy that forgets the "is it a CanvasLayer" check is
## exactly the kind of divergence that produces a silent no-HUD bug — which is
## what happened before any of these existed.
func _spawn_overlay(path: String, label: String, out_slot: String) -> void:
	if not ResourceLoader.exists(path):
		Log.error("Main", "%s scene missing at %s" % [label, path])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		Log.error("Main", "Failed to load %s scene" % label)
		return
	var layer := packed.instantiate() as CanvasLayer
	if layer == null:
		Log.error("Main", "%s scene root is not a CanvasLayer" % label)
		return
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	# Set through the dictionary rather than by name so a caller cannot typo an
	# assignment into a field that is never read.
	set(out_slot, layer)
	Log.info("Main", "Spawned %s" % label)


func _spawn_status_hud() -> void:
	_spawn_overlay(status_hud_scene_path, "status HUD", "status_hud")


func _spawn_hotbar_hud() -> void:
	_spawn_overlay(hotbar_hud_scene_path, "hotbar HUD", "hotbar_hud")


func _spawn_quest_tracker() -> void:
	_spawn_overlay(quest_tracker_scene_path, "quest tracker", "quest_tracker")


func _spawn_shop_ui() -> void:
	_spawn_overlay(shop_ui_scene_path, "shop UI", "shop_ui")


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


## Spawns the farming system and hands it the plot the world generated.
##
## The grid is built inside `world.tscn`, so it does not exist until the world is
## in the tree. The service is a script-only node rather than a scene because it
## has no visual representation at all — a `.tscn` of two empty properties would
## be ceremony.
func _spawn_farm_service() -> void:
	if world == null:
		Log.error("Main", "Cannot spawn farm service without a world")
		return
	var grid := _find_farm_grid(world)
	if grid == null:
		Log.error("Main", "World contains no FarmGrid; farming disabled")
		return
	farm_service = FarmService.new()
	farm_service.name = "FarmService"
	farm_service.player_state = player_state
	add_child(farm_service)
	farm_service.attach_grid(grid)
	# No loadout here: the player does not exist yet, and a tool handed out before
	# there is anyone to swing it would be granted for a frame with no holder.
	Log.info("Main", "Spawned farm service over %d tiles" % grid.tile_count())


## The chop/mine/forage rules.
##
## Script-only, like the farm service, and for the same reason: it has no visual
## representation. It does *not* attach to anything, though — the resource nodes were
## built by [WorldBuilder] with their own interaction components, and the service is
## found by group from the tree rather than handed a field. That is what lets a test
## drop a service next to a hand-built node and have the two work.
##
## Spawned after the farm service because both read the same [PlayerStateService], and
## before the player, so the first swing of a new game already has somewhere to go.
func _spawn_gathering_service() -> void:
	gathering_service = GatheringService.new()
	gathering_service.name = "GatheringService"
	add_child(gathering_service)
	var field := _find_resource_field(world)
	var count := field.count() if field != null else 0
	Log.info("Main", "Spawned gathering service over %d nodes" % count)


func _find_resource_field(start: Node) -> ResourceField:
	if start == null:
		return null
	if start is ResourceField:
		return start as ResourceField
	for child: Node in start.get_children():
		var found := _find_resource_field(child)
		if found != null:
			return found
	return null


## The buy/sell rules.
##
## After the farm service so that the shop, the farm and the purse all resolve the
## same [PlayerStateService] in the same frame; the order does not actually matter
## because every lookup is by group, and this is written to say so rather than
## leave a reader hunting for a dependency that is not there.
func _spawn_economy_service() -> void:
	economy_service = EconomyService.new()
	economy_service.name = "EconomyService"
	add_child(economy_service)
	Log.info("Main", "Spawned economy service")


func _find_farm_grid(start: Node) -> FarmGrid:
	if start == null:
		return null
	if start is FarmGrid:
		return start
	for child: Node in start.get_children():
		var found := _find_farm_grid(child)
		if found != null:
			return found
	return null


func _spawn_npc_manager() -> void:
	npc_manager = NpcManager.new()
	npc_manager.name = "NpcManager"
	# Before `add_child`, because `_ready` reads it - and the whole day is decided in
	# `_ready`: the grid is built, the clock is found and every villager is pointed at
	# their first destination.
	npc_manager.apply_schedules = true
	add_child(npc_manager)
	Log.info("Main", "Spawned %d villagers" % npc_manager.count())


## The quest log.
##
## After the NPC manager, because it pays heart rewards through it, and after the player
## state, because an objective has to be able to look in the bag. Both lookups also fall
## back to a group search, so this is a convenience rather than a requirement — which is
## what lets a test stand up a quest service next to a bag with no village at all.
func _spawn_quest_service() -> void:
	quest_service = QuestService.new()
	quest_service.name = "QuestService"
	quest_service.player_state = player_state
	quest_service.npc_manager = npc_manager
	add_child(quest_service)
	Log.info("Main", "Spawned quest service over %d jobs" % QuestRegistry.all_quests().size())


## The conversation runner.
##
## Builds no content of its own: the trees come from [DialogueRegistry] when the
## first conversation opens, so booting before the content generator has run is
## a `no_tree` at talk time rather than a crash at boot.
func _spawn_dialogue_service() -> void:
	dialogue_service = DialogueService.new()
	dialogue_service.name = "DialogueService"
	add_child(dialogue_service)
	Log.info("Main", "Spawned dialogue service")


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
	_time_service = TimeService.find(get_tree().get_root())
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