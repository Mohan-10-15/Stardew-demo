class_name QuestReward
extends Resource
## What a quest hands over when it is turned in: gold, items, and friendship.
##
## ## Why every field is separate rather than one weighted list
##
## Same bargain as [member NpcData.loved_gifts]: a gold purse and a villager's opinion are
## not denominations of the same currency. Keeping gold, items and hearts as three fields
## means "what does this quest pay?" is three readable values instead of a list of tuples
## with a tag, and it means the service pays each through the system that owns it — gold
## through [Wallet], friendship through [NpcManager] — rather than the quest system reaching
## into both.
##
## A quest pays out through other systems rather than touching the player directly, which is
## why this class holds no reference to a player and no code that pays anything.

## Gold into the purse. Zero is a legitimate reward for a quest whose real payment is
## friendship, so there is no minimum.
@export var gold: int = 0
## Items into the bag, by id, one entry per *kind* of item rather than per unit, because
## "a bag and a butter" and "three bags and a butter" are not different rewards and an author
## should not have to encode the second as two nearly-identical entries.
@export var items: Array[StringName] = []
## How many of each entry in [member items] the player is handed. One per kind is the usual
## case; two is for the pair of things that always come as a pair. A list of units instead of
## this would mean the amount lives in the list's length, which cannot say "two of each".
@export_range(1, 99, 1) var item_amount: int = 1
## Friendship, which is a payment the player does not hold.
@export var hearts: Array[QuestHeartReward] = []


## Whether this reward is nothing at all, which is never allowed.
##
## Asked separately from [method is_valid] because "a quest that pays nothing" and "a quest
## that is malformed" are different content bugs and deserve different messages.
func is_empty() -> bool:
	return gold <= 0 and items.is_empty() and hearts.is_empty()


## Whether this reward is authored well enough to pay out.
##
## Only structural checks. Whether the item exists is [method QuestData.is_valid]'s
## question, because a reward naming a nonexistent item is a broken quest, not a broken
## reward, and the error message should say which file is at fault.
func is_valid() -> bool:
	if gold < 0:
		return false
	if item_amount < 1:
		return false
	for heart: QuestHeartReward in hearts:
		if heart == null or not heart.is_valid():
			return false
	return true


## One line for a reward popup: "350g, 2 Wild Berry, Bram (1 heart)".
func describe() -> String:
	var parts: Array[String] = []
	if gold > 0:
		parts.append("%dg" % gold)
	for id: StringName in items:
		var noun := item_name(id)
		parts.append(("%d %s" % [item_amount, noun]) if item_amount > 1 else noun)
	for heart: QuestHeartReward in hearts:
		parts.append(heart.describe())
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## The items this reward pays, with duplicates collapsed.
##
## The economy's [signal EventBus.item_added] is the single funnel for "the player now holds
## this", so the service pays one line per distinct id rather than one per entry. Paying
## twice for the same id would still be arithmetically right and would double every stack
## alert, so the collapse is deliberate and lives next to the thing that causes it.
func distinct_items() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in items:
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


## What to call [param id] in a line of text, for [param amount] of them.
##
## Resolves across both item and crop registries, in-lane, because a quest asking for
## parsnips is asking for something with no [ItemDefinition] at all — a harvested crop
## enters the bag under its crop id. [method ItemRegistry.display_name_of] falls back to the
## raw id in that case, which would print "parsnip" in a reward popup.
##
## [method item_name] is the singular form. Quest prose wants this one, because "Bring 20
## Woods" is the sort of bug a suite asserting on ids walks straight past: the id is right,
## the count is right, and the English is wrong. The plural comes from the item, not from a
## rule in this lane — see [method ItemDefinition.plural].
static func name_of(id: StringName, amount: int = 1) -> String:
	var item := ItemRegistry.get_item(id)
	if item != null:
		return item.plural(amount)
	var crop := CropRegistry.get_crop(id)
	if crop != null:
		return crop.plural(amount)
	return String(id)


## The singular name for [param id]. See [method name_of].
static func item_name(id: StringName) -> String:
	var item := ItemRegistry.get_item(id)
	if item != null:
		return item.display_name
	var crop := CropRegistry.get_crop(id)
	if crop != null:
		return crop.display_name
	return String(id)