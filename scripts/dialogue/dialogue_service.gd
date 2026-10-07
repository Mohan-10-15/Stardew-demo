class_name DialogueService
extends Node
## Opens, runs and ends conversations, and remembers what was said.
##
## ## What it owns
##
## The rules of a conversation: which line is showing, which lines have already
## been shown, which story flags are set, and what saying a line or picking a
## reply grants. It draws nothing and reads no input — the panel
## ([DialogueUI]) is a listener and a caller, the same split as
## [QuestService] and the tracker. That is what lets every dialogue test run
## headless against this node alone, and what lets a cutscene later drive a
## conversation without a panel at all.
##
## ## Selection is a pure function
##
## [method select] takes a tree, a context and a seen-table and returns the
## line to say. No tree access, no signals, no state — so the interesting
## question ("what does she say on a rainy Winter night at four hearts?") is
## answered by a unit test with a dictionary, not by booting a village and
## waiting for the weather.
##
## ## Pairing
##
## Every [signal EventBus.dialogue_started] is answered by exactly one
## [signal EventBus.dialogue_finished] — including when a conversation is cut
## short by [method cancel] or by a broken `next` link, both of which still owe
## the listener a close. [signal EventBus.dialogue_failed] is about a
## conversation that could not start or could not continue, and may accompany a
## finish when a continuation was refused mid-way.

## Group this node registers under, and the lookup the interaction component
## performs. Same arrangement as [constant NpcManager.SERVICE_GROUP].
const SERVICE_GROUP := &"dialogue_service"

## Group [NpcManager] registers under, reached only to read hearts for the
## context and to grant them for an effect. Found rather than referenced for
## the reason every component in this codebase documents: naming the manager
## here would invite a cycle the moment the manager wants to open a line of
## its own.
const NPC_SERVICE_GROUP := &"npc_service"

## Who is talking right now, or [code]&""[/code] when no conversation is open.
var _active_npc: StringName = &""
## The line on screen, or null.
var _current: DialogueEntry = null
## The tree the conversation is running out of. Links resolve inside it.
var _current_tree: DialogueTree = null
## npc_id -> { entry_id -> times shown }. Drives `once` and the rotation
## tie-break in [method select]. Persisted: a save that forgot what was shown
## would replay introductions every load.
var _seen: Dictionary = {}
## Story flags raised by dialogue. Names are content-owned; nothing in this
## service interprets them, it only stores and gates on them.
var _flags: Dictionary = {}


func _ready() -> void:
	add_to_group(SERVICE_GROUP)


# --- Opening ---------------------------------------------------------------

## Opens a conversation with [param npc_id] from the registered content.
##
## Returns false and publishes [signal EventBus.dialogue_failed] when there is
## nothing to say — a missing tree or a moment where every line is ruled out.
## The caller (the interaction component) has usually *already* published
## [signal EventBus.npc_talked], because a greeting that happens with no panel
## is still a greeting; the failure is about the conversation, not the hello.
func open(npc_id: StringName) -> bool:
	var tree := DialogueRegistry.tree_for(npc_id)
	if tree == null:
		EventBus.dialogue_failed.emit(npc_id, &"no_tree")
		return false
	return open_tree(tree)


## Opens a conversation from an explicit tree rather than the registry.
##
## Public on purpose: a cutscene, a festival or a test may hold a tree that is
## not (or not yet) registered content, and they should be able to run it
## through the same rules, effects and pairing as everything else.
func open_tree(tree: DialogueTree, ctx_override: Dictionary = {}) -> bool:
	if tree == null or tree.npc_id.is_empty():
		EventBus.dialogue_failed.emit(
			tree.npc_id if tree != null else &"", &"no_tree")
		return false
	var npc_id := tree.npc_id
	# Opening a second conversation closes the first, so the listener that is
	# counting starts against finishes is never left waiting.
	if is_open():
		_finish()
	var seen := _seen_for(npc_id)
	var ctx := build_context(npc_id)
	for key: Variant in ctx_override.keys():
		ctx[key] = ctx_override[key]
	var chosen := select(tree, ctx, seen)
	if chosen == null:
		EventBus.dialogue_failed.emit(npc_id, &"no_matching_entry")
		return false
	_current_tree = tree
	_present(npc_id, chosen, true)
	return true


# --- Running ---------------------------------------------------------------

func is_open() -> bool:
	return not _active_npc.is_empty() and _current != null


func current_npc_id() -> StringName:
	return _active_npc


func current_entry() -> DialogueEntry:
	return _current


## The words to draw right now, or [code]""[/code] when nothing is open.
func current_text() -> String:
	return _current.text if _current != null else ""


## The replies to draw right now; empty when the line continues on advance.
func current_choices() -> Array[DialogueChoice]:
	if _current == null:
		return []
	return _current.choices


## Whether the conversation is waiting for a reply rather than a continue.
func is_awaiting_choice() -> bool:
	return _current != null and _current.has_choices()


