class_name Friendship
extends Resource
## One villager's opinion of the player, in points, hearts and a name for the tier.
##
## A plain [Resource] with no [EventBus] in it, like [Stamina] and [Wallet], and for
## the same reason: it is loaded and saved as data, so a value holder that reached for
## an autoload would be unloadable from a `--script` run and unsaveable by anything
## but the live tree (see `AGENTS.md`, "Two Godot-specific traps").
##
## ## Points, not hearts
##
## [member points] is the real number and [method hearts] is a rounded-down view of
## it. Storing hearts instead would mean every gift that did not cross a 250-point
## boundary silently vanished, and a player watching the meter refuse to move would
## have no way to tell "no progress" from "lost progress". The heartbeat cap in
## Stardew is a real design idea and this is not that: here a point is a point and the
## heart only moves when there are a hundred more of them.
##
## ## Why the counters are here and not in the NPC
##
## [member gifts_today], [member loved_today] and [member gifts_this_week] are the
## gift-limit state, and they belong with the score they limit. Putting them on [Npc]
## would mean the save format carries two numbers in two places, and a villager whose
## relationship was restored without its gift counters would quietly become giftable
## a second time in the same day.

## Points per heart. Matches the constant the content test asserts heart thresholds
## against, and is a field rather than a literal everywhere so the economy can be
## retuned without hunting.
const POINTS_PER_HEART := 250
## Ten hearts, like every other game, and a cap so a relationship cannot be maxed
## twice by a double-counted gift.
const MAX_HEARTS := 10
## Points the maximum is worth, which is what the cap is applied to.
const MAX_POINTS := MAX_HEARTS * POINTS_PER_HEART

## A gift they have never been given before. The only one with a daily cap, because
## it is the only one expensive enough to farm.
const POINTS_LOVED := 80
## A gift they have mentioned. Ordinary goodwill.
const POINTS_LIKED := 45
## A gift that means nothing to them either way. Not zero: a player who brings a
## village a gift should get *something*, and zero would make neutral gifts feel
## broken.
const POINTS_NEUTRAL := 15
## A gift they dislike. Negative, and deliberately larger than neutral so handing
## someone the wrong thing is a worse mistake than handing them nothing.
const POINTS_DISLIKED := -20

## Gifts per in-game week, any reaction. Two, like every farming game, because the
## interesting decision is *which two*.
const WEEKLY_GIFT_LIMIT := 2
## Loved gifts per day. One. Without this the [constant POINTS_LOVED] cap is worth
## farming and the whole liked/disliked structure stops mattering.
const LOVED_GIFT_LIMIT := 1

## Heart count at which each tier name begins. Ascending; [method tier_name] walks
## this rather than branching, so adding a tier is one entry.
const TIER_THRESHOLDS: Array[int] = [0, 1, 2, 3, 4, 6, 8, 10]
const TIER_NAMES: Array[String] = [
	"Stranger", "Acquaintance", "Friend", "Close Friend",
	"Good Friend", "Confidant", "Trusted", "Soulbound",
]

## Points, the real number. Zero is a stranger, not a negative score: a villager who
## dislikes something the player found in a ditch is not *unfriendly*.
@export var points: int = 0
## Gifts accepted today. Reset by [method new_day].
@export var gifts_today: int = 0
## Loved gifts accepted today, tracked apart from [member gifts_today] because its
## limit is per day rather than per week.
@export var loved_today: int = 0
## Gifts accepted this week. Reset by [method new_week].
@export var gifts_this_week: int = 0


func hearts() -> int:
	return clampi(int(floor(float(points) / float(POINTS_PER_HEART))), 0, MAX_HEARTS)


## The name of the tier this relationship has reached.
##
## Walks [constant TIER_THRESHOLDS] backwards so the *highest* threshold the score has
## passed wins. A forward walk would report "Acquaintance" for a maxed-out friendship
## and quietly make ten hearts read as one.
func tier_name() -> String:
	if TIER_NAMES.is_empty():
		return "Stranger"
	var reached := 0
	for i: int in range(TIER_THRESHOLDS.size()):
		if hearts() >= TIER_THRESHOLDS[i]:
			reached = i
	return TIER_NAMES[clampi(reached, 0, TIER_NAMES.size() - 1)]


## Whether another gift can be accepted today at all.
##
## A *weekly* refusal, not a daily one: two gifts a week is the budget, and the
## loved-per-day cap is a separate question with a separate answer. Merging them
## would mean a player who gave two gifts on Monday could never give a loved one on
## Tuesday, which is the opposite of what the rule is for.
func can_gift_today() -> bool:
	return gifts_this_week < WEEKLY_GIFT_LIMIT


## Whether one more *loved* gift can be accepted today.
func can_gift_loved_today() -> bool:
	return loved_today < LOVED_GIFT_LIMIT


## Adds [param reaction]'s points and counts the gift, then returns the points that
## actually landed.
##
## Returns the real delta rather than the intended one, because a friendship already at
## ten hearts accepts a loved gift worth nothing and a caller that reported 80 would
## be telling the player their present mattered when it bought nothing.
##
## The counters advance whether or not the points did. A gift swallowed by a maxed
## meter still cost the player the gift, and still counts against the weekly budget —
## otherwise maxing one relationship would hand out unlimited free presents.
func award(reaction: StringName) -> int:
	var before := points
	points = clampi(points + points_for(reaction), 0, MAX_POINTS)
	gifts_today += 1
	gifts_this_week += 1
	if reaction == NpcData.REACTION_LOVED:
		loved_today += 1
	return points - before


## What [param reaction] is worth in points, as a constant lookup.
static func points_for(reaction: StringName) -> int:
	match reaction:
		NpcData.REACTION_LOVED:
			return POINTS_LOVED
		NpcData.REACTION_LIKED:
			return POINTS_LIKED
		NpcData.REACTION_DISLIKED:
			return POINTS_DISLIKED
		NpcData.REACTION_NEUTRAL:
			return POINTS_NEUTRAL
	return 0


## Clears the per-day gift state. Called on [signal EventBus.day_started].
func new_day() -> void:
	gifts_today = 0
	loved_today = 0


## Clears the weekly gift budget. Called by the same rollover.
func new_week() -> void:
	gifts_this_week = 0


## One line for a prompt or a HUD: "Friend, 2 hearts (420 points)".
func describe() -> String:
	return "%s, %d hearts (%d points)" % [tier_name(), hearts(), points]


func to_dict() -> Dictionary:
	return {
		"points": points,
		"gifts_today": gifts_today,
		"loved_today": loved_today,
		"gifts_this_week": gifts_this_week,
	}


## Restores from [method to_dict].
##
## Clamps on the way in rather than trusting the file. A save edited by hand, or
## written by an older build with a higher cap, would otherwise open the game with a
## friendship of -4000 that no gift could climb out of.
func from_dict(data: Dictionary) -> void:
	points = clampi(int(data.get("points", 0)), 0, MAX_POINTS)
	gifts_today = maxi(int(data.get("gifts_today", 0)), 0)
	loved_today = maxi(int(data.get("loved_today", 0)), 0)
	gifts_this_week = maxi(int(data.get("gifts_this_week", 0)), 0)


func copy() -> Friendship:
	var out := Friendship.new()
	out.from_dict(to_dict())
	return out