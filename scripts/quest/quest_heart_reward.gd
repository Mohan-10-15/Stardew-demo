class_name QuestHeartReward
extends Resource
## "Bram likes you one heart more for this" — one villager's slice of a quest's reward.
##
## Its own resource rather than a `Dictionary` in a list because a reward that is a bag of
## untyped pairs cannot be checked. With this, [method QuestReward.is_valid] can ask
## whether every villager named in a reward is somebody who exists, and a content test can
## assert it — which is what caught the legacy quests in
## `resources/legacy_content/quests.json` rewarding a `topaz` that no item registry has ever
## heard of, and two villagers who are not in the valley.

## Who gains the friendship. Must be a villager that [NpcRegistry] knows.
@export var npc: StringName = &""
## How many hearts. Capped at [member MAX_HEARTS] rather than unbounded so a content author
## cannot author a quest that maxes out friendship in one delivery.
@export_range(1, 3, 1) var amount: int = 1

## The most a single quest may hand out. Two is already generous; three is the price of a
## favour nobody would ask twice, which is why it is a named constant and not a mystery
## number in a `.tres`.
const MAX_HEARTS := 3


func is_valid() -> bool:
	return not npc.is_empty() and amount >= 1 and amount <= MAX_HEARTS


## "Bram (1 heart)" — for a reward line.
func describe(display_name: String = "") -> String:
	var who: String = display_name if not display_name.is_empty() else String(npc)
	return "%s (%d %s)" % [who, amount, "heart" if amount == 1 else "hearts"]