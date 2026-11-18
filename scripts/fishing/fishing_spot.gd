extends Interactable
## The pond shore: E casts a line. Landing the fish reuses the same key while
## the FishingService is waiting for a bite.

func _ready() -> void:
	super()
	prompt_text = "Cast a line into the pond"
	max_distance = 4.0


func get_aim_point() -> Vector3:
	var body := get_parent()
	if body is Node3D:
		return (body as Node3D).global_position + Vector3(0.0, 0.8, 0.0)
	return super()


func interact(_actor: Node) -> bool:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var service := FishingService.find((loop as SceneTree).root)
		if service != null and not bool(service.call("cast")):
			return false
	interacted.emit(_actor)
	return true
