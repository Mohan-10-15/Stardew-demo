class_name AmbienceDirector
extends Node
## W6.5: layered ambience. A location/season bed under a weather bed, with
## occasional one-shots. Selection is pure so a test can assert the layers.

signal layers_changed(bed: StringName, weather: StringName)

var context: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _one_shot_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _i: int in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = "AMBIENT"
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	_one_shot_timer = 6.0


func _process(delta: float) -> void:
	_one_shot_timer -= delta
	if _one_shot_timer > 0.0:
		return
	_one_shot_timer = 8.0 + float(int(hash(str(context))) % 7)
	var shot := one_shot_for(context)
	if shot != &"":
		var audio := _audio()
		if audio != null:
			audio.call("play_sfx", shot)


static func bed_for(ctx: Dictionary) -> StringName:
	var location := String(ctx.get("location", "farm"))
	if location.contains("mine"):
		return &"cave_loop"
	if location.contains("pond") or location.contains("beach"):
		return &"pond_loop"
	if location.contains("forest"):
		return &"birds_loop"
	var hour := int(ctx.get("hour", 8))
	if hour >= 20 or hour < 6:
		return &"crickets_loop"
	return &"wind_loop"


static func weather_for(ctx: Dictionary) -> StringName:
	match int(ctx.get("weather", 0)):
		1, 2:
			return &"storm_loop" if int(ctx.get("weather", 0)) == 2 else &"rain_loop"
		3:
			return &"snow_loop"
		_:
			return &""


static func one_shot_for(ctx: Dictionary) -> StringName:
	var bed := bed_for(ctx)
	match bed:
		&"birds_loop":
			return &"bird_chirp"
		&"crickets_loop":
			return &"cricket_chirp"
		&"cave_loop":
			return &"cave_drip"
	return &""


func set_context(next: Dictionary) -> void:
	for key: Variant in next:
		context[key] = next[key]
	var bed := bed_for(context)
	var weather := weather_for(context)
	# One player holds the bed, one holds weather; a change to either swaps that
	# layer without restarting the other.
	_set_layer(0, bed)
	_set_layer(1, weather)
	layers_changed.emit(bed, weather)


func _set_layer(index: int, id: StringName) -> void:
	if index < 0 or index >= _players.size():
		return
	var player := _players[index]
	if id == &"":
		player.stop()
		return
	if player.stream != null and String(player.stream.resource_path).contains(String(id)):
		return
	var definition := AudioRegistry.sound_for(id)
	if definition == null:
		return
	player.stream = AudioSynth.stream_for(definition)
	player.play()


func current_layers() -> Array[StringName]:
	var out: Array[StringName] = []
	for player: AudioStreamPlayer in _players:
		out.append(&"" if player.stream == null else StringName(
			String(player.stream.resource_path).get_file().get_basename()))
	return out


func _audio() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"AudioManager")


static func find(start: Node) -> AmbienceDirector:
	if start == null:
		return null
	if start is AmbienceDirector:
		return start as AmbienceDirector
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null
