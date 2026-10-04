class_name NpcData
extends Resource
## What one villager is: who they are, what they look like, where they live, and
## what they like being given.
##
## The NPC system's answer to "content is data". Nothing in [Npc] or [NpcManager]
## switches on a villager's id, so the seventh inhabitant of the valley is one
## `.tres` in `resources/npc/npcs/` and no code at all — the same bargain
## [ResourceNodeData] strikes for trees, and the reason this is a resource and not a
## match statement with six arms.
##
## ## Why the gifts are three lists and not one
##
## [member loved_gifts], [member liked_gifts] and [member disliked_gifts] are
## separate rather than one list with a weight per entry. A single list would put
## "loves honey, dislikes rocks" in two places in one structure and make the
## interesting question — *does this person love this thing?* — answerable only by
## scanning. Three lists mean a lookup is a membership test, which is what a gift
## actually is, and an entry in two of them is a content bug a test can catch rather
## than a silent precedence rule.
##
## ## Why art is a path and a tint
##
## The CC0 character pack ships five rigged bodies and the GDD wants a dozen
## villagers. [member model] picks the body and [member tint] recolours it, so six
## villagers share five models without six copies of the same silhouette looking like
## six of the same person. Two villagers wearing the same tint and the same body is
## allowed — nothing stops it — but `duplicate_appearances` in the registry exists so
## a content test can notice if the whole cast ends up in one costume.

@export var id: StringName = &""
@export var display_name: String = "Villager"
## One line shown in the prompt and the dialogue header. Not the id: a player reads
## "Mira", never "npc_mira".
@export var description: String = ""

@export_group("Art")
## The CC0 character model this villager wears. Required — a villager with no body
## is a collider the player aims at and cannot place.
@export var model: String = ""
## Multiplied over the model's own colours so five bodies can carry a cast of twelve.
@export var model_tint: Color = Color(1, 1, 1, 1)
## Metres. Measured from the model rather than trusted from content, so a villager
## is never three times the height of the player because someone typed a number.
@export_range(0.5, 3.0, 0.05) var target_height: float = 1.8

@export_group("Home")
## Where this villager lives, in world metres on the XZ plane. Absolute rather than
## "in the village" plus an offset, because the village is a shape somebody will move
## and a home that quietly moves with it is a home that stops being anybody's.
@export var home: Vector2 = Vector2.ZERO
## How far from [member home] they drift when they have nothing to do. Group 15 turns
## this into a schedule; until then it is the whole of their movement.
@export_range(0.5, 40.0, 0.5) var wander_radius: float = 6.0
## Metres per second. Villagers walk slower than the player sprints and slower than
## the player walks, because a villager who keeps pace with you is a nuisance.
@export_range(0.2, 8.0, 0.1) var walk_speed: float = 1.8

@export_group("Dates")
## Which season this villager's birthday falls in. Indexed into [enum WorldTime.Season]
## rather than stored as a name, so a save does not carry a string that a rename
## would orphan.
@export_range(0, 3, 1) var birthday_season: int = 0
@export_range(1, 28, 1) var birthday_day: int = 1

@export_group("Gifts")
## Gave these before: the reaction that matters, and the only one with a daily cap.
@export var loved_gifts: Array[StringName] = []
## Would enjoy. Positive, no cap of its own.
@export var liked_gifts: Array[StringName] = []
## Actively unhappy to receive. Negative, and the cap does not save you.
@export var disliked_gifts: Array[StringName] = []

## Whether the birthday is a real date.
##
## Month 0 day 0 is the sentinel for "nobody told me", which is different from Spring
## 1st, and a villager whose birthday silently lands on the first of the first month
## because a field defaulted is a small lie the player can catch.
func has_birthday() -> bool:
	return birthday_season > 0 and birthday_day > 0


func is_valid() -> bool:
	if id.is_empty() or display_name.is_empty():
		return false
	if model.is_empty():
		return false
	if target_height <= 0.0:
		return false
	if walk_speed <= 0.0 or wander_radius <= 0.0:
		return false
	if birthday_day < 0 or birthday_day > 28:
		return false
	if birthday_season < 0 or birthday_season > 3:
		return false
	# A gift in two lists is not a preference, it is an unresolved question, and the
	# first list to be searched would decide it silently. Refuse the content instead.
	for id_in_loved: StringName in loved_gifts:
		if liked_gifts.has(id_in_loved) or disliked_gifts.has(id_in_loved):
			return false
	for id_in_liked: StringName in liked_gifts:
		if disliked_gifts.has(id_in_liked):
			return false
	return true