## Leaves the current line: applies its effects, then follows its `next` link
## or ends the conversation.
##
## Returns true when another line is now showing, false when the conversation
## is over (or never was). Refusing a stray press — [code]nothing_active[/code]
## — is a failure and says so; a press that lands on a line with replies is a
## failure too ([code]awaiting_choice[/code]), because "the player pressed
## advance while three replies are on screen" means the caller lost track of
## what is showing, and silently advancing would pick for them.
func advance() -> bool:
	if not is_open():
		EventBus.dialogue_failed.emit(_active_npc, &"nothing_active")
		return false
	if _current.has_choices():
		EventBus.dialogue_failed.emit(_active_npc, &"awaiting_choice")
		return false
	var leaving := _current
	var npc_id := _active_npc
	_apply_effects(npc_id, leaving)
	if leaving.next.is_empty():
		_finish()
		return false
	var next_entry := _current_tree.entry(leaving.next) if _current_tree != null else null
	if next_entry == null:
		# Refused at load by the registry; this arm is the belt for a tree
		# mutated after loading. The conversation still owes a close, so it
		# fails *and* finishes — the panel must not hang on a dead link.
		EventBus.dialogue_failed.emit(npc_id, &"bad_reference")
		_finish()
		return false
	_present(npc_id, next_entry)
	return true


## Takes reply [param index] from the line currently showing.
##
## Applies the line's own effects as well as the reply's: the player read the
## line and then spoke, and both happened. A reply with no [member
## DialogueChoice.next] ends the conversation.
func choose(index: int) -> bool:
	if not is_open():
		EventBus.dialogue_failed.emit(_active_npc, &"nothing_active")
		return false
	var entry := _current
	if index < 0 or index >= entry.choices.size():
		EventBus.dialogue_failed.emit(_active_npc, &"bad_choice")
		return false
	var npc_id := _active_npc
	var choice := entry.choices[index]
	_apply_effects(npc_id, entry)
	EventBus.dialogue_choice_taken.emit(npc_id, entry.id, index)
	_apply_effects(npc_id, choice)
	if choice.next.is_empty():
		_finish()
		return false
	var next_entry := _current_tree.entry(choice.next) if _current_tree != null else null
	if next_entry == null:
		EventBus.dialogue_failed.emit(npc_id, &"bad_reference")
		_finish()
		return false
	_present(npc_id, next_entry)
	return true


## Walks away mid-line: ends the conversation without applying the line the
## player never finished reading.
##
## Still answers [signal EventBus.dialogue_finished] — the pairing is about the
## conversation having happened, not about every effect landing. Effects of
## lines already left behind are untouched: they were read and answered.
func cancel() -> void:
	if not is_open():
		return
	_finish()


# --- Context and selection -------------------------------------------------

## Everything a condition can ask about, as one dictionary.
##
## Missing services degrade rather than crash: no clock means the default
## season/weather/hour, no cast means zero hearts. A dialogue system that
## refuses to speak because the weather service is absent would take the whole
## conversation down with one missing node — and every content test runs
## without a clock on purpose.
func build_context(npc_id: StringName) -> Dictionary:
	var ctx := {
		"season": WorldTime.Season.SPRING,
		"weather": WorldTime.Weather.SUN,
		"hour": 12,
		"hearts": 0,
		"flags": _flags.duplicate(),
	}
	var clock := TimeService.find_in_tree()
	if clock != null:
		ctx["season"] = clock.time.season
		ctx["hour"] = clock.time.hour
		ctx["weather"] = clock.get_weather()
	var hearts := _hearts_of(npc_id)
	if hearts >= 0:
		ctx["hearts"] = hearts
	return ctx


## The line to say in [param ctx] out of [param tree], or null.
##
## Most conditions wins; then least-shown wins (rotation); then authored order.
## The one deliberate exception: an unseen `once` line outranks everything that
## matches, because a story beat authored as one-time must not be starved out of
## ever showing by a filler line that happens to have one more condition.
static func select(tree: DialogueTree, ctx: Dictionary, seen: Dictionary) -> DialogueEntry:
	if tree == null:
		return null
	var best: DialogueEntry = null
	var best_score := -1
	var best_seen := 0
	var best_index := -1
	for i: int in tree.entries.size():
		var e := tree.entries[i]
		if e == null:
			continue
		var times := int(seen.get(e.id, 0))
		if e.once and times > 0:
			continue
		if not e.matches(ctx):
			continue
		var score := e.condition_count() + (100 if e.once else 0)
		if best == null or score > best_score \
				or (score == best_score and times < best_seen) \
				or (score == best_score and times == best_seen and i < best_index):
			best = e
			best_score = score
			best_seen = times
			best_index = i
	return best


# --- Remembering -----------------------------------------------------------

## Whether [param flag] was raised by any conversation.
func has_flag(flag: StringName) -> bool:
	return bool(_flags.get(flag, false))


