class_name FishingService
extends Node
## The fishing loop: cast, wait for a bite, land the fish inside the window.
## Four distinct events, four distinct sounds. No timer runs while the game is
## paused, and the service owns no item logic beyond asking the bag to add one.

const SERVICE_GROUP := &"fishing_service"
const DIR := "res://resources/fishing/fish/"
enum State { IDLE, WAITING, BITE }

var state: State = State.IDLE
var current_fish: FishData = null
var wait_left: float = 0.0
var bite_left: float = 0.0
var _rng := RandomNumberGenerator.new()


static func find(start: Node) -> FishingService:
	if start == null:
		return null
	if start is FishingService:
		return start as FishingService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()


func _process(delta: float) -> void:
	if state == State.WAITING:
		wait_left -= delta
		if wait_left <= 0.0:
			_to_bite()
	elif state == State.BITE:
		bite_left -= delta
		if bite_left <= 0.0:
			_escape(&"missed_the_bite")
	if state != State.IDLE and Input.is_action_just_pressed(InputActions.INTERACT):
		if state == State.BITE:
			land()
		else:
			_escape(&"reeled_in_early")


func cast() -> bool:
	if state != State.IDLE:
		return false
	current_fish = _pick_fish()
	if current_fish == null:
		return false
	state = State.WAITING
	wait_left = _rng.randf_range(current_fish.wait_min, current_fish.wait_max)
	var bus := _bus()
	if bus != null:
		bus.fishing_cast.emit()
		var state_service := _find_named(get_tree().get_root(), "PlayerState")
		if state_service != null:
			var held: Dictionary = state_service.call("held_item_id")
			bus.tool_swung.emit(StringName(held.get("id", &"")))
	return true


func _to_bite() -> void:
	state = State.BITE
	bite_left = current_fish.bite_window
	var bus := _bus()
	if bus != null:
		bus.fish_bite.emit(current_fish.id)


func land() -> bool:
	if state != State.BITE or current_fish == null:
		return false
	var fish := current_fish
	state = State.IDLE
	current_fish = null
	var state_service := _find_named(get_tree().get_root(), "PlayerState")
	if state_service != null and state_service.get("inventory") != null:
		var bag: Object = state_service.get("inventory")
		bag.call("add", fish.item_id, 1)
	var bus := _bus()
	if bus != null:
		bus.fish_caught.emit(fish.id, fish.item_id)
	return true


func _escape(reason: StringName) -> void:
	var fish := current_fish
	state = State.IDLE
	current_fish = null
	var bus := _bus()
	if bus != null and fish != null:
		bus.fish_escaped.emit(fish.id, reason)


func _pick_fish() -> FishData:
	var clock := TimeService.find_in_tree()
	var season := 0
	var weather := 0
	var hour := 12
	if clock != null:
		season = int(clock.time.season)
		weather = int(clock.get_weather())
		hour = int(clock.time.hour)
	var pool: Array[FishData] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if ResourceFiles.is_resource(entry):
			var data := ResourceLoader.load(ResourceFiles.path_for(DIR, entry)) as FishData
			if data != null and data.is_valid() and data.seasons.has(season) \
					and data.weathers.has(weather) and _hour_matches(data, hour):
				pool.append(data)
		entry = dir.get_next()
	dir.list_dir_end()
	if pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _hour_matches(fish: FishData, hour: int) -> bool:
	if fish.hour_from <= fish.hour_to:
		return hour >= fish.hour_from and hour <= fish.hour_to
	return hour >= fish.hour_from or hour <= fish.hour_to


func to_dict() -> Dictionary:
	return {"state": int(state), "fish": current_fish.id if current_fish != null else &"",
		"wait_left": wait_left, "bite_left": bite_left}


func from_dict(data: Dictionary) -> void:
	state = int(data.get("state", State.IDLE)) as State
	current_fish = _load_fish(StringName(str(data.get("fish", &""))))
	wait_left = float(data.get("wait_left", 0.0))
	bite_left = float(data.get("bite_left", 0.0))


func _load_fish(id: StringName) -> FishData:
	if id.is_empty():
		return null
	return ResourceLoader.load("%s%s.tres" % [DIR, id]) as FishData


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
