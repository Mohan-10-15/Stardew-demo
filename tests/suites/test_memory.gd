extends TestSuite
## W2.6: the valley remembers real events, never invented ones, and the
## Mending can recite only deeds that actually happened.

var _memory: ValleyMemory = null


func get_cases() -> Array[StringName]:
	return [&"the_ledger_has_real_deeds", &"a_real_event_is_remembered",
		&"recitation_limits_to_seven_real_deeds", &"memory_survives_a_save"]


func setup() -> void:
	_memory = null


func teardown() -> void:
	if _memory != null and is_instance_valid(_memory):
		_memory.free()
	_memory = null


func _run(case: StringName) -> Dictionary:
	match case:
		&"the_ledger_has_real_deeds":
			if ValleyMemory.DEEDS.size() < 25:
				return fail(case, "only %d deeds" % ValleyMemory.DEEDS.size())
			return succeeded(case, "%d remembered deeds" % ValleyMemory.DEEDS.size())
		&"a_real_event_is_remembered":
			_memory = ValleyMemory.new()
			root().add_child(_memory)
			autoload(&"EventBus").emit_signal(&"crop_harvested", Vector2i.ZERO, &"parsnip", 1)
			if not _memory.has(&"first_harvest"):
				return fail(case, "a harvest was not remembered")
			return succeeded(case, "first harvest entered the ledger")
		&"recitation_limits_to_seven_real_deeds":
			_memory = ValleyMemory.new()
			root().add_child(_memory)
			for deed: StringName in ValleyMemory.DEEDS:
				_memory.remember(deed)
			var recited := _memory.recite()
			if recited.size() != 7 or recited.has(&""):
				return fail(case, "recited %d deeds" % recited.size())
			return succeeded(case, "seven real deeds recited")
		&"memory_survives_a_save":
			_memory = ValleyMemory.new()
			root().add_child(_memory)
			_memory.remember(&"first_festival")
			var data: Dictionary = _memory.call("to_dict")
			var fresh := ValleyMemory.new()
			root().add_child(fresh)
			fresh.call("from_dict", data)
			if not fresh.has(&"first_festival"):
				return fail(case, "memory did not round-trip")
			return succeeded(case, "a remembered deed survived a save")
	return fail(case, "no case implementation for %s" % case)
