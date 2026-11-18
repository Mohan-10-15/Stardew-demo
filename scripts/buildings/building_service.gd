class_name BuildingService
extends Node
## Buy, place and upgrade farm buildings. The buildings are usable: their
## effects are queried by the animal and farm services through this manager,
## so a placed coop actually changes what the farm produces.

const SERVICE_GROUP := &"building_service"
const SLOT_CENTRES: Array[Vector3] = [
	Vector3(-9, 0, -25), Vector3(13, 0, -25),
	Vector3(-9, 0, -13), Vector3(13, 0, -13),
]

var placed: Array[Dictionary] = []
var _visuals: Node3D = null


static func find(start: Node) -> BuildingService:
	if start == null:
		return null
	if start is BuildingService:
		return start as BuildingService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


static func all_buildings() -> Array[BuildingData]:
	var out: Array[BuildingData] = []
	var dir := DirAccess.open("res://resources/buildings/")
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("res://resources/buildings/%s" % entry) as BuildingData
			if data != null and data.is_valid():
				out.append(data)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: BuildingData, b: BuildingData) -> bool: return String(a.id) < String(b.id))
	return out


func _ready() -> void:
	add_to_group(SERVICE_GROUP)


func definition(id: StringName) -> BuildingData:
	for data: BuildingData in all_buildings():
		if data.id == id:
			return data
	return null


func buy_and_place(id: StringName) -> int:
	var data := definition(id)
	var bus := _bus()
	if data == null:
		if bus != null:
			bus.building_failed.emit(id, &"no_building")
		return -1
	if placed.size() >= SLOT_CENTRES.size():
		if bus != null:
			bus.building_failed.emit(id, &"no_slot")
		return -1
	var wallet := _wallet()
	if wallet == null:
		if bus != null:
			bus.building_failed.emit(id, &"no_player_state")
		return -1
	if int(wallet.get("gold")) < data.price:
		if bus != null:
			bus.building_failed.emit(id, &"poor")
		return -1
	wallet.call("set_gold", int(wallet.get("gold")) - data.price)
	var slot := placed.size()
	placed.append({"building": id, "data": data, "level": 1, "slot": slot})
	_build_visual(data, slot, 1)
	if bus != null:
		bus.building_placed.emit(id, slot)
	return slot


func upgrade(slot: int) -> bool:
	var bus := _bus()
	if slot < 0 or slot >= placed.size():
		if bus != null:
			bus.building_failed.emit(&"", &"no_building")
		return false
	var state: Dictionary = placed[slot]
	var data: BuildingData = state["data"]
	var level := int(state["level"])
	if level >= 2:
		if bus != null:
			bus.building_failed.emit(data.id, &"max_level")
		return false
	var wallet := _wallet()
	if wallet == null or int(wallet.get("gold")) < data.upgrade_price:
		if bus != null:
			bus.building_failed.emit(data.id, &"poor")
		return false
	wallet.call("set_gold", int(wallet.get("gold")) - data.upgrade_price)
	state["level"] = level + 1
	placed[slot] = state
	_build_visual(data, slot, level + 1)
	if bus != null:
		bus.building_upgraded.emit(data.id, slot, level + 1)
	return true


## Sum of one effect kind across all placed buildings. An upgraded building
## contributes twice its base value — that is the real upgrade effect.
func effect(kind: StringName) -> int:
	var total := 0
	for state: Dictionary in placed:
		var data: BuildingData = state["data"]
		if data.effect_kind != kind:
			continue
		total += data.effect_value * int(state["level"])
	return total


func level_of(slot: int) -> int:
	return int(placed[slot].get("level", 1)) if slot >= 0 and slot < placed.size() else 0


func _build_visual(data: BuildingData, slot: int, level: int) -> void:
	if _visuals == null:
		_visuals = Node3D.new()
		_visuals.name = "BuildingVisuals"
		get_tree().get_root().add_child(_visuals)
	var old := _visuals.get_node_or_null(NodePath("Building%d" % slot))
	if old != null:
		old.free()
	var body := MeshInstance3D.new()
	body.name = "Building%d" % slot
	var box := BoxMesh.new()
	box.size = Vector3(3.0 + float(level) * 0.4, 2.0 + float(level) * 0.5, 3.0)
	body.mesh = box
	body.position = SLOT_CENTRES[slot] + Vector3(0, box.size.y * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.tint
	body.material_override = mat
	_visuals.add_child(body)


func to_dict() -> Dictionary:
	var out: Array = []
	for state: Dictionary in placed:
		out.append({"building": state["building"], "level": state["level"]})
	return {"placed": out}


func from_dict(data: Dictionary) -> void:
	placed.clear()
	var saved: Variant = data.get("placed", [])
	if saved is Array:
		for item: Variant in (saved as Array):
			if not item is Dictionary:
				continue
			var id := StringName(str((item as Dictionary).get("building", &"")))
			var data_def := definition(id)
			if data_def == null or placed.size() >= SLOT_CENTRES.size():
				continue
			var slot := placed.size()
			var level := clampi(int((item as Dictionary).get("level", 1)), 1, 2)
			placed.append({"building": id, "data": data_def, "level": level, "slot": slot})
			_build_visual(data_def, slot, level)


func _wallet() -> Object:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	return state.get("wallet") as Object if state != null else null


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
