class_name BuildingData
extends Resource
## A placeable farm building with one concrete effect and an upgrade path.

@export var id: StringName = &""
@export var display_name: String = ""
@export var price: int = 0
@export var upgrade_price: int = 0
@export var effect_kind: StringName = &"product"
## Base strength of the effect; an upgrade doubles it.
@export var effect_value: int = 1
@export var tint: Color = Color.WHITE


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and price > 0 \
		and upgrade_price > 0 and effect_value > 0
