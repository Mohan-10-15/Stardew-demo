extends Node
## Minimal FarmService stand-in for the save fixture: the real one needs the
## generated world, and the aggregate save only asks it for its grid's state.

var grid: Node = null


func to_dict() -> Dictionary:
	return {"stub": true}


func from_dict(_data: Dictionary) -> void:
	pass
