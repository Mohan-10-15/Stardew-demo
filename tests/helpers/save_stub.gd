extends Node
## Minimal SaveService stand-in for title-menu tests: the title only asks one
## question, so the stub owns one answer.

var has_save_value: bool = false


func has_save() -> bool:
	return has_save_value
