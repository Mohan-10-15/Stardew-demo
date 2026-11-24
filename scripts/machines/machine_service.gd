class_name MachineService
extends Node
## Placeable machines on fixed farm pads. Buy, place, load, wait a day, collect.
## The pads are content positions rather than free-form placement: a machine
## that can be dropped anywhere can be dropped inside a wall.

const SERVICE_GROUP := &"machine_service"
const DIR := "res://resources/machines/"
const PADS: Array[Vector3] = [
	Vector3(-5, 0, -25), Vector3(2, 0, -25), Vector3(9, 0, -25),
	Vector3(-5, 0, -17), Vector3(2, 0, -17), Vector3(9, 0, -17),
]

## Each placement: {machine, data, input, days_left, output}
var placed: Array[Dictionary] = []
var _visuals: Node3D = null


static func find(start: Node) -> MachineService:
	if start == null:
		return null
	if start is MachineService:
		return start as MachineService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


static func all_machines() -> Array[MachineData]:
	var out: Array[MachineData] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if ResourceFiles.is_resource(entry):
			var data := ResourceLoader.load(ResourceFiles.path_for(DIR, entry)) as MachineData
			if data != null and data.is_valid():
				out.append(data)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: MachineData, b: MachineData) -> bool: return String(a.id) < String(b.id))
	return out


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus != null:
		bus.day_started.connect(_on_day_started)


func _exit_tree() -> void:
	var bus := _bus()
	if bus != null and bus.day_started.is_connected(_on_day_started):
		bus.day_started.disconnect(_on_day_started)


func place(machine_id: StringName) -> int:
	var data := _definition(machine_id)
	var bus := _bus()
	if data == null:
		if bus != null:
			bus.machine_load_failed.emit(machine_id, -1, &"no_machine")
		return -1
	var slot := placed.size()
	if slot >= PADS.size():
		if bus != null:
			bus.machine_load_failed.emit(machine_id, -1, &"no_free_pad")
		return -1
	placed.append({
		"machine": machine_id, "data": data, "input": &"",
		"days_left": 0, "output": 0, "slot": slot,
	})
	_build_visual(data, slot)
	if bus != null:
		bus.machine_placed.emit(machine_id, slot)
	return slot


func load_input(slot: int, item_id: StringName) -> bool:
	var bus := _bus()
	if slot < 0 or slot >= placed.size():
		if bus != null:
			bus.machine_load_failed.emit(&"", slot, &"no_machine")
		return false
	var state: Dictionary = placed[slot]
	var data: MachineData = state["data"]
	if not bool(state["input"] == &""):
		if bus != null:
			bus.machine_load_failed.emit(data.id, slot, &"already_loaded")
		return false
	if item_id != data.input_id:
		if bus != null:
			bus.machine_load_failed.emit(data.id, slot, &"wrong_input")
		return false
	var bag := _bag()
	if bag == null or int(bag.call("count", item_id)) <= 0:
		if bus != null:
			bus.machine_load_failed.emit(data.id, slot, &"no_input_item")
		return false
	bag.call("remove", item_id, 1)
	state["input"] = item_id
	state["days_left"] = data.process_days
	placed[slot] = state
	if bus != null:
		bus.machine_loaded.emit(data.id, slot, item_id)
	return true


func load_from_bag(slot: int) -> bool:
	if slot < 0 or slot >= placed.size():
		return false
	var data: MachineData = placed[slot]["data"]
	return load_input(slot, data.input_id)


func collect(slot: int) -> bool:
	var bus := _bus()
	if slot < 0 or slot >= placed.size():
		if bus != null:
			bus.machine_collect_failed.emit(&"", slot, &"no_machine")
		return false
	var state: Dictionary = placed[slot]
	var data: MachineData = state["data"]
	var ready := int(state["output"])
	if ready <= 0:
		if bus != null:
			bus.machine_collect_failed.emit(data.id, slot, &"not_ready")
		return false
	var bag := _bag()
	if bag == null:
		if bus != null:
			bus.machine_collect_failed.emit(data.id, slot, &"no_player_state")
		return false
	bag.call("add", data.output_id, ready)
	state["output"] = 0
	state["input"] = &""
	placed[slot] = state
	if bus != null:
		bus.machine_collected.emit(data.id, slot, data.output_id, ready)
	return true


