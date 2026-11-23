class_name CreditEntry
extends Resource
## One row of the in-game credits screen.

@export var label: String = ""
@export var detail: String = ""


func is_valid() -> bool:
	return not label.strip_edges().is_empty() and not detail.strip_edges().is_empty()
