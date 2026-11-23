class_name MusicDirector
extends Node
## W6.2: finally wires music into gameplay. One hub, no gameplay service calls
## into it — the world publishes state through EventBus and this node chooses a
## cue by priority, crossfades, ducks under dialogue and rests between phrases.

const DIR := "res://resources/audio/cues/"
const BUS := "Music"
const DUCK_DB := -6.0

signal cue_changed(cue_id: StringName)

var cues: Dictionary = {}
var context: Dictionary = {}
var current_id: StringName = &""
var history: Array[StringName] = []
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _played_for: float = 0.0
var _resting_for: float = 0.0
var _ducked := false
var _rest_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cues()
	_ensure_bus()
	for _i: int in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


func _load_cues() -> void:
	cues.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var cue := ResourceLoader.load(DIR + entry) as MusicCue
			if cue != null and cue.is_valid():
				cues[cue.id] = cue


func _ensure_bus() -> void:
	for i: int in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == BUS:
			return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, BUS)
	AudioServer.set_bus_send(AudioServer.get_bus_count() - 1, "Master")


func _process(delta: float) -> void:
	if current_id == &"":
		return
	_played_for += delta
	var cue: MusicCue = cues.get(current_id)
	if cue == null:
		return
	if _rest_enabled and _played_for >= cue.min_play_seconds:
		_resting_for += delta
		if _resting_for >= cue.rest_seconds:
			_resting_for = 0.0
			_played_for = 0.0
			_fade_out(0.6)
			current_id = &""
			cue_changed.emit(&"")


## Accepts a partial context dictionary; missing keys keep their last value.
func set_context(next: Dictionary) -> void:
	for key: Variant in next:
		context[key] = next[key]
	var winner := _select()
	if winner == &"" or winner == current_id:
		return
	_switch(winner)


func _select() -> StringName:
	# Highest priority first; ties broken by the most specific tag match.
	if bool(context.get("menu", false)):
		return _first_with_tag(&"menu")
	if bool(context.get("cutscene", false)):
		return _first_with_tag(&"cutscene")
	if bool(context.get("story", false)):
		return &"mending"
	if bool(context.get("combat", false)):
		return &"combat"
	if bool(context.get("festival", false)):
		return &"festival"
	var location := String(context.get("location", ""))
	if location.contains("mine"):
		return &"deep_mines" if bool(context.get("deep", false)) else &"upper_mines"
	if location.contains("pond"):
		return &"pond"
	if location.contains("forest"):
		return &"forest_edge"
	if location.contains("village"):
		return &"village_night" if bool(context.get("night", false)) else &"village_day"
	var season := String(context.get("season", "spring"))
	if bool(context.get("night", false)):
		return &"farm_night"
	return StringName("farm_%s" % season) if cues.has(StringName("farm_%s" % season)) else &"title"


func _first_with_tag(tag: StringName) -> StringName:
	var best: StringName = &""
	var best_priority := -1
	for id: StringName in cues:
		var cue: MusicCue = cues[id]
		if cue.tags.has(tag) and cue.priority > best_priority:
			best = id
			best_priority = cue.priority
	return best


func _switch(id: StringName) -> void:
	var cue: MusicCue = cues.get(id)
	if cue == null:
		return
	var stream := MusicSynth.stream_for(cue.score)
	if stream == null:
		return
	var incoming_index := 1 - _active
	var incoming := _players[incoming_index]
	var outgoing := _players[_active]
	incoming.stream = stream
	incoming.play()
	_fade(incoming, 0.0, cue.fade_seconds)
	_fade(outgoing, -80.0, cue.fade_seconds)
	# There are exactly two players, so an old loop at -80 dB is a bounded cost;
	# stopping it from a timer callback would capture a node that a test teardown
	# may free first (lambda capture errors at exit).
	_active = incoming_index
	current_id = id
	_played_for = 0.0
	_resting_for = 0.0
	history.append(id)
	cue_changed.emit(id)


func _fade(player: AudioStreamPlayer, target_db: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, maxf(seconds, 0.05))


func _fade_out(seconds: float) -> void:
	_fade(_players[_active], -80.0, seconds)


func duck(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	var target := BUS
	var index := -1
	for i: int in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == target:
			index = i
	if index < 0:
		return
	# Duck the music bus itself relative to its normal gain.
	var db := DUCK_DB if on else 0.0
	AudioServer.set_bus_volume_db(index, db)


static func find(start: Node) -> MusicDirector:
	if start == null:
		return null
	if start is MusicDirector:
		return start as MusicDirector
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null
