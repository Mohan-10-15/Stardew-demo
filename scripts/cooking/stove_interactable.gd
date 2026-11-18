extends Interactable
## The farmhouse stove: E cooks the first dish the bag can currently make.
## It is the physical station that makes cooking more than a global menu.

func _ready() -> void:
	super()
	prompt_text = "Cook at the stove"
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
	var service := CookingService.find((loop as SceneTree).root)
	if service == null:
		return false
	for recipe: CookingRecipe in CookingService.all_recipes():
		if service.can_cook(recipe.id) == &"":
			return service.cook(recipe.id)
	var bus := (loop as SceneTree).root.get_node_or_null(^"EventBus")
	if bus != null:
		bus.cook_failed.emit(&"", &"missing_ingredients")
	return false
