class_name AnimalData
extends Resource
## One farm animal, as data: what it eats and what it gives when fed.

@export var id: StringName = &""
@export var display_name: String = ""
@export var feed_item: StringName = &""
@export var product_item: StringName = &""
@export var product_amount: int = 1
@export var days_to_product: int = 1
@export var tint: Color = Color.WHITE


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and not feed_item.is_empty() and not product_item.is_empty() \
		and product_amount > 0 and days_to_product >= 1
