extends Interactable
## A placed machine: E loads the input if empty, otherwise collects the output.

var slot: int = -1


func setup(index: int) -> void:
	slot = index
	prompt_text = "Use the machine"


func get_aim_point() -> Vector3:
	var body := get_parent()
	if body is Node3D:
		return (body as Node3D).global_position + Vector3(0, 0.8, 0)
	return super()


func interact(_actor: Node) -> bool:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	var service := MachineService.find((loop as SceneTree).root)
	if service == null:
		return false
	var state: Dictionary = service.placed[slot]
	if int(state["output"]) > 0:
		service.collect(slot)
	else:
		service.load_from_bag(slot)
	interacted.emit(_actor)
	return true
