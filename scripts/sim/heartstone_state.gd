class_name HeartstoneState
extends RefCounted
## Pure logic for the six-Ember progression. No scene dependency, so a
## --script test can exercise it directly. Embers are never removed: a save
## with all six is the entry condition for The Mending.

const EMBERS: Array[StringName] = [
	&"fields", &"waters", &"stone", &"table", &"wilds", &"hearts",
]

var embers: Dictionary = {}


func _init() -> void:
	clear()


func clear() -> void:
	embers.clear()
	for ember: StringName in EMBERS:
		embers[ember] = false


func has_ember(ember: StringName) -> bool:
	return bool(embers.get(ember, false))


func add_ember(ember: StringName) -> bool:
	if not EMBERS.has(ember) or has_ember(ember):
		return false
	embers[ember] = true
	return true


func count() -> int:
	var n := 0
	for ember: StringName in EMBERS:
		if has_ember(ember):
			n += 1
	return n


func can_mend() -> bool:
	return count() == EMBERS.size()


func to_dict() -> Dictionary:
	return embers.duplicate()


func from_dict(data: Dictionary) -> void:
	clear()
	for ember: StringName in EMBERS:
		embers[ember] = bool(data.get(String(ember), false))
