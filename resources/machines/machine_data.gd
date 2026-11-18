class_name MachineData
extends Resource
## One placeable machine: what it takes in, what it makes, and how long it runs.

@export var id: StringName = &""
@export var display_name: String = ""
@export var input_id: StringName = &""
@export var output_id: StringName = &""
@export var output_amount: int = 1
@export var process_days: int = 1
@export var price: int = 0
@export var tint: Color = Color.WHITE


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and not input_id.is_empty() and not output_id.is_empty() \
		and output_amount > 0 and process_days >= 1
