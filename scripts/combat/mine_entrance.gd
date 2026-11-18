extends Interactable
## The mine door. Its only job is to turn a normal E press into the one
## `mine_entered` event the combat manager listens to.

const MINE_PROMPT := "Enter the old mine"


func _ready() -> void:
	super()
	prompt_text = MINE_PROMPT
	one_shot = false
	max_distance = 3.5


func get_aim_point() -> Vector3:
	var body := get_parent()
	if body is Node3D:
		return (body as Node3D).global_position + Vector3(0.0, 1.2, 0.0)
	return super()


func interact(_actor: Node) -> bool:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var bus := (loop as SceneTree).root.get_node_or_null(^"EventBus")
		if bus != null:
			bus.emit_signal(&"mine_entered")
	interacted.emit(_actor)
	return true
