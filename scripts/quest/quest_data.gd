class_name QuestData
extends Resource
## What one quest is: who asks, what they want, and what they pay.
##
## ## The quest system's answer to "content is data"
##
## Nothing in [QuestService] switches on a quest id. Adding the seventh job in the valley is
## one `.tres` in `resources/quest/quests/` and no code — the same bargain
## [NpcData] strikes for villagers, and the reason this is a resource rather than a match
## statement with five arms.
##
## ## Why `deliver` needs a target distinct from the giver
##
## A `collect` quest is handed to the person who asked for it, so it needs no target of its
## own. A `deliver` quest is about the *pair*: fetch the thing, then find the person who
## wanted it. With a single giver field those two are indistinguishable, and a delivery to
## Mira becomes indistinguishable from a hand-in to Mira, which quietly makes half the
## objective kinds pointless. So the target lives in [QuestObjective.target_npc] and
## [method is_valid] rejects a delivery to the giver rather than resolving it as a collect.

## Never offered again once handed in.
const REPEATS_ONCE := &"once"
## Offered again after [constant QuestProgress.WEEKLY_INTERVAL_DAYS].
const REPEATS_WEEKLY := &"weekly"

## Every repeat mode, for a content test that asserts the vocabulary is closed.
const REPEATS: Array[StringName] = [REPEATS_ONCE, REPEATS_WEEKLY]

@export var id: StringName = &""
@export var title: String = "Job"
## One or two lines shown in the journal and when the quest is offered. The player reads
## this instead of the objective's field names.
@export_multiline var description: String = ""
## Who offers it. The player hands a `collect` quest back to this person.
@export var giver: StringName = &""
## What is wanted.
@export var objective: QuestObjective = null
## What is paid.
@export var reward: QuestReward = null
@export var repeats: StringName = REPEATS_ONCE
## Hearts of friendship the giver wants before they will offer this at all.
##
## `-1` means no gate, which is the default and the value four of the five shipped
## jobs carry. A job is "something the player wants", which is exactly what
## `docs/ACCEPTANCE.md` asks friendship to gate: a villager who hands a stranger the
## keys to their delivery run before they have ever had a conversation with them is
## a quest system with no people in it.
##
## The gate is applied by [method QuestService.next_offer_from], never by refusing an
## acceptance — an id a player was somehow offered must still be accepted, so the rule
## cannot turn into a dead end that fails for a reason the player cannot see.
@export var min_hearts: int = -1


## Whether this quest is authored well enough to be offered, and — more importantly —
## whether it can be completed.
##
## The objective and reward checks are not optional politeness. A quest whose objective
## refers to an item nothing produces, or a reward that pays a villager who does not exist,
## is a quest a player can accept and then never finish, and the failure surfaces as a bug
## report with no error in the log. Refusing the content at load time turns that into a
## failing test instead.
func is_valid() -> bool:
	if id.is_empty() or title.is_empty():
		return false
	if giver.is_empty():
		return false
	if not NpcRegistry.has_npc(giver):
		return false
	if objective == null or not objective.is_valid():
		return false
	if reward == null or not reward.is_valid() or reward.is_empty():
		return false
	if not REPEATS.has(repeats):
		return false
	# `-1` is the "no gate" sentinel; anything past the meter is a threshold nothing
	# can reach, which is a job nobody can ever be offered and no test would notice.
	if min_hearts < -1 or min_hearts > Friendship.MAX_HEARTS:
		return false
	if objective.kind == QuestObjective.KIND_DELIVER and objective.target_npc == giver:
		# A delivery to the person who asked for it is a collect. Accepting it here would
		# produce a quest with two ways to finish it and one prompt.
		return false
	if objective.needs_an_item() and not NpcData.is_known_item(objective.item_id):
		return false
	for item_id: StringName in reward.items:
		if not NpcData.is_known_item(item_id):
			return false
	if objective.target_npc != &"" and not NpcRegistry.has_npc(objective.target_npc):
		return false
	for heart: QuestHeartReward in reward.hearts:
		if not NpcRegistry.has_npc(heart.npc):
			return false
	return true


## One line naming the villager who offers it, for a prompt: "Job — Bram".
func describe_giver() -> String:
	var npc := NpcRegistry.get_npc(giver)
	return npc.display_name if npc != null else String(giver)


## What this quest wants, in a line of English.
##
## The giver is named, because this line is read where the villager is not: a log entry
## and a journal row both have to say who to go back to on their own.
func describe_objective() -> String:
	if objective == null:
		return ""
	return objective.describe(QuestReward.item_name(objective.item_id), describe_giver())


## Whether this quest has a repeat at all, as opposed to being a one-off.
func repeats_forever() -> bool:
	return repeats != REPEATS_ONCE


## Whether friendship decides whether this job is offered at all.
func gates_on_hearts() -> bool:
	return min_hearts >= 0