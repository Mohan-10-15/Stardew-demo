class_name FestivalService
extends Node
## Runs one festival at a time, in the physical world.
##
## The service is a listener and a scheduler: it notices the date, tells the
## cast to defer to their gathering day, puts up decorations in the square, and
## pays the player once if they actually turn up. Skipping is the absence of
## that reward, reported as its own event.

const SERVICE_GROUP := &"festival_service"
const SQUARE := Vector2(38.0, 8.0)
const ATTEND_RADIUS := 14.0

var current_id: StringName = &""
var attended: bool = false
var _decorations: Node3D = null
var _last_season: int = -1
var _last_day: int = -1


static func find(start: Node) -> FestivalService:
	if start == null:
		return null
	if start is FestivalService:
		return start as FestivalService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus != null:
		bus.time_minute_changed.connect(_on_minute)
	_check_date()


func _exit_tree() -> void:
	var bus := _bus()
	if bus != null and bus.time_minute_changed.is_connected(_on_minute):
		bus.time_minute_changed.disconnect(_on_minute)


func _on_minute(_minute: int) -> void:
	_check_date()


func _check_date() -> void:
	var clock := TimeService.find_in_tree()
	if clock == null:
		return
	var season := int(clock.time.season)
	var day := int(clock.time.day_of_month)
	if season == _last_season and day == _last_day:
		return
	_last_season = season
	_last_day = day
	var festival := FestivalRegistry.on(season, day)
	if festival != null and festival.id != current_id:
		_start(festival)
	elif festival == null and not current_id.is_empty():
		_end()


func _start(festival: FestivalData) -> void:
	current_id = festival.id
	attended = false
	var manager := _npcs()
	if manager != null:
		manager.set("festival_active", true)
		manager.call("refresh_schedules")
	_build_decorations()
	var bus := _bus()
	if bus != null:
		bus.festival_started.emit(festival.id)
	Log.info("Festival", "%s begins in the square" % festival.display_name)


func _end() -> void:
	var finished := current_id
	if not attended and bus_has(finished):
		var bus := _bus()
		if bus != null:
			bus.festival_skipped.emit(finished)
	var manager := _npcs()
	if manager != null:
		manager.set("festival_active", false)
		manager.call("refresh_schedules")
	if _decorations != null:
		# free(), not queue_free(): the square must be clear the moment the
		# festival ends, including in a test that inspects the tree at once.
		_decorations.free()
		_decorations = null
	current_id = &""
	var bus := _bus()
	if bus != null:
		bus.festival_ended.emit(finished)
	Log.info("Festival", "%s has ended" % finished)


func bus_has(id: StringName) -> bool:
	return not id.is_empty()


func _process(_delta: float) -> void:
	if current_id.is_empty() or attended:
		return
	var player: Node3D = _find_named(get_tree().get_root(), "Player")
	if player == null:
		return
	var flat := Vector2(player.global_position.x, player.global_position.z)
	if flat.distance_to(SQUARE) <= ATTEND_RADIUS:
		_attend()


func _attend() -> void:
	var festival := FestivalRegistry.festival_for(current_id)
	if festival == null:
		return
	attended = true
	var state: Node = _find_named(get_tree().get_root(), "PlayerState")
	if state != null and state.get("wallet") != null:
		var wallet: Object = state.get("wallet")
		wallet.call("set_gold", int(wallet.get("gold")) + festival.reward_gold)
	if state != null and state.get("inventory") != null \
			and not festival.reward_item.is_empty():
		var bag: Object = state.get("inventory")
		bag.call("add", festival.reward_item, 1)
	var manager := _npcs()
	if manager != null and festival.heart_reward > 0:
		manager.call("grant_hearts", &"mira", festival.heart_reward)
	var bus := _bus()
	if bus != null:
		bus.festival_attended.emit(festival.id, festival.reward_gold)
	Log.info("Festival", "Attended %s (+%dg)" % [
		festival.display_name, festival.reward_gold,
	])


## Colourful stalls in the square: the festival is a change to the existing
## world, not a separate scene. Generated from primitives so no new pack is
## needed, and owned by the service so it disappears when the day ends.
func _build_decorations() -> void:
	_decorations = Node3D.new()
	_decorations.name = "FestivalDecor"
	get_tree().get_root().add_child(_decorations)
	var colors := [
		Color(0.90, 0.30, 0.28), Color(0.95, 0.78, 0.22),
		Color(0.28, 0.70, 0.85), Color(0.62, 0.36, 0.86),
	]
	for i: int in range(4):
		var post := MeshInstance3D.new()
		post.name = "Lantern%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.10
		mesh.bottom_radius = 0.10
		mesh.height = 2.4
		post.mesh = mesh
		post.position = Vector3(
			SQUARE.x + cos(float(i) * PI * 0.5) * 6.0, 1.2,
			SQUARE.y + sin(float(i) * PI * 0.5) * 6.0
		)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.emission_enabled = true
		mat.emission = colors[i]
		mat.emission_energy_multiplier = 0.6
		post.material_override = mat
		_decorations.add_child(post)


func to_dict() -> Dictionary:
	return {"current_id": current_id, "attended": attended}


func from_dict(data: Dictionary) -> void:
	current_id = StringName(str(data.get("current_id", &"")))
	attended = bool(data.get("attended", false))


func _npcs() -> Node:
	return _find_named(get_tree().get_root(), "NpcManager")


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