## Raises a flag directly. For story systems that are not a conversation but
## share the same memory — a cutscene that tells the player something should be
## able to gate the same lines a spoken confession does.
func set_flag(flag: StringName, value: bool = true) -> void:
	if value:
		_flags[flag] = true
	else:
		_flags.erase(flag)


## How often [param entry_id] has been shown to [param npc_id].
func times_shown(npc_id: StringName, entry_id: StringName) -> int:
	return int(_seen_for(npc_id).get(entry_id, 0))


func to_dict() -> Dictionary:
	var seen_out := {}
	for npc_id: Variant in _seen:
		var rows := {}
		for entry_id: Variant in _seen[npc_id]:
			rows[entry_id] = int(_seen[npc_id][entry_id])
		seen_out[npc_id] = rows
	var flag_out := {}
	for flag: Variant in _flags:
		flag_out[flag] = true
	return {"seen": seen_out, "flags": flag_out}


## Restores a saved table, clamping rather than trusting: a hand-edited file
## naming a negative count or a non-boolean flag must not reach selection.
func from_dict(data: Dictionary) -> void:
	_seen.clear()
	_flags.clear()
	var seen_in: Variant = data.get("seen", {})
	if seen_in is Dictionary:
		for npc_id: Variant in (seen_in as Dictionary):
			var rows: Dictionary = {}
			var source: Variant = (seen_in as Dictionary)[npc_id]
			if source is Dictionary:
				for entry_id: Variant in source:
					var count := int(source[entry_id])
					if count > 0:
						rows[entry_id] = count
			if not rows.is_empty():
				_seen[npc_id] = rows
	var flags_in: Variant = data.get("flags", {})
	if flags_in is Dictionary:
		for flag: Variant in (flags_in as Dictionary):
			if bool((flags_in as Dictionary)[flag]):
				_flags[flag] = true


# --- Internals -------------------------------------------------------------

## Puts [param entry] on screen for [param npc_id] and announces it.
##
## [param first] splits the announcement: the line that *opens* a conversation
## publishes [signal EventBus.dialogue_started], the lines that follow it
## publish [signal EventBus.dialogue_line_changed], so one conversation is one
## open and one close with repaints in between.
##
## Marks the line shown *here*, on display rather than on close: a player who
## sees the opening of an introduction and walks away has still seen it, and a
## `once` line that required finishing would replay every time someone pressed
## Escape at the first word.
func _present(npc_id: StringName, entry: DialogueEntry, first: bool = false) -> void:
	_active_npc = npc_id
	_current = entry
	var rows := _seen_for(npc_id)
	rows[entry.id] = int(rows.get(entry.id, 0)) + 1
	_seen[npc_id] = rows
	if first:
		EventBus.dialogue_started.emit(npc_id, entry.id)
	else:
		EventBus.dialogue_line_changed.emit(npc_id, entry.id)


func _finish() -> void:
	var npc_id := _active_npc
	var last := _current
	_active_npc = &""
	_current = null
	_current_tree = null
	if last != null:
		EventBus.dialogue_finished.emit(npc_id, last.id)


## Applies hearts and flags from either an entry or a reply — they are the same
## four fields, and one place means a new effect cannot be wired for one and
## forgotten for the other.
func _apply_effects(npc_id: StringName, source: Resource) -> void:
	if source == null:
		return
	var flag_names: Variant = source.get("set_flags")
	if flag_names is Array:
		for flag: Variant in flag_names:
			_flags[flag] = true
	var hearts := int(source.get("hearts"))
	if hearts > 0:
		var manager := _find_by_group(NPC_SERVICE_GROUP)
		if manager != null:
			manager.call("grant_hearts", npc_id, hearts)
		else:
			# Headless content runs have no cast; the hearts are not the point
			# there. A real game always has the manager, so this branch is a
			# missing node worth saying out loud rather than a silent no-op.
			Log.warn("Dialogue", "no NpcManager to grant %d hearts to '%s'" % [
				hearts, npc_id,
			])


func _seen_for(npc_id: StringName) -> Dictionary:
	if not _seen.has(npc_id):
		_seen[npc_id] = {}
	return _seen[npc_id]


## Hearts with [param npc_id] has right now, or -1 when there is no cast to ask.
##
## -1 rather than 0 so a missing manager is not mistaken for "stranger": the
## context builder leaves the default 0 in place only when the answer really is
## zero.
func _hearts_of(npc_id: StringName) -> int:
	var manager := _find_by_group(NPC_SERVICE_GROUP)
	if manager == null:
		return -1
	var npc: Variant = manager.call("get_npc", npc_id)
	if npc == null:
		return -1
	var friendship: Variant = (npc as Object).get("friendship")
	if friendship == null:
		return 0
	return int(friendship.call("hearts"))


func _find_by_group(group: StringName) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search(scene_root, group)


static func _search(node: Node, group: StringName) -> Node:
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _search(child, group)
		if found != null:
			return found
	return null
