class_name AudioManager
extends Node
## Owns sound, music and ambience. A manager, not a system: it holds no gameplay
## rules, listens to `EventBus`, and can be removed by deleting this node.
##
## Built against `docs/AUDIO_GUIDE.md`. Every distinct outcome already has a
## distinct EventBus signal, so each one is mapped here to its own sound — no
## gameplay code calls `play_sfx` to announce that something succeeded.

const SERVICE_GROUP := &"audio_service"
## Loaded by path so a fresh checkout compiles before the new global classes
## are registered — the same trap a `--script` tool hits.
const SYNTH_SCRIPT := "res://scripts/audio/audio_synth.gd"
const DEFINITION_SCRIPT := "res://resources/audio/audio_definition.gd"
const BUS_NAMES: Array[StringName] = [&"Music", &"SFX", &"Ambient", &"UI"]

## The one place a signal becomes a sound. Tests assert both that every key
## resolves to a real definition and that no two distinct outcomes share one.
const SOUND_FOR_SIGNAL: Dictionary = {
	&"soil_tilled": &"hoe_till",
	&"soil_watered": &"water_pour",
	&"crop_planted": &"seed_plant",
	&"crop_harvested": &"crop_harvest",
	&"farming_failed": &"farming_fail",
	&"resource_hit": &"gather_hit",
	&"resource_depleted": &"gather_collect",
	&"gathering_failed": &"gather_fail",
	&"npc_talked": &"npc_talk",
	&"npc_gift_failed": &"gift_refused",
	&"romance_started": &"romance_started",
	&"romance_started_failed": &"romance_refused",
	&"npc_married": &"marriage",
	&"npc_propose_failed": &"propose_refused",
	&"quest_accepted": &"quest_accepted",
	&"quest_accepted_failed": &"quest_accept_refused",
	&"quest_turned_in": &"quest_completed",
	&"quest_turned_in_failed": &"quest_turnin_refused",
	&"item_purchased": &"shop_buy",
	&"item_sold": &"shop_sell",
	&"trade_failed": &"trade_refused",
	&"tool_broken": &"tool_broken",
	&"day_started": &"day_start",
	&"dialogue_failed": &"dialogue_failed",
	&"stamina_exhausted": &"stamina_empty",
	&"hotbar_selection_changed": &"ui_move",
	&"shop_opened": &"ui_open",
	&"fishing_cast": &"fish_cast",
	&"fish_bite": &"fish_bite",
	&"fish_caught": &"fish_caught",
	&"fish_escaped": &"fish_escaped",
	&"craft_succeeded": &"craft_ok",
	&"craft_failed": &"craft_fail",
	&"animal_fed": &"animal_feed",
	&"animal_product_collected": &"animal_product",
	&"animal_feed_failed": &"animal_refused",
	&"animal_purchased": &"animal_bought",
	&"machine_placed": &"machine_placed",
	&"machine_loaded": &"machine_load",
	&"machine_load_failed": &"machine_refused",
	&"machine_collected": &"machine_done",
	&"machine_collect_failed": &"machine_empty",
	&"dish_cooked": &"cook_done",
	&"cook_failed": &"cook_refused",
	&"building_placed": &"building_placed",
	&"building_upgraded": &"building_upgraded",
	&"building_failed": &"building_refused",
}

const POOL_SIZE := 12

var _players: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _ambience: Array[AudioStreamPlayer] = []
var _music_index: int = 0
var _ambience_index: int = 0
var _paused: bool = false
var _disabled: bool = false
var _current_music: StringName = &""
var _current_ambience: StringName = &""


static func find(start: Node) -> AudioManager:
	if start == null:
		return null
	if start is AudioManager:
		return start as AudioManager
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	_setup_buses()
	_build_players()
	_wire()
	var config: Node = get_node_or_null(^"/root/Config")
	if config != null and config.has_signal("settings_applied"):
		config.connect("settings_applied", _apply_settings)
	_apply_settings()
	var bus := autoload_bus()
	if bus != null:
		bus.game_paused.connect(_on_paused)
	Log.info("Audio", "Audio manager ready (%d sounds, %d players)" % [
		AudioRegistry.all_sounds().size(), _players.size(),
	])


func _exit_tree() -> void:
	var bus := autoload_bus()
	if bus != null and bus.game_paused.is_connected(_on_paused):
		bus.game_paused.disconnect(_on_paused)
	var config: Node = get_node_or_null(^"/root/Config")
	if config != null and config.has_signal("settings_applied") \
			and config.is_connected("settings_applied", _apply_settings):
		config.disconnect("settings_applied", _apply_settings)


func autoload_bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


## Creates the four child buses under Master. Re-running is safe: a bus that
## already exists is left alone rather than duplicated.
func _setup_buses() -> void:
	if AudioServer.get_bus_count() == 0:
		_disabled = true
		Log.warn("Audio", "no audio buses; the game will be silent")
		return
	for name: StringName in BUS_NAMES:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(index, name)
			AudioServer.set_bus_send(index, &"Master")


func _build_players() -> void:
	for i: int in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)
	for i: int in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = &"Music"
		add_child(player)
		_music.append(player)
	for i: int in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "Ambience%d" % i
		player.bus = &"Ambient"
		add_child(player)
		_ambience.append(player)