## How this villager feels about being handed [param item_id].
##
## [constant REACTION_LOVED] and friends, or an empty [StringName] when the item is
## not one this villager has an opinion about — which is *not* the same as disliking
## it. An unlisted gift is a pleasant nothing; a disliked one costs friendship, and
## collapsing the two would mean a player could never give a safe present.
func reaction_to(item_id: StringName) -> StringName:
	if loved_gifts.has(item_id):
		return REACTION_LOVED
	if liked_gifts.has(item_id):
		return REACTION_LIKED
	if disliked_gifts.has(item_id):
		return REACTION_DISLIKED
	return REACTION_NEUTRAL


## "Mira (Friend, 2 hearts)" — the name and the standing, for a prompt.
##
## The tier name rather than a bare number, because "3" on its own tells a player
## nothing and the whole point of the meter is that it is legible.
func describe_standing(friendship: Friendship) -> String:
	if friendship == null:
		return display_name
	return "%s (%s, %d hearts)" % [display_name, friendship.tier_name(), friendship.hearts()]


## Whether [param item_id] is something a villager can be handed at all.
##
## By [enum ItemDefinition.Category] and not by a flag on the item, because
## giftability here is a fact about *what the thing is*: nobody wants to be handed a
## rake, and a hoe left in a villager's hands is a bug whether or not the hoe's author
## thought of it.
static func is_giftable(item: ItemDefinition) -> bool:
	if item == null:
		return false
	if item.is_tool():
		return false
	return item.category == ItemDefinition.Category.CROP \
		or item.category == ItemDefinition.Category.FORAGE \
		or item.category == ItemDefinition.Category.MATERIAL \
		or item.category == ItemDefinition.Category.FOOD


## Whether [param item_id] — the id a bag stack actually carries — can be handed over.
##
## The id-level question rather than a definition-level one because a harvested crop
## enters the bag under its crop id and has no [ItemDefinition] at all, exactly as
## [method ItemRegistry.sell_price_of] documents for selling. Asking only
## [method is_giftable] therefore made every crop ungiftable: a villager whose loved
## list is written in parsnips could never be given one, and the prompt quietly
## downgraded to "talk" while the player was holding the very thing they loved.
static func is_giftable_id(item_id: StringName) -> bool:
	if item_id.is_empty():
		return false
	var item := ItemRegistry.get_item(item_id)
	if item != null:
		return is_giftable(item)
	# A crop is giftable by being a crop; there is no definition to check and nothing
	# about a harvested parsnip that makes it unsuitable as a present.
	return CropRegistry.has_crop(item_id)


## Whether anything at all in the content is authored behind [param item_id].
##
## The "stack with no definition behind it" question, kept apart from
## [method is_giftable_id] because the two refusals are different sentences: a hoe is a
## thing that exists and is not a present, a `ghost_item` is a thing the game has never
## heard of, and a player who is handed one of those deserves to know which.
static func is_known_item(item_id: StringName) -> bool:
	if item_id.is_empty():
		return false
	return ItemRegistry.has_item(item_id) or CropRegistry.has_crop(item_id)


## What this villager calls the reaction, for a prompt or a line of dialogue.
static func describe_reaction(reaction: StringName) -> String:
	match reaction:
		REACTION_LOVED:
			return "love"
		REACTION_LIKED:
			return "like"
		REACTION_DISLIKED:
			return "dislike"
		REACTION_NEUTRAL:
			return "a passing interest"
	return "no opinion"


## The reaction an unlisted gift gets. Named rather than left to a `match` default so
## a new reaction cannot appear in one place and be forgotten in the other.
const REACTION_LOVED := &"loved"
const REACTION_LIKED := &"liked"
const REACTION_NEUTRAL := &"neutral"
const REACTION_DISLIKED := &"disliked"

## Every reaction, for a content test that asserts the vocabulary is closed. Adding
## an arm to [method describe_reaction] without adding it here fails that test.
const REACTIONS: Array[StringName] = [
	REACTION_LOVED, REACTION_LIKED, REACTION_NEUTRAL, REACTION_DISLIKED,
]

## The season names, indexed the way [member birthday_season] is.
const SEASON_NAMES: Array[String] = ["Spring", "Summer", "Fall", "Winter"]

## What this villager's birthday reads as: "12 Fall" or nothing.
func describe_birthday() -> String:
	if not has_birthday():
		return ""
	if birthday_season >= SEASON_NAMES.size():
		return ""
	return "%d %s" % [birthday_day, SEASON_NAMES[birthday_season]]