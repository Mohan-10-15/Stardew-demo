class_name DialogueTree
extends Resource
## Every line one villager can say, as one loadable unit.
##
## One file per villager under `resources/npc/dialogue/`, keyed by
## [member npc_id] — the same contract as [NpcSchedule]: the id inside the file
## is what says whom the content is about, and the file name is not
## load-bearing.
##
## [method is_valid] returns an empty string when the tree is sound and a
## sentence naming the problem when it is not. The registry refuses an invalid
## tree at load and the generator refuses to write one, so a dangling reply or a
## blank line fails the build with the id of the entry at fault rather than
## appearing in game as a villager who stops talking mid-sentence.

## Whom this tree belongs to. Must name a real villager for the content test;
## the registry itself only requires it to be non-empty, because — like
## [ScheduleRegistry] — loading content should not need every other content
## directory to do its job.
@export var npc_id: StringName = &""

## Every line, in authored order. Order is the final tie-break in selection, so
## the first written fallback is the one that speaks when everything else is
## even.
@export var entries: Array[DialogueEntry] = []


## The entry with this [param id], or null.
func entry(id: StringName) -> DialogueEntry:
	for e: DialogueEntry in entries:
		if e != null and e.id == id:
			return e
	return null


## Every entry id, in authored order.
func entry_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: DialogueEntry in entries:
		if e != null:
			out.append(e.id)
	return out


## Whether at least one entry would match an *empty* context — the "can this
## villager ever fall back to something" question, checked for the default
## (Spring, sunny, midday, no hearts, no flags) situation by
## [method fallback_exists_for].
func has_unconditional_entry() -> bool:
	for e: DialogueEntry in entries:
		if e != null and e.condition_count() == 0 and not e.once:
			return true
	return false


## Whether at least one entry matches [param ctx] with all `once` entries
## treated as spent. The real guarantee behind `no_matching_entry`: the service
## runs this before it picks, and content is tested across a sweep of contexts
## so a tree that goes quiet in Winter is caught by a test, not by a player.
func fallback_exists_for(ctx: Dictionary) -> bool:
	for e: DialogueEntry in entries:
		if e == null:
			continue
		if e.once:
			continue
		if e.matches(ctx):
			return true
	return false


## `""` when the tree is sound; a sentence naming the first problem otherwise.
func is_valid() -> String:
	if npc_id.is_empty():
		return "tree has no npc_id"
	if entries.is_empty():
		return "tree for '%s' has no entries" % npc_id
	var seen_ids: Dictionary = {}
	var has_fallback := false
	for e: DialogueEntry in entries:
		if e == null:
			return "tree for '%s' contains a null entry" % npc_id
		if e.id.is_empty():
			return "tree for '%s' has an entry with no id" % npc_id
		if seen_ids.has(e.id):
			return "tree for '%s' has duplicate entry id '%s'" % [npc_id, e.id]
		seen_ids[e.id] = true
		if e.text.strip_edges().is_empty():
			return "entry '%s' has no text" % e.id
		var err := _validate_conditions(e)
		if not err.is_empty():
			return err
		err = _validate_effects(e)
		if not err.is_empty():
			return err
		if e.condition_count() == 0 and not e.once:
			has_fallback = true
		for c: DialogueChoice in e.choices:
			if c == null:
				return "entry '%s' contains a null choice" % e.id
			if c.text.strip_edges().is_empty():
				return "entry '%s' has a choice with no text" % e.id
			if c.hearts < 0:
				return "entry '%s' has a choice granting negative hearts" % e.id
	for e: DialogueEntry in entries:
		if e == null:
			continue
		if not e.next.is_empty() and entry(e.next) == null:
			return "entry '%s' points at missing entry '%s'" % [e.id, e.next]
		for c: DialogueChoice in e.choices:
			if c != null and not c.next.is_empty() and entry(c.next) == null:
				return "entry '%s' choice '%s' points at missing entry '%s'" % [
					e.id, c.text, c.next,
				]
	if not has_fallback:
		return "tree for '%s' has no unconditional fallback entry" % npc_id
	return ""


## Condition bounds: seasons, weathers and hours inside their enums, and a
## window that actually opens before it closes.
func _validate_conditions(e: DialogueEntry) -> String:
	if e.season != DialogueEntry.ANY_SEASON and (e.season < 0 or e.season > 3):
		return "entry '%s' has season %d, which is not a season" % [e.id, e.season]
	if e.weather != DialogueEntry.ANY_WEATHER and (e.weather < 0 or e.weather > 4):
		return "entry '%s' has weather %d, which is not a weather" % [e.id, e.weather]
	for hour: int in [e.hour_from, e.hour_to]:
		if hour != DialogueEntry.ANY_HOUR and (hour < 0 or hour > 23):
			return "entry '%s' has hour %d, which is not an hour" % [e.id, hour]
	# A window whose opening hour is after its closing one spans midnight and is
	# legal (23→5 is "late night"); a window with both ends equal is a single
	# hour and equally legal. Only the bounds themselves are checked.
	if e.min_hearts > 10:
		return "entry '%s' requires %d hearts, more than exist" % [e.id, e.min_hearts]
	if e.max_hearts > 10:
		return "entry '%s' caps at %d hearts, more than exist" % [e.id, e.max_hearts]
	return ""


## Effect bounds: nothing that costs the player friendship for speaking, and no
## line that jumps to itself.
func _validate_effects(e: DialogueEntry) -> String:
	if e.hearts < 0:
		return "entry '%s' grants negative hearts" % e.id
	if e.next == e.id:
		return "entry '%s' points at itself" % e.id
	return ""


## One-line summary for logs and test messages.
func describe() -> String:
	return "DialogueTree '%s' (%d entries)" % [npc_id, entries.size()]
