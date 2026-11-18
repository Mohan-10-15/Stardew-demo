class_name Recipe
extends Resource
## A recipe: ingredient ids and counts in, one item stack out. Data, never a
## branch in a service.

@export var id: StringName = &""
@export var display_name: String = ""
@export var ingredients: Dictionary = {}
@export var output_id: StringName = &""
@export var output_count: int = 1
@export var description: String = ""


func is_valid() -> bool:
	if id.is_empty() or display_name.is_empty() or output_id.is_empty() \
			or output_count <= 0 or ingredients.is_empty():
		return false
	for key: Variant in ingredients:
		if StringName(str(key)).is_empty() or int(ingredients[key]) <= 0:
			return false
	return true
