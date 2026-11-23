class_name CollectionTier
extends Resource
## One milestone in a collection: a fraction complete plus the thing it opens.

@export_range(0.0, 1.0, 0.01) var threshold: float = 0.4
@export var unlock: StringName = &""
@export var ember: StringName = &""


func is_valid() -> bool:
	return threshold > 0.0 and threshold <= 1.0
