class_name TutorialStep
extends Resource
## One non-blocking first-day hint. It completes on an existing EventBus
## signal, or on an input action for states that have no signal of their own
## (opening the inventory). Data, written by tools/generate_tutorial_data.gd.

@export var id: StringName = &""
@export var hint: String = ""
@export var completion_signal: StringName = &""
@export var completion_action: StringName = &""
@export var order: int = 0


func is_valid() -> bool:
	return not id.is_empty() and not hint.strip_edges().is_empty() \
		and (not completion_signal.is_empty() or not completion_action.is_empty())
