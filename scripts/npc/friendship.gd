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
##
## ## Why the romance is here too
##
## [member romance] is the third piece of the same relationship. Courtship is *earned*
## through hearts, so splitting it onto [Npc] would mean a save that restored one and
## not the other could hold a proposal with nothing to have proposed from. The bodies,
## the schedules and the farm house are all consequences of the stage; this number is
## the stage.

## The three states of a romance, in the order they are reached.
##
## An int rather than an enum because it is *saved*: a `Dictionary` key and a
## hand-edited `.tres` are both read by [method from_dict], and an enum that gained a
## fourth value later would leave an old file's `2` meaning something else. The names
## live here so no caller writes a bare `1`.
const STAGE_NONE := 0
const STAGE_DATING := 1
const STAGE_MARRIED := 2

## Hearts at which a romanceable villager will agree to court the player.
##
## Deliberately *below* the top of the meter: a proposal that needs ten hearts means
## the last stretch of a relationship is the one that pays off, and a courtship
## reachable at one heart would make the gift economy pointless. Six is the
## "Confidant" tier, so the prompt and the meter say the same thing about when it opens.
const COURT_HEARTS := 6
## Hearts at which a dating villager will say yes to a proposal. Ten, the cap: asking
## for the whole meter is what makes the proposal the end of the road rather than a
## step on it.
const PROPOSE_HEARTS := 10
## What a birthday does to a positive reaction. Negative reactions are *not* doubled —
## being handed a rock on your birthday is not twice as insulting, and doubling the
## downside would make the day a trap rather than a treat.
const BIRTHDAY_MULTIPLIER := 2

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
## How far the romance has come, as one of [constant STAGE_NONE],
## [constant STAGE_DATING] or [constant STAGE_MARRIED].
##
## Here rather than on [Npc] for the same reason the gift counters are: it is part of
## the relationship, it is saved with it, and a spouse restored without the rest of the
## friendship would be a marriage nothing remembered.
@export var romance: int = STAGE_NONE


func hearts() -> int:
	return clampi(int(floor(float(points) / float(POINTS_PER_HEART))), 0, MAX_HEARTS)


## Whether the player is seeing this villager.
func is_dating() -> bool:
	return romance >= STAGE_DATING


## Whether this villager lives on the farm now.
func is_married() -> bool:
	return romance >= STAGE_MARRIED


## The stage as a word for a prompt or a HUD: "", "dating" or "married".
##
## Lower case and appended rather than substituted, because "Mira, 6/10, dating" keeps
## the meter readable while "Mira, dating" throws away the number the whole panel is
## there to show.
func romance_stage_name() -> String:
	match clampi(romance, STAGE_NONE, STAGE_MARRIED):
		STAGE_DATING:
			return "dating"
		STAGE_MARRIED:
			return "married"
	return ""


## Whether [method court] would succeed right now, and why not when it would not.
##
## The rule lives here so the prompt, the press and the test all ask one question. The
## reason is the same machine-readable vocabulary [signal
## EventBus.romance_started_failed] publishes, so a refusal cannot be worded one way
## on screen and another on the bus.
func court_refusal() -> StringName:
	if romance >= STAGE_DATING:
		return &"already_involved"
	if hearts() < COURT_HEARTS:
		return &"not_enough_hearts"
	return &""


## Whether [method propose] would succeed right now, and why not when it would not.
func propose_refusal() -> StringName:
	if romance >= STAGE_MARRIED:
		return &"already_married"
	if romance < STAGE_DATING:
		return &"not_courting"
	if hearts() < PROPOSE_HEARTS:
		return &"not_enough_hearts"
	return &""


## Moves the relationship to [constant STAGE_DATING]. Returns false, unchanged, if
## [method court_refusal] says no — so a caller cannot court a stranger by forgetting
## to check.
func court() -> bool:
	if not court_refusal().is_empty():
		return false
	romance = STAGE_DATING
	return true


## Moves the relationship to [constant STAGE_MARRIED], for the same reason.
func propose() -> bool:
	if not propose_refusal().is_empty():
		return false
	romance = STAGE_MARRIED
	return true


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
##
## [param birthday] doubles a *positive* reaction and changes nothing else — not the
## counters, not the caps, not the negative ones. A birthday is worth going out of your
## way for, and a day on which a disliked gift costs twice as much would be a day the
## player is better off not giving anything at all.
func award(reaction: StringName, birthday: bool = false) -> int:
	var before := points
	var worth := points_for(reaction)
	if birthday and worth > 0:
		worth *= BIRTHDAY_MULTIPLIER
	points = clampi(points + worth, 0, MAX_POINTS)
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


## Adds [param amount] whole hearts, ignoring [member POINTS_PER_HEART]'s remainder.
##
## The whole-heart version of [method award], for payment that arrives as a number of hearts
## rather than as a reaction to a gift. Clamped like [method award] so a reward cannot push
## a friendship past [constant MAX_HEARTS], and deliberately does **not** touch
## [member gifts_today] or [member gifts_this_week]: nobody handed this villager a present,
## so spending one of today's two gifts on a quest reward would be a tax nobody agreed to.
func add_hearts(amount: int) -> int:
	var before := hearts()
	points = clampi(points + maxi(amount, 0) * POINTS_PER_HEART, 0, MAX_POINTS)
	return hearts() - before


## One line for a prompt or a HUD: "Friend, 2 hearts (420 points)".
func describe() -> String:
	return "%s, %d hearts (%d points)" % [tier_name(), hearts(), points]


func to_dict() -> Dictionary:
	return {
		"points": points,
		"gifts_today": gifts_today,
		"loved_today": loved_today,
		"gifts_this_week": gifts_this_week,
		"romance": romance,
	}


## Restores from [method to_dict].
##
## Clamps on the way in rather than trusting the file. A save edited by hand, or
## written by an older build with a higher cap, would otherwise open the game with a
## friendship of -4000 that no gift could climb out of — and a `romance` of 9 would
## open it with a marriage state no code knows how to leave.
func from_dict(data: Dictionary) -> void:
	points = clampi(int(data.get("points", 0)), 0, MAX_POINTS)
	gifts_today = maxi(int(data.get("gifts_today", 0)), 0)
	loved_today = maxi(int(data.get("loved_today", 0)), 0)
	gifts_this_week = maxi(int(data.get("gifts_this_week", 0)), 0)
	romance = clampi(int(data.get("romance", STAGE_NONE)), STAGE_NONE, STAGE_MARRIED)


func copy() -> Friendship:
	var out := Friendship.new()
	out.from_dict(to_dict())
	return out