## Plays a sound by id. A missing id or a broken stream is one warning and
## silence — never an error that stops the game.
func play_sfx(id: StringName, bus_override: StringName = &"") -> void:
	if _disabled or id.is_empty():
		return
	var definition := AudioRegistry.sound_for(id)
	if definition == null:
		Log.warn("Audio", "no sound definition for '%s'" % id)
		return
	var player := _free_player()
	if player == null:
		return
	var synth := load(SYNTH_SCRIPT) as GDScript
	var definition_script := load(DEFINITION_SCRIPT) as GDScript
	player.stream = synth.call(&"stream_for", definition)
	player.bus = bus_override if not bus_override.is_empty() \
		else definition_script.call(&"bus_name", definition.bus)
	var pitch := 1.0
	if definition.pitch_max > 1.0:
		pitch = randf_range(1.0, definition.pitch_max)
	player.pitch_scale = pitch
	player.play()


func _free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if not player.playing:
			return player
	# All busy: steal the oldest rather than dropping a distinct outcome.
	return _players[0]


## Crossfades a looping cue on the music bus. Two players so the old cue fades
## while the new one comes up — a hard cut is the audio equivalent of an NPC
## teleporting.
func play_music(id: StringName) -> void:
	if _disabled or id == _current_music:
		return
	var definition := AudioRegistry.sound_for(id)
	if definition == null:
		Log.warn("Audio", "no music cue for '%s'" % id)
		return
	_current_music = id
	var incoming := _music[1 - _music_index]
	var outgoing := _music[_music_index]
	var synth := load(SYNTH_SCRIPT) as GDScript
	incoming.stream = synth.call(&"stream_for", definition)
	incoming.volume_db = -40.0
	incoming.play()
	_crossfade(outgoing, incoming)
	_music_index = 1 - _music_index


func play_ambience(id: StringName) -> void:
	if _disabled or id == _current_ambience:
		return
	var definition := AudioRegistry.sound_for(id)
	if definition == null:
		Log.warn("Audio", "no ambience cue for '%s'" % id)
		return
	_current_ambience = id
	var incoming := _ambience[1 - _ambience_index]
	var outgoing := _ambience[_ambience_index]
	var synth := load(SYNTH_SCRIPT) as GDScript
	incoming.stream = synth.call(&"stream_for", definition)
	incoming.volume_db = -40.0
	incoming.play()
	_crossfade(outgoing, incoming)
	_ambience_index = 1 - _ambience_index


func _crossfade(outgoing: AudioStreamPlayer, incoming: AudioStreamPlayer) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	if outgoing.playing:
		tween.tween_property(outgoing, "volume_db", -40.0, 1.2)
	tween.tween_property(incoming, "volume_db", 0.0, 1.2)


func _apply_settings() -> void:
	var config: Node = get_node_or_null(^"/root/Config")
	if config == null or config.get("settings") == null:
		return
	var settings: Resource = config.get("settings")
	var values := {
		&"Master": float(settings.get("master_volume")),
		&"Music": float(settings.get("music_volume")),
		&"SFX": float(settings.get("sfx_volume")),
		&"Ambient": float(settings.get("ambient_volume")),
		&"UI": float(settings.get("ui_volume")),
	}
	for name: StringName in values:
		var index := AudioServer.get_bus_index(name)
		if index < 0:
			continue
		var value: float = clampf(values[name], 0.0, 1.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
		AudioServer.set_bus_mute(index, _paused or bool(settings.get("muted")) or value <= 0.001)


func _on_paused(paused: bool) -> void:
	_paused = paused
	_apply_settings()


# --- EventBus wiring ----------------------------------------------------------


func _wire() -> void:
	var bus := autoload_bus()
	if bus == null:
		return
	for signal_name: StringName in SOUND_FOR_SIGNAL:
		if not bus.has_signal(signal_name):
			Log.warn("Audio", "EventBus has no signal '%s'" % signal_name)
			continue
		var id: StringName = SOUND_FOR_SIGNAL[signal_name]
		bus.connect(signal_name, func(_a = null, _b = null, _c = null) -> void:
			play_sfx(id))
	# Footsteps are one signal with a surface id, so the surface picks the sound.
	bus.connect(&"footstep", func(surface: StringName) -> void:
		play_sfx(StringName("footstep_%s" % surface)))
	# The reaction half of gifting is content, not a separate signal: pick the
	# liked or disliked cue from the same event that already distinguishes them.
	bus.connect(&"npc_gifted", func(_npc: StringName, _item: StringName, reaction: StringName) -> void:
		play_sfx(&"npc_gift_liked" if reaction == NpcData.REACTION_LOVED \
			or reaction == NpcData.REACTION_LIKED else &"npc_gift_disliked"))
	bus.connect(&"weather_changed", func(weather: int) -> void:
		play_ambience(&"rain_loop" if weather == WorldTime.Weather.RAIN \
			or weather == WorldTime.Weather.STORM else &"wind_loop"))
	bus.connect(&"time_hour_changed", func(hour: int) -> void:
		if hour >= 20 or hour < 6:
			play_ambience(&"night_loop"))
