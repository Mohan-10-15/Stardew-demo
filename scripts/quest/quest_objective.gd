class_name QuestObjective
extends Resource
## What one quest is actually asking for: bring five parsnips, hand something to Halda,
## or go and speak to Bram.
##
## ## Why this is a resource and not a string
##
## The three objective kinds are different *questions*, not three flavours of one. `collect`
## asks what has come into the bag since the player agreed to the job, `deliver` asks what
## the bag holds right now and who is standing in front of them, and `talk` asks nothing
## about items at all. An earlier cut of this was a `kind` string plus a bag of loosely-typed
## fields, which meant "is this quest done?" was answered by a `match` in the service with
## three arms that had to agree with each other about what counted. Here the predicate is
## [method is_satisfied_by] and it is the only place the question is asked.
##
## ## Why `collect` counts what was gathered and not what is held
##
## Both, and the difference is the whole reason [method is_satisfied_by] takes two
## arguments. Counting only what the bag holds means a player who already had twenty parsnips
## when they accepted the job completes it by saying yes, which is not doing the objective.
## Counting only what was gathered means a player who harvests five parsnips and then eats
## them completes it having delivered nothing, which is worse. So progress is the running
## total of what arrived since acceptance, and the bag is checked again at the counter.
const KIND_COLLECT := &"collect"
const KIND_DELIVER := &"deliver"
const KIND_TALK := &"talk"

## Every kind, for a content test that asserts the vocabulary is closed. A new arm in
## [method is_satisfied_by] or [method describe] without an entry here fails it.
const KINDS: Array[StringName] = [KIND_COLLECT, KIND_DELIVER, KIND_TALK]

@export var kind: StringName = &""
## The item being gathered or carried. Empty for [constant KIND_TALK], which has no item.
@export var item_id: StringName = &""
## How many of it. Always at least one; "bring some" is not a number an author can mean.
@export_range(1, 999, 1) var count: int = 1
## Who has to be spoken to, or handed to. Empty for [constant KIND_COLLECT], where the
## giver is the one who takes the delivery — spelled out rather than defaulted, because a
## `collect` quest that quietly also names a target is two quests in one field.
@export var target_npc: StringName = &""


## Whether this objective is satisfied.
##
## [param progress] is the running state of the quest and [param held] is how many of
## [member item_id] the player is carrying at this instant. Both are needed, for the reason
## in the class comment.
##
## This is the only definition of "done" in the project. [QuestService] asks it and the
## tests ask it directly, so a quest that can be handed in without its objective being met
## is a bug in one function rather than a disagreement between three.
func is_satisfied_by(progress: QuestProgress, held: int) -> bool:
	if progress == null:
		return false
	match kind:
		KIND_COLLECT:
			return progress.collected >= count and held >= count
		KIND_DELIVER:
			return progress.spoke_to_target and held >= count
		KIND_TALK:
			return progress.spoke_to_target
	return false


## Whether this objective has been started but is not yet finished.
##
## Drives the "2 of 5" line. Separate from [method is_satisfied_by] rather than derived by
## negation, because a quest the player cannot begin — one whose item does not exist, or a
## `talk` to somebody who is not in the valley — should read as "0 of 1" rather than as a
## negative number.
func current_amount(progress: QuestProgress) -> int:
	if progress == null:
		return 0
	match kind:
		KIND_COLLECT:
			return mini(progress.collected, count)
		KIND_DELIVER:
			# The conversation is half of it, so a delivery reads 0 of 1 until the target
			# has been spoken to even if the item is already in the bag.
			return 1 if progress.spoke_to_target else 0
		KIND_TALK:
			return 1 if progress.spoke_to_target else 0
	return 0


## How many are needed. One number for every kind, so a journal does not switch on the kind
## to decide which column to draw.
func required_amount() -> int:
	return 1 if kind == KIND_TALK else maxi(count, 1)


## Whether the objective carries an item at all, which decides whether the service has to
## look in the bag before it can answer "is this done?".
func needs_an_item() -> bool:
	return kind == KIND_COLLECT or kind == KIND_DELIVER


## Whether the objective is finished by speaking to somebody.
##
## The service uses this to decide whether hearing [signal EventBus.npc_talked] is progress
## or completion, and it is asked as a question here so the three kinds stay in one place.
func is_completed_by_talking() -> bool:
	return kind == KIND_TALK or kind == KIND_DELIVER


## Whether somebody has to be spoken to for this objective, and who.
func target() -> StringName:
	return target_npc


## One line for a prompt or a journal entry, in the voice of the quest rather than the
## schema's field names.
##
## [param giver_name] is the villager who asked, because "to the giver" is a schema word
## and a journal row has nowhere else to say who to go back to. Left empty it still reads
## as prose, which is what an [InteractionPrompt] wants: the prompt is drawn next to the
## villager being talked to, so naming them there is noise.
##
## The delivery and talk targets are resolved through [NpcRegistry] rather than printed
## raw. `Speak to halda` is a database key on the player's screen.
func describe(item_name: String = "", giver_name: String = "") -> String:
	var who: String = giver_name if not giver_name.is_empty() else "the giver"
	var unit: String = "one" if count == 1 else "%d" % count
	match kind:
		KIND_COLLECT:
			return "Bring %s %s to %s" % [unit, _noun(item_name), who]
		KIND_DELIVER:
			return "Deliver %s %s to %s" % [unit, _noun(item_name), _target_name()]
		KIND_TALK:
			return "Speak to %s" % _target_name()
	return "Nothing to do"


## The noun for [param count] of the wanted item, resolving across both registries.
##
## Pluralisation is the item's business, not this lane's. Guessing here is what put
## "Bring 20 Woods to Fen" on the tracker — the quest id was right, the count was right,
## and every automated check passed, because nothing was reading the prose. The registry
## resolves crops and materials alike, so [code]describe[/code] does not care which kind it
## is asking for.
func _noun(item_name: String) -> String:
	var known := QuestReward.name_of(item_id, count)
	if not String(item_id).is_empty() and known != String(item_id):
		return known
	return item_name if not item_name.is_empty() else String(item_id)


## The target's display name, or the raw id when the villager is not in the registry.
func _target_name() -> String:
	var npc := NpcRegistry.get_npc(target_npc)
	return npc.display_name if npc != null else String(target_npc)


## Whether this objective is authored completely enough to be asked.
##
## The per-kind checks are deliberately fussy. A `collect` that names a target is rejected
## rather than quietly treated as a `deliver`, because that is the kind of authoring mistake
## that otherwise shows up as a quest the player can complete in two places.
func is_valid() -> bool:
	if not KINDS.has(kind):
		return false
	if count < 1:
		return false
	match kind:
		KIND_COLLECT:
			return not item_id.is_empty() and target_npc.is_empty()
		KIND_DELIVER:
			return not item_id.is_empty() and not target_npc.is_empty()
		KIND_TALK:
			return item_id.is_empty() and not target_npc.is_empty()
	return false