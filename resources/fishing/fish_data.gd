class_name FishData
extends Resource
## One fish and the moment it can be caught, as data.

@export var id: StringName = &""
@export var display_name: String = ""
@export var item_id: StringName = &""
@export var seasons: Array[int] = []
@export var weathers: Array[int] = []
@export var hour_from: int = 0
@export var hour_to: int = 23
@export var wait_min: float = 1.6
@export var wait_max: float = 4.0
@export var bite_window: float = 1.3


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and not item_id.is_empty() and wait_max >= wait_min and bite_window > 0.0
