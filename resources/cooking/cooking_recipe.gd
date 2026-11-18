class_name CookingRecipe
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var ingredients: Dictionary = {}
@export var output_id: StringName = &""


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and not ingredients.is_empty() and not output_id.is_empty()
