class_name ExamineInteractable
extends Interactable
## Generic interactable for anything that can simply be "used" without needing
## bespoke logic: signs, wells, notice boards, lamps, doors.
##
## It exists mainly to prove the component is reusable - it was attached to
## three unrelated world props with nothing but inspector values, no new code
## per prop. Real systems (crops, chests, NPCs, workstations) will subclass
## [Interactable] directly rather than extend this.

## Verb shown before the interaction, e.g. "Look into".
@export var verb: String = "Examine"
## Verb shown after interacting, e.g. "Look into" -> "Read again".
@export var after_verb: String = "Examine again"
## Logged on use. Also surfaced through [signal noticed] for future dialogue.
@export var description: String = "Nothing to report."
## Swaps to [member after_verb] once used.
@export var change_prompt_after_use: bool = true

signal noticed(description: String)


func _ready() -> void:
	super()
	prompt_text = verb
	if one_shot:
		change_prompt_after_use = false


func get_prompt(_actor: Node) -> String:
	if change_prompt_after_use and has_been_used():
		return after_verb
	return verb


func interact(actor: Node) -> bool:
	# `super()` runs the base bookkeeping (availability gate, one-shot latch,
	# `interacted` signal). Calling `interact` here would recurse forever.
	if not super.interact(actor):
		return false
	Log.info("Examine", "%s: %s" % [name, description])
	noticed.emit(description)
	return true