func _on_day_started(_day: int) -> void:
	for i: int in range(placed.size()):
		var state: Dictionary = placed[i]
		if String(state["input"]).is_empty():
			continue
		var left := int(state["days_left"]) - 1
		if left <= 0:
			var data: MachineData = state["data"]
			state["output"] = int(state["output"]) + data.output_amount
			state["days_left"] = 0
		else:
			state["days_left"] = left
		placed[i] = state


func _definition(id: StringName) -> MachineData:
	for data: MachineData in all_machines():
		if data.id == id:
			return data
	return null


func _build_visual(data: MachineData, slot: int) -> void:
	if _visuals == null:
		_visuals = Node3D.new()
		_visuals.name = "MachineVisuals"
		get_tree().get_root().add_child(_visuals)
	var old := _visuals.get_node_or_null(NodePath("Machine%d" % slot))
	if old != null:
		old.free()
	var body := StaticBody3D.new()
	body.name = "Machine%d" % slot
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	body.position = PADS[slot]

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 1.0, 1.1)
	shell.mesh = box
	shell.position = Vector3(0, 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.tint
	shell.material_override = mat
	body.add_child(shell)

	# A chimney, a hopper and a hatch: composed geometry reads as a machine
	# rather than the single placeholder cube it replaced.
	var chimney := MeshInstance3D.new()
	chimney.name = "Chimney"
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.16
	pipe.bottom_radius = 0.22
	pipe.height = 0.75
	pipe.radial_segments = 10
	chimney.mesh = pipe
	chimney.position = Vector3(0.38, 1.28, -0.25)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.30, 0.28, 0.26)
	chimney.material_override = metal
	body.add_child(chimney)

	var hopper := MeshInstance3D.new()
	hopper.name = "Hopper"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.36
	cone.bottom_radius = 0.12
	cone.height = 0.5
	cone.radial_segments = 8
	hopper.mesh = cone
	hopper.position = Vector3(-0.34, 1.24, 0.1)
	hopper.material_override = metal
	body.add_child(hopper)

	var hatch := MeshInstance3D.new()
	hatch.name = "Hatch"
	var door := BoxMesh.new()
	door.size = Vector3(0.5, 0.42, 0.06)
	hatch.mesh = door
	hatch.position = Vector3(0, 0.52, 0.58)
	var hatch_mat := StandardMaterial3D.new()
	hatch_mat.albedo_color = data.tint.darkened(0.45)
	hatch.material_override = hatch_mat
	body.add_child(hatch)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var col := BoxShape3D.new()
	col.size = Vector3(1.3, 1.0, 1.1)
	shape.shape = col
	shape.position = Vector3(0, 0.5, 0)
	body.add_child(shape)
	var component := Node.new()
	component.name = "Interactable"
	component.set_script(load("res://scripts/machines/machine_interactable.gd"))
	component.call("setup", slot)
	body.add_child(component)
	_visuals.add_child(body)


func to_dict() -> Dictionary:
	var out: Array = []
	for state: Dictionary in placed:
		out.append({
			"machine": state["machine"], "input": state["input"],
			"days_left": state["days_left"], "output": state["output"],
		})
	return {"placed": out}


func from_dict(data: Dictionary) -> void:
	placed.clear()
	var saved: Variant = data.get("placed", [])
	if saved is Array:
		for item: Variant in (saved as Array):
			if not item is Dictionary:
				continue
			var entry: Dictionary = item
			var id := StringName(str(entry.get("machine", &"")))
			var definition := _definition(id)
			if definition == null:
				continue
			var slot := placed.size()
			if slot >= PADS.size():
				break
			placed.append({
				"machine": id, "data": definition,
				"input": StringName(str(entry.get("input", &""))),
				"days_left": int(entry.get("days_left", 0)),
				"output": int(entry.get("output", 0)), "slot": slot,
			})
			_build_visual(definition, slot)


func _bag() -> Object:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	return state.get("inventory") as Object if state != null else null


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
