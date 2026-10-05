class_name QuestProgress
extends Resource
## How far one quest has got, and how many times it has been handed in.
##
## Split from [QuestData] on purpose. [QuestData] is authored content and is shared by
## every player who loads the save; this is the one player's mutable answer to it, and a
## `QuestData` that quietly held "3 of 5 parsnips" would be content that changes when you
## play it. [Friendship] makes the same split for the same reason.
##
## [method to_dict] and [method from_dict] are here rather than in [QuestService] because
## every other persisted thing in the project serialises itself: [method FarmGrid.to_dict]
## writes its own version, [method Friendship.to_dict] writes its own. A save loader that
## had to reach into another object's fields to save it is a save loader that breaks the
## moment the field is renamed.

## In hand, not yet handed in.
const STATE_ACTIVE := &"active"
## Finished and paid. Kept rather than deleted so the journal can still say so and so a
## `once` quest stays completed across a reload.
const STATE_TURNED_IN := &"turned_in"

## Every state, for a content test that asserts the vocabulary is closed.
const STATES: Array[StringName] = [STATE_ACTIVE, STATE_TURNED_IN]

## How many days must pass before a `weekly` quest is offered again.
const WEEKLY_INTERVAL_DAYS := 7

@export var quest_id: StringName = &""
@export var state: StringName = STATE_ACTIVE
## Running total of items that came into the bag since the quest was accepted, clamped by
## the objective when read. Not the bag's current contents — see [QuestObjective].
@export var collected: int = 0
## Whether the player has already spoken to the objective's target.
@export var spoke_to_target: bool = false
## How many times this quest has been handed in. Weekly quests use it to keep a streak.
@export var turn_ins: int = 0
## Days since the last hand-in. Reset to -1 when never handed in, so a fresh quest does not
## inherit a save that happened to have a nonzero counter.
@export var days_since_turn_in: int = -1


static func create(p_quest_id: StringName) -> QuestProgress:
	var progress := QuestProgress.new()
	progress.quest_id = p_quest_id
	return progress


func is_active() -> bool:
	return state == STATE_ACTIVE


func is_turned_in() -> bool:
	return state == STATE_TURNED_IN


## Whether this quest is currently on offer, as opposed to in hand or on cooldown.
##
## "On offer" and "accepted" are different questions and this answers only the first, so
## the service can report "you already have this" separately from "come back next week".
## That distinction is the difference between two legible refusals and one confusing one.
##
## [param repeats] is the content's [member QuestData.repeats], passed in rather than read
## from a registry, so this is answerable for a quest that is not loaded — which is the
## state a save loader cares about.
##
## Counted on [member turn_ins] rather than [member state] because those two are not the
## same question: a quest the player is halfway through is [constant STATE_ACTIVE], and a
## quest they finished an hour ago is [constant STATE_TURNED_IN], and neither is the one
## being asked about here.
func can_be_offered(repeats: StringName) -> bool:
	if turn_ins <= 0:
		return true
	if repeats == QuestData.REPEATS_WEEKLY:
		return days_since_turn_in >= WEEKLY_INTERVAL_DAYS
	return false


## Records one item arriving, so progress survives the player spending what they gathered.
func note_item_added(amount: int) -> void:
	collected = maxi(collected, 0) + maxi(amount, 0)


func note_turned_in(day: int = 0) -> void:
	state = STATE_TURNED_IN
	turn_ins += 1
	days_since_turn_in = 0


## Advances the weekly clock. Called once per [signal EventBus.day_started].
func new_day() -> void:
	if days_since_turn_in >= 0:
		days_since_turn_in += 1


## Clears the run so a repeatable quest can be accepted again from scratch, without
## touching [member turn_ins].
func reset_for_repeat() -> void:
	state = STATE_ACTIVE
	collected = 0
	spoke_to_target = false
	days_since_turn_in = -1


func to_dict() -> Dictionary:
	return {
		"quest_id": quest_id,
		"state": state,
		"collected": collected,
		"spoke_to_target": spoke_to_target,
		"turn_ins": turn_ins,
		"days_since_turn_in": days_since_turn_in,
	}


## Restores from a save.
##
## Every field is defaulted individually rather than trusted wholesale, because a save
## written before this feature existed has no quest section at all and a partially-formed
## one should degrade to "not started" instead of failing the whole load.
func from_dict(data: Dictionary) -> void:
	quest_id = StringName(String(data.get("quest_id", "")))
	var raw_state := StringName(String(data.get("state", STATE_ACTIVE)))
	state = raw_state if STATES.has(raw_state) else STATE_ACTIVE
	collected = maxi(int(data.get("collected", 0)), 0)
	spoke_to_target = bool(data.get("spoke_to_target", false))
	turn_ins = maxi(int(data.get("turn_ins", 0)), 0)
	days_since_turn_in = int(data.get("days_since_turn_in", -1))


## "Bring 2 of 5 parsnips" — the journal line. Needs the objective to phrase the noun.
func describe(objective: QuestObjective, item_name: String = "") -> String:
	if objective == null:
		return ""
	return "%d of %d %s" % [
		objective.current_amount(self), objective.required_amount(),
		item_name if not item_name.is_empty() else String(objective.item_id),
	]