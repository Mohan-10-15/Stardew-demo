class_name DialogueEntry
extends Resource
## One line of villager dialogue, the conditions under which it is said, and
## what saying it does.
##
## ## The condition set is a filter, not a priority queue
##
## Every condition on an entry is a question about the *context*: what season it
## is, what the weather is doing, what hour of the day it is, how far the
## relationship has come, which story flags are set. An entry with no conditions
## is a fallback — a line that is always true — and every tree must keep at
## least one, because a tree whose entries can all be ruled out is a villager
## who can fall silent, which is the `no_matching_entry` refusal.
##
## ## Specificity decides who speaks
##
## When several entries match, the one with the most active conditions wins
## (see [method DialogueService.select]), because a line written for "rainy
## Spring evening at four hearts" is more *true* of this moment than a line
## written for "morning". Ties rotate by how often each has been shown, so a
## villager does not repeat the same seasonal line every time the season comes
## up.
##
## ## Effects apply when the line is left, not when it is shown
##
## Hearts and flags are granted on [method DialogueService.advance] or
## [method DialogueService.choose] — when the player has actually read the line
## and moved on. Applying on display would credit a line the player skipped out
## of before a single word appeared.

## Condition: any season. Otherwise a [enum WorldTime.Season] value.
const ANY_SEASON := -1
## Condition: any weather. Otherwise a [enum WorldTime.Weather] value.
const ANY_WEATHER := -1
## Condition: any hour. Otherwise 0–23.
const ANY_HOUR := -1

## Unique within its tree. What `next` links and reply targets aim at.
@export var id: StringName = &""

## The words on screen. Never empty — [method DialogueTree.is_valid] refuses it.
@export var text: String = ""

# --- Conditions ------------------------------------------------------------
## Only said in this season ([constant ANY_SEASON] for any).
@export var season: int = ANY_SEASON
## Only said in this weather ([constant ANY_WEATHER] for any).
@export var weather: int = ANY_WEATHER
## Only said from this hour on, inclusive ([constant ANY_HOUR] for any).
@export var hour_from: int = ANY_HOUR
## Only said up to this hour, inclusive ([constant ANY_HOUR] for any).
@export var hour_to: int = ANY_HOUR
## Only said once the relationship has reached this many hearts.
@export var min_hearts: int = -1
## Only said while the relationship is *at or below* this many hearts, for lines
## that belong to a relationship that has not warmed yet.
@export var max_hearts: int = -1
## Only said while this story flag is set. Empty means no requirement.
@export var requires_flag: StringName = &""
## Only said while this story flag is *not* set — the "before they told me"
## version of a line, consumed once the flag is raised.
@export var excludes_flag: StringName = &""
## Said at most once per save. The mechanism behind introductions and one-time
## story beats: after the first showing the entry leaves the candidate set for
## good, so the fallback underneath it takes over.
@export var once: bool = false

# --- Effects ---------------------------------------------------------------
## Hearts granted when the player leaves this line. Whole hearts, non-negative;
## see [DialogueChoice.hearts].
@export var hearts: int = 0
## Story flags raised when the player leaves this line.
@export var set_flags: Array[StringName] = []
## The entry to show next when the player advances past this line, or [code]&""
## to end the conversation. A chain, not a menu — menus belong to [member choices].
@export var next: StringName = &""
## The replies offered instead of a plain continue. Empty means "advance ends or
## follows [member next]"; non-empty means the conversation waits for a pick.
@export var choices: Array[DialogueChoice] = []


## How many conditions are actually constraining this line.
##
## The specificity score behind selection: two active conditions beat one, one
## beats none. An inactive condition ([constant ANY_SEASON] and friends) adds
## nothing, so an authored fallback really does score zero.
func condition_count() -> int:
	var n := 0
	if season != ANY_SEASON:
		n += 1
	if weather != ANY_WEATHER:
		n += 1
	if hour_from != ANY_HOUR or hour_to != ANY_HOUR:
		n += 1
	if min_hearts >= 0 or max_hearts >= 0:
		n += 1
	if not requires_flag.is_empty():
		n += 1
	if not excludes_flag.is_empty():
		n += 1
	return n


## Whether this line may be said in [param ctx].
##
## [param ctx] is the dictionary [DialogueService.build_context] produces:
## `season`, `weather`, `hour`, `hearts` and `flags` (a `Dictionary` of set
## flags). Unknown or missing keys count as "no information", and a condition
## that needs the missing key fails closed — a test that forgot to set a season
## does not silently match every seasonal line.
func matches(ctx: Dictionary) -> bool:
	if season != ANY_SEASON and int(ctx.get("season", -999)) != season:
		return false
	if weather != ANY_WEATHER and int(ctx.get("weather", -999)) != weather:
		return false
	var hour := int(ctx.get("hour", -999))
	# A window whose opening hour is *after* its closing hour spans midnight —
	# 23 to 5 is "late night", not an error, and refusing it would force every
	# night line into two entries that both have to be maintained.
	if hour_from != ANY_HOUR and hour_to != ANY_HOUR and hour_from > hour_to:
		if hour < hour_from and hour > hour_to:
			return false
	else:
		if hour_from != ANY_HOUR and hour < hour_from:
			return false
		if hour_to != ANY_HOUR and hour > hour_to:
			return false
	var hearts := int(ctx.get("hearts", -1))
	if min_hearts >= 0 and hearts < min_hearts:
		return false
	if max_hearts >= 0 and hearts > max_hearts:
		return false
	var flags: Variant = ctx.get("flags", {})
	var set_flags_now: Dictionary = flags if flags is Dictionary else {}
	if not requires_flag.is_empty() and not bool(set_flags_now.get(requires_flag, false)):
		return false
	if not excludes_flag.is_empty() and bool(set_flags_now.get(excludes_flag, false)):
		return false
	return true


## Whether the conversation waits for a reply rather than continuing.
func has_choices() -> bool:
	return not choices.is_empty()


## One-line summary for a validation message.
func describe() -> String:
	return "entry '%s' (%d conditions)" % [id, condition_count()]
