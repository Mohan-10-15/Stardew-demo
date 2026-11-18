extends Interactable
## One E at the coop collects a product if one is waiting, otherwise it feeds
## the animals. The service decides which; this component only asks.

func _ready() -> void:
	super()
	prompt_text = "Tend the coop"
	max_distance = 3.5


func get_aim_point() -> Vector3:
	var body := get_parent()
	if body is Node3D:
		return (body as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	return super()


func interact(_actor: Node) -> bool:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	var service := AnimalService.find((loop as SceneTree).root)
	if service == null:
		return false
	if service.stored_of(&"hen") > 0 or service.stored_of(&"goat") > 0:
		if service.stored_of(&"hen") > 0:
			service.collect(&"hen")
		else:
			service.collect(&"goat")
	else:
		service.feed(&"hen")
		service.feed(&"goat")
	interacted.emit(_actor)
	return true
