extends TestSuite
## TASK-008 (M5) — the conversation: content, the rules, the panel,
## and the one key that starts it.
##
## Covers the four layers in the order they answer questions: the authored words
## ([DialogueTree] and [DialogueRegistry]), the pure choice of which line to say
## ([DialogueService.select]), the rules of a running conversation (open, advance,
## reply, effects, pairing, the save), the panel that draws and pauses it
## ([DialogueUI]), and finally the real interact key in front of a real villager.
##
## ## Why no case here calls `check_*` and branches on the result
##
## `check_true` and its siblings return a `Dictionary`, and an empty dictionary is truthy
## in GDScript. A suite written as `if check_equals(...): return check_equals(...)` therefore
## passes on failure. Every case in this file instead uses a guard — `if wrong: return
## fail(case, "the actual problem")` — which is what the other suites do and which cannot
## pass by accident.
##
## ## Why the refusal vocabulary is written out here
##
## The seven reasons [EventBus.dialogue_failed] documents are duplicated rather than
## read out of the code under test: a vocabulary *derived* from the service cannot fail
## when the service drops a reason, which is the exact change the test exists to catch.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const RECORDER_SCRIPT := "res://tests/helpers/event_recorder.gd"
const DIALOGUE_UI_SCENE := "res://scenes/ui/dialogue_panel.tscn"

## Loaded by path rather than named for construction, for the documented reason:
## `AGENTS.md` warns that naming a manager here pulls its whole dependency chain into
## this file's compile. Types and constants are still referenced directly, exactly as
## `test_quest` does with [QuestService].
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const DIALOGUE_SERVICE_SCRIPT := "res://scripts/dialogue/dialogue_service.gd"

const MIRA := &"mira"
## A villager id nothing claims, for the "unknown villager" refusals.
const GHOST := &"villager_with_no_words_was_ever_authored"

## Every refusal the [EventBus] documents for a conversation, in one list.
##
## Duplicated rather than derived — see the file header.
const REFUSAL_REASONS: Array[StringName] = [
	&"no_service", &"no_tree", &"no_matching_entry", &"nothing_active",
	&"awaiting_choice", &"bad_choice", &"bad_reference",
]

var _rig: Node3D = null
## Every recorder this case opened, so a connection cannot outlive the case that made it.
var _watchers: Array[Dictionary] = []


func is_async() -> bool:
	return true


func setup() -> void:
	_rig = null


func teardown() -> void:
	# Never leave a simulated keypress behind: it outlives the case that made it and the
	# next case's first press arrives already held.
	Input.action_release(InputActions.INTERACT)
	_reset_rig()
	# A panel freed or a case failed while the conversation held the world still must not
	# freeze the rest of the suite.
	if GameState.paused:
		GameState.set_paused(false)


func get_cases() -> Array[StringName]:
	return [
		# --- content --------------------------------------------------------------
		&"every_villager_has_words",
		&"no_two_trees_share_a_villager",
		&"every_dialogue_tree_is_valid",
		&"every_tree_keeps_an_unconditional_fallback",
		&"every_tree_covers_the_day_the_weather_and_the_seasons",
		&"every_reply_points_at_a_line_that_exists",
		&"every_line_has_words_and_no_two_trees_repeat_them",
		&"every_story_beat_grants_a_heart_and_a_flag",
		# --- which line is said ----------------------------------------------------
		&"an_unseen_introduction_outranks_every_matching_line",
		&"the_most_specific_matching_line_wins",
		&"the_least_shown_line_wins_a_tie",
		&"a_spent_introduction_never_comes_back",
		&"a_missing_context_fails_closed",
		&"a_midnight_window_covers_both_ends_of_the_night",
		&"a_tree_with_no_fallback_can_go_quiet",
		# --- the running conversation ---------------------------------------------
		&"a_missing_tree_is_refused_with_its_own_reason",
		&"every_dialogue_refusal_has_its_own_reason",
		&"one_open_is_answered_by_exactly_one_finish",
		&"effects_land_when_the_line_is_left",
		&"a_story_reply_jumps_and_remembers",
		&"the_conversation_memory_survives_a_save_and_reload",
		&"a_corrupt_save_cannot_reach_selection",
		# --- the panel -------------------------------------------------------------
		&"the_dialogue_panel_starts_hidden",
		&"opening_a_line_shows_it_and_pauses_the_world",
		&"the_first_press_finishes_the_line_and_the_second_advances",
		&"replies_hide_the_continue_hint_and_answer_the_number_keys",
		&"walking_away_closes_the_panel",
		&"a_dialogue_panel_freed_while_open_releases_the_pause",
		# --- through the real game -------------------------------------------------
		&"talking_to_a_villager_opens_their_conversation",
		&"a_greeting_without_a_dialogue_service_still_says_hello",
		&"the_dialogue_group_finds_a_live_service",
		&"the_villager_keeps_facing_you_until_the_conversation_ends",
	]


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"every_villager_has_words":
			return await _t_villagers_have_words()
		&"no_two_trees_share_a_villager":
			return await _t_no_duplicate_trees()
		&"every_dialogue_tree_is_valid":
			return await _t_trees_valid()
		&"every_tree_keeps_an_unconditional_fallback":
			return await _t_trees_have_fallback()
		&"every_tree_covers_the_day_the_weather_and_the_seasons":
			return await _t_trees_cover_conditions()
		&"every_reply_points_at_a_line_that_exists":
			return await _t_links_resolve()
		&"every_line_has_words_and_no_two_trees_repeat_them":
			return await _t_lines_are_written()
		&"every_story_beat_grants_a_heart_and_a_flag":
			return await _t_story_beats_pay()
		&"an_unseen_introduction_outranks_every_matching_line":
			return await _t_intro_wins()
		&"the_most_specific_matching_line_wins":
			return await _t_specificity_wins()
		&"the_least_shown_line_wins_a_tie":
			return await _t_rotation_wins()
		&"a_spent_introduction_never_comes_back":
			return await _t_intro_spent()
		&"a_missing_context_fails_closed":
			return await _t_context_fails_closed()
		&"a_midnight_window_covers_both_ends_of_the_night":
			return await _t_midnight_window()
		&"a_tree_with_no_fallback_can_go_quiet":
			return await _t_no_fallback_goes_quiet()
		&"a_missing_tree_is_refused_with_its_own_reason":
			return await _t_missing_tree_refused()
		&"every_dialogue_refusal_has_its_own_reason":
			return await _t_every_refusal_reason()
		&"one_open_is_answered_by_exactly_one_finish":
			return await _t_pairing()
		&"effects_land_when_the_line_is_left":
			return await _t_effects_on_leave()
		&"a_story_reply_jumps_and_remembers":
			return await _t_story_reply()
		&"the_conversation_memory_survives_a_save_and_reload":
			return await _t_save_round_trip()
		&"a_corrupt_save_cannot_reach_selection":
			return await _t_corrupt_save()
		&"the_dialogue_panel_starts_hidden":
			return await _t_panel_starts_hidden()
		&"opening_a_line_shows_it_and_pauses_the_world":
			return await _t_panel_opens_and_pauses()
		&"the_first_press_finishes_the_line_and_the_second_advances":
			return await _t_two_presses_close()
		&"replies_hide_the_continue_hint_and_answer_the_number_keys":
			return await _t_replies_take_number_keys()
		&"walking_away_closes_the_panel":
			return await _t_escape_closes()
		&"a_dialogue_panel_freed_while_open_releases_the_pause":
			return await _t_freed_panel_releases_pause()
		&"talking_to_a_villager_opens_their_conversation":
			return await _t_press_opens_conversation()
		&"a_greeting_without_a_dialogue_service_still_says_hello":
			return await _t_greeting_without_service()
		&"the_dialogue_group_finds_a_live_service":
			return await _t_group_matches()
		&"the_villager_keeps_facing_you_until_the_conversation_ends":
			return await _t_attending_held()
	return fail(case, "no case implementation for %s" % case)


# --- Content --------------------------------------------------------------------


func _t_villagers_have_words() -> Dictionary:
	var c := &"every_villager_has_words"
	var ids: Array[StringName] = []
	for data: NpcData in NpcRegistry.all_npcs():
		ids.append(data.id)
	if ids.size() < 6:
		return fail(c, "only %d villagers are defined at all" % ids.size())
	var gaps := DialogueRegistry.coverage_gaps(ids)
	var missing: Array = gaps.get("missing", [])
	var orphaned: Array = gaps.get("orphaned", [])
	if not missing.is_empty():
		return fail(c, "these villagers have no dialogue: %s" % str(missing))
	if not orphaned.is_empty():
		return fail(c, "these trees belong to nobody: %s" % str(orphaned))
	if DialogueRegistry.all_trees().size() != ids.size():
		return fail(c, "%d trees for %d villagers" % [
			DialogueRegistry.all_trees().size(), ids.size(),
		])
	return succeeded(c, "%d villagers, one tree each" % ids.size())


func _t_no_duplicate_trees() -> Dictionary:
	var c := &"no_two_trees_share_a_villager"
	var duplicates := DialogueRegistry.duplicate_ids()
	if not duplicates.is_empty():
		return fail(c, "more than one file claims: %s" % str(duplicates))
	var claimed: Dictionary = {}
	for tree: DialogueTree in DialogueRegistry.all_trees():
		if claimed.has(tree.npc_id):
			return fail(c, "'%s' has two trees" % tree.npc_id)
		claimed[tree.npc_id] = true
	return succeeded(c, "%d villagers, each claimed once" % claimed.size())


func _t_trees_valid() -> Dictionary:
	var c := &"every_dialogue_tree_is_valid"
	var trees := DialogueRegistry.all_trees()
	if trees.size() < 6:
		return fail(c, "only %d trees loaded" % trees.size())
	for tree: DialogueTree in trees:
		var problem := tree.is_valid()
		if not problem.is_empty():
			return fail(c, "%s: %s" % [tree.npc_id, problem])
	return succeeded(c, "%d trees all valid" % trees.size())


func _t_trees_have_fallback() -> Dictionary:
	var c := &"every_tree_keeps_an_unconditional_fallback"
	for tree: DialogueTree in DialogueRegistry.all_trees():
		if not tree.has_unconditional_entry():
			return fail(c, "%s can be talked out of every line" % tree.npc_id)
	return succeeded(c, "every tree falls back to something that is always true")


func _t_trees_cover_conditions() -> Dictionary:
	var c := &"every_tree_covers_the_day_the_weather_and_the_seasons"
	for tree: DialogueTree in DialogueRegistry.all_trees():
		var has_hour := false
		var has_weather := false
		var has_season := false
		var has_hearts := false
		var has_intro := false
		var has_choices := false
		var intro_flag := StringName("met_" + String(tree.npc_id))
		for e: DialogueEntry in tree.entries:
			if e.hour_from != DialogueEntry.ANY_HOUR:
				has_hour = true
			if e.weather != DialogueEntry.ANY_WEATHER:
				has_weather = true
			if e.season != DialogueEntry.ANY_SEASON:
				has_season = true
			if e.min_hearts >= 0:
				has_hearts = true
			if e.once and e.set_flags.has(intro_flag):
				has_intro = true
			if not e.choices.is_empty():
				has_choices = true
		var missing: Array[String] = []
		if not has_hour:
			missing.append("an hour window")
		if not has_weather:
			missing.append("weather")
		if not has_season:
			missing.append("a season")
		if not has_hearts:
			missing.append("a hearts gate")
		if not has_intro:
			missing.append("a once introduction raising %s" % intro_flag)
		if not has_choices:
			missing.append("replies")
		if not missing.is_empty():
			return fail(c, "%s never says: %s" % [tree.npc_id, ", ".join(missing)])
	return succeeded(c, "every villager covers the day, the sky, the year and the bond")


func _t_links_resolve() -> Dictionary:
	var c := &"every_reply_points_at_a_line_that_exists"
	# Counted independently of `is_valid`, the way the quest suite recounts its own
	# links: the registry refuses a broken tree at load, so a content regression would
	# otherwise only show up as a tree silently missing from the registry.
	for tree: DialogueTree in DialogueRegistry.all_trees():
		for e: DialogueEntry in tree.entries:
			if not e.next.is_empty() and tree.entry(e.next) == null:
				return fail(c, "%s: '%s' advances to missing '%s'" % [
					tree.npc_id, e.id, e.next,
				])
			for choice: DialogueChoice in e.choices:
				if not choice.next.is_empty() and tree.entry(choice.next) == null:
					return fail(c, "%s: reply '%s' on '%s' leads to missing '%s'" % [
						tree.npc_id, choice.text, e.id, choice.next,
					])
	return succeeded(c, "every `next` and every reply target resolves")


func _t_lines_are_written() -> Dictionary:
	var c := &"every_line_has_words_and_no_two_trees_repeat_them"
	var by_text: Dictionary = {}
	for tree: DialogueTree in DialogueRegistry.all_trees():
		for e: DialogueEntry in tree.entries:
			var words := e.text.strip_edges()
			if words.length() < 10:
				return fail(c, "%s: '%s' is only %d characters" % [
					tree.npc_id, e.id, words.length(),
				])
			var lowered := words.to_lower()
			if lowered.contains("todo") or lowered.contains("fixme") \
					or lowered.contains("lorem"):
				return fail(c, "%s: '%s' left a placeholder in: %s" % [
					tree.npc_id, e.id, words,
				])
			if by_text.has(words):
				return fail(c, "%s and %s say the same line: '%s'" % [
					by_text[words], tree.npc_id, words,
				])
			by_text[words] = tree.npc_id
	return succeeded(c, "%d lines, all written and none repeated" % by_text.size())


func _t_story_beats_pay() -> Dictionary:
	var c := &"every_story_beat_grants_a_heart_and_a_flag"
	for tree: DialogueTree in DialogueRegistry.all_trees():
		var found := false
		for e: DialogueEntry in tree.entries:
			for choice: DialogueChoice in e.choices:
				if choice.next.is_empty():
					continue
				var target := tree.entry(choice.next)
				if target == null:
					continue
				found = true
				if target.hearts < 1:
					return fail(c, "%s: reply '%s' leads to '%s', which grants no heart" % [
						tree.npc_id, choice.text, target.id,
					])
				if target.set_flags.is_empty():
					return fail(c, "%s: '%s' grants a heart but raises no flag" % [
						tree.npc_id, target.id,
					])
				if not target.once:
					return fail(c, "%s: '%s' pays out every time it is reached" % [
						tree.npc_id, target.id,
					])
		if not found:
			return fail(c, "%s offers no reply that leads anywhere" % tree.npc_id)
	return succeeded(c, "every branching reply lands on a one-time beat that pays")


# --- Which line is said ----------------------------------------------------------


func _t_intro_wins() -> Dictionary:
	var c := &"an_unseen_introduction_outranks_every_matching_line"
	var tree := DialogueRegistry.tree_for(MIRA)
	if tree == null:
		return fail(c, "Mira has no tree")
	# The harshest moment in the sweep: a snowy 3am at four hearts, where five
	# conditional lines all match. The introduction must still speak first.
	var chosen := DialogueService.select(tree, _ctx(
		WorldTime.Season.WINTER, WorldTime.Weather.SNOW, 3, 4), {})
	if chosen == null:
		return fail(c, "nothing matched at all")
	if chosen.id != &"intro":
		return fail(c, "at a snowy 3am with four hearts, '%s' spoke instead of the introduction" % [
			chosen.id,
		])
	return succeeded(c, "the first meeting always speaks first")


func _t_specificity_wins() -> Dictionary:
	var c := &"the_most_specific_matching_line_wins"
	var tree := _tree(MIRA, [
		_entry(&"any_time"),
		_entry(&"morning", {"from": 6, "to": 10}),
		_entry(&"rainy", {"weather": WorldTime.Weather.RAIN}),
		_entry(&"rainy_morning", {"from": 6, "to": 10, "weather": WorldTime.Weather.RAIN}),
	])
	var chosen := DialogueService.select(tree, _ctx(
		WorldTime.Season.SPRING, WorldTime.Weather.RAIN, 7, 0), {})
	if chosen == null:
		return fail(c, "nothing matched a rainy morning")
	if chosen.id != &"rainy_morning":
		return fail(c, "two conditions lost to the weaker line '%s'" % chosen.id)
	return succeeded(c, "the line written for this exact moment spoke")


func _t_rotation_wins() -> Dictionary:
	var c := &"the_least_shown_line_wins_a_tie"
	var tree := _tree(MIRA, [
		_entry(&"rainy", {"weather": WorldTime.Weather.RAIN}),
		_entry(&"springy", {"season": WorldTime.Season.SPRING}),
	])
	var ctx := _ctx(WorldTime.Season.SPRING, WorldTime.Weather.RAIN, 12, 0)
	var first := DialogueService.select(tree, ctx, {})
	if first == null or first.id != &"rainy":
		return fail(c, "with an even field, authored order did not win: %s" % (
			"nothing" if first == null else first.id))
	var second := DialogueService.select(tree, ctx, {&"rainy": 1})
	if second == null or second.id != &"springy":
		return fail(c, "the line shown once beat the line never shown: %s" % (
			"nothing" if second == null else second.id))
	return succeeded(c, "a tie rotates toward the line the player has not heard")


func _t_intro_spent() -> Dictionary:
	var c := &"a_spent_introduction_never_comes_back"
	var tree := DialogueRegistry.tree_for(MIRA)
	if tree == null:
		return fail(c, "Mira has no tree")
	var seen := {&"intro": 1}
	for season: int in range(4):
		for weather: int in range(5):
			for hour: int in [0, 5, 6, 12, 17, 23]:
				var chosen := DialogueService.select(tree, _ctx(season, weather, hour, 0), seen)
				if chosen == null:
					return fail(c, "season %d weather %d hour %d: the tree fell silent" % [
						season, weather, hour,
					])
				if chosen.id == &"intro":
					return fail(c, "the introduction returned at season %d weather %d hour %d" % [
						season, weather, hour,
					])
	return succeeded(c, "120 moments, and the spent introduction spoke none of them")


func _t_context_fails_closed() -> Dictionary:
	var c := &"a_missing_context_fails_closed"
	var tree := _tree(MIRA, [_entry(&"only_spring", {"season": WorldTime.Season.SPRING})])
	var without := DialogueService.select(tree, {}, {})
	if without != null:
		return fail(c, "a seasonal line matched a context with no season in it")
	var with := DialogueService.select(tree, _ctx(
		WorldTime.Season.SPRING, WorldTime.Weather.SUN, 12, 0), {})
	if with == null:
		return fail(c, "the line did not match the season it asks for")
	return succeeded(c, "a missing key refuses the line rather than accepting it")


func _t_midnight_window() -> Dictionary:
	var c := &"a_midnight_window_covers_both_ends_of_the_night"
	var night := _entry(&"night", {"from": 23, "to": 5})
	for hour: int in [23, 0, 1, 5]:
		if not night.matches(_ctx(WorldTime.Season.SPRING, WorldTime.Weather.SUN, hour, 0)):
			return fail(c, "the night line refuses %d:00" % hour)
	for hour: int in [6, 12, 22]:
		if night.matches(_ctx(WorldTime.Season.SPRING, WorldTime.Weather.SUN, hour, 0)):
			return fail(c, "the night line claims %d:00" % hour)
	return succeeded(c, "23 to 5 is one window covering both ends of the night")


func _t_no_fallback_goes_quiet() -> Dictionary:
	var c := &"a_tree_with_no_fallback_can_go_quiet"
	var tree := _tree(MIRA, [_entry(&"conditional", {"needs": &"never_raised"})])
	if tree.has_unconditional_entry():
		return fail(c, "the tree claims an unconditional line it does not have")
	if tree.fallback_exists_for(_ctx(WorldTime.Season.SPRING, WorldTime.Weather.SUN, 12, 0)):
		return fail(c, "a ruled-out line is still offered")
	if DialogueService.select(tree, _ctx(
		WorldTime.Season.SPRING, WorldTime.Weather.SUN, 12, 0), {}) != null:
		return fail(c, "a line that cannot be said was selected")
	var with_flag := DialogueService.select(tree, _ctx(
		WorldTime.Season.SPRING, WorldTime.Weather.SUN, 12, 0, {&"never_raised": true}), {})
	if with_flag == null:
		return fail(c, "with its condition met the line still would not speak")
	return succeeded(c, "the tree falls silent exactly when it should, and speaks when it should")


# --- The running conversation -----------------------------------------------------


func _t_missing_tree_refused() -> Dictionary:
	var c := &"a_missing_tree_is_refused_with_its_own_reason"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a service")
	var service: DialogueService = built["service"]
	var failed := _recorder(&"dialogue_failed")
	if service.open(GHOST):
		return fail(c, "a villager with no words was given a conversation")
	if failed.count != 1:
		return fail(c, "%d failures for one open" % failed.count)
	if StringName(failed.arg(0)) != GHOST:
		return fail(c, "the failure names '%s'" % str(failed.arg(0)))
	if _fail_reason(failed) != &"no_tree":
		return fail(c, "the refusal was '%s'" % _fail_reason(failed))
	if service.is_open():
		return fail(c, "the refused conversation is somehow open")
	_stop_recorders()
	return succeeded(c, "no words, no conversation, and it says so")


func _t_every_refusal_reason() -> Dictionary:
	var c := &"every_dialogue_refusal_has_its_own_reason"
	var reasons: Array[StringName] = []
	var bus := autoload(&"EventBus")
	var listener := func(_npc_id: StringName, reason: StringName) -> void:
		reasons.append(reason)
	bus.connect(&"dialogue_failed", listener)
	var problem := await _refusal_walk()
	bus.disconnect(&"dialogue_failed", listener)
	_stop_recorders()
	if not problem.is_empty():
		return fail(c, problem)
	if reasons.size() != REFUSAL_REASONS.size():
		return fail(c, "expected %d refusals, saw %d: %s" % [
			REFUSAL_REASONS.size(), reasons.size(), str(reasons),
		])
	var unique: Dictionary = {}
	for reason: StringName in reasons:
		if not REFUSAL_REASONS.has(reason):
			return fail(c, "undocumented reason '%s'" % reason)
		unique[reason] = true
	if unique.size() != reasons.size():
		return fail(c, "two refusals share a reason: %s" % str(reasons))
	return succeeded(c, "seven distinct reasons: %s" % str(reasons))


## Drives every documented refusal exactly once. Returns "" or the first problem.
##
## Runs against two rigs on purpose: `no_service` is the one reason a component
## publishes rather than the service, so the first step greets a villager with no
## conversation node anywhere in the tree, then the rest exercise the service itself.
func _refusal_walk() -> String:
	var village := await _build_village(false)
	if village.is_empty():
		return "could not stand up a village"
	var component: NpcInteractable = village["component"]
	var talked := _recorder(&"npc_talked")
	if not component.interact(village["state"]):
		return "the greeting itself was refused"
	if talked.count != 1:
		return "no_service was reported without the greeting having happened"

	var built := await _build_service()
	if built.is_empty():
		return "could not stand up a service"
	var service: DialogueService = built["service"]
	if service.open(GHOST):
		return "a villager with no words was given a conversation"
	var impossible := _tree(MIRA, [_entry(&"ruled_out", {"needs": &"never_raised"})])
	if service.open_tree(impossible):
		return "a line ruled out by its own conditions opened anyway"
	if service.advance():
		return "advance with nothing open reported another line"
	var choosy := _tree(MIRA, [_entry(&"pick_one", {
		"choices": [{&"text": "Yes, and then some."}],
	})])
	if not service.open_tree(choosy):
		return "the reply line would not open"
	if service.advance():
		return "advancing over replies reported success"
	service.cancel()
	if not service.open(MIRA):
		return "Mira's real tree would not open"
	if service.choose(5):
		return "reply 5 of no replies reported success"
	service.cancel()
	var broken := _tree(MIRA, [_entry(&"dead_link", {
		"next": &"entry_that_does_not_exist",
	})])
	if not service.open_tree(broken):
		return "the line with the dead link would not open"
	if service.advance():
		return "a dead link reported another line"
	return ""


func _t_pairing() -> Dictionary:
	var c := &"one_open_is_answered_by_exactly_one_finish"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a service")
	var service: DialogueService = built["service"]
	var started := _recorder(&"dialogue_started")
	var finished := _recorder(&"dialogue_finished")
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	if started.count != 1 or finished.count != 0:
		return fail(c, "one open announced %d starts and %d finishes" % [
			started.count, finished.count,
		])
	if service.advance():
		return fail(c, "the introduction claimed to continue")
	if finished.count != 1:
		return fail(c, "one advance and %d finishes" % finished.count)
	if not service.open(MIRA):
		return fail(c, "the second conversation would not open")
	if started.count != 2:
		return fail(c, "%d conversations announced for 2 opens" % started.count)
	if not service.open(MIRA):
		return fail(c, "reopening a live conversation was refused")
	if finished.count != 2 or started.count != 3:
		return fail(c, "reopening left %d starts and %d finishes" % [
			started.count, finished.count,
		])
	service.cancel()
	if finished.count != 3:
		return fail(c, "cancel owed a finish and left %d" % finished.count)
	if started.count != finished.count:
		return fail(c, "%d starts against %d finishes" % [started.count, finished.count])
	_stop_recorders()
	return succeeded(c, "three conversations, three closes, nothing hanging")


func _t_effects_on_leave() -> Dictionary:
	var c := &"effects_land_when_the_line_is_left"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var service: DialogueService = built["service"]
	var npc: Npc = built["npc"]
	var beat := _tree(MIRA, [_entry(&"beat", {
		"hearts": 1, "flags": [&"mira_remembers_this"],
	})])
	if not service.open_tree(beat):
		return fail(c, "the beat would not open")
	if service.has_flag(&"mira_remembers_this"):
		return fail(c, "the flag was raised while the line was merely on screen")
	if npc.friendship.hearts() != 0:
		return fail(c, "hearts were granted while the line was merely on screen")
	service.advance()
	if not service.has_flag(&"mira_remembers_this"):
		return fail(c, "leaving the line left the flag unset")
	if npc.friendship.hearts() != 1:
		return fail(c, "leaving the line granted %d hearts" % npc.friendship.hearts())
	if service.is_open():
		return fail(c, "the conversation outlived its last line")
	return succeeded(c, "a line pays out when the player moves past it, not before")


func _t_story_reply() -> Dictionary:
	var c := &"a_story_reply_jumps_and_remembers"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var service: DialogueService = built["service"]
	var npc: Npc = built["npc"]
	# The state a player arrives in after the first meeting: the introduction has been
	# seen and Mira has been met, so the story beat is on offer.
	service.from_dict({
		"seen": {MIRA: {&"intro": 1}},
		"flags": {&"met_mira": true},
	})
	var started := _recorder(&"dialogue_started")
	var finished := _recorder(&"dialogue_finished")
	var changed := _recorder(&"dialogue_line_changed")
	var picked := _recorder(&"dialogue_choice_taken")
	if not service.open(MIRA):
		return fail(c, "the story would not open")
	if service.current_entry() == null or service.current_entry().id != &"story_1":
		return fail(c, "the first beat opened as '%s'" % (
			"nothing" if service.current_entry() == null else service.current_entry().id))
	if not service.is_awaiting_choice():
		return fail(c, "a branching line did not wait for a reply")
	if service.choose(0):
		# Another line is showing; the walk continues below.
		pass
	else:
		return fail(c, "taking the reply ended instead of jumping")
	if StringName(picked.arg(0)) != MIRA or StringName(picked.arg(1)) != &"story_1" \
			or int(picked.arg(2)) != 0:
		return fail(c, "the reply announcement reads %s / %s / %s" % [
			str(picked.arg(0)), str(picked.arg(1)), str(picked.arg(2)),
		])
	if changed.count != 1 or StringName(changed.arg(1)) != &"story_2":
		return fail(c, "the jump repainted %d lines, last '%s'" % [
			changed.count, str(changed.arg(1)),
		])
	if service.current_entry() == null or service.current_entry().id != &"story_2":
		return fail(c, "the second beat is not the one on screen")
	service.advance()
	if not service.has_flag(&"mira_field_secret"):
		return fail(c, "finishing the story raised no flag")
	if npc.friendship.hearts() != 1:
		return fail(c, "finishing the story granted %d hearts" % npc.friendship.hearts())
	if started.count != 1 or finished.count != 1:
		return fail(c, "%d starts and %d finishes for one conversation" % [
			started.count, finished.count,
		])
	_stop_recorders()
	return succeeded(c, "reply 1 jumped to the second beat, and the second beat paid")


func _t_save_round_trip() -> Dictionary:
	var c := &"the_conversation_memory_survives_a_save_and_reload"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a service")
	var service: DialogueService = built["service"]
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	service.advance()
	var saved := service.to_dict()
	service.from_dict(saved)
	if JSON.stringify(service.to_dict()) != JSON.stringify(saved):
		return fail(c, "the service could not read its own save back")
	if service.times_shown(MIRA, &"intro") != 1:
		return fail(c, "the introduction is remembered %d times" % service.times_shown(MIRA, &"intro"))
	if not service.has_flag(&"met_mira"):
		return fail(c, "the flag raised by the introduction was lost")
	if not service.open(MIRA):
		return fail(c, "Mira would not open after the reload")
	if service.current_entry() == null or service.current_entry().id == &"intro":
		return fail(c, "the introduction played a second time after the reload")
	# A *fresh* service — the actual reload — restores to the same state.
	var script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	if script == null:
		return fail(c, "the service script is gone")
	var restored: DialogueService = script.new()
	restored.name = "RestoredDialogueService"
	_rig.add_child(restored)
	await _step(1)
	restored.from_dict(saved)
	if restored.times_shown(MIRA, &"intro") != 1:
		return fail(c, "a fresh service restored the count as %d" % restored.times_shown(MIRA, &"intro"))
	if not restored.has_flag(&"met_mira"):
		return fail(c, "a fresh service lost the flag")
	if JSON.stringify(restored.to_dict()) != JSON.stringify(saved):
		return fail(c, "the restored save does not match the saved one")
	return succeeded(c, "the words already heard and the flags raised come back")


func _t_corrupt_save() -> Dictionary:
	var c := &"a_corrupt_save_cannot_reach_selection"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a service")
	var service: DialogueService = built["service"]
	# A hand-edited file that claims the introduction was shown a negative number of
	# times, and a flag saved as false. Neither may reach selection.
	service.from_dict({
		"seen": {MIRA: {&"intro": -5}},
		"flags": {&"a_lie": false, &"a_truth": true},
	})
	if service.times_shown(MIRA, &"intro") != 0:
		return fail(c, "a negative count was kept as %d" % service.times_shown(MIRA, &"intro"))
	if service.has_flag(&"a_lie"):
		return fail(c, "a flag saved as false was raised")
	if not service.has_flag(&"a_truth"):
		return fail(c, "a flag saved as true was dropped")
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	if service.current_entry() == null or service.current_entry().id != &"intro":
		return fail(c, "the untrusted count spent the introduction anyway")
	return succeeded(c, "the clamps kept a corrupt save from changing what is said")


# --- The panel -------------------------------------------------------------------


func _t_panel_starts_hidden() -> Dictionary:
	var c := &"the_dialogue_panel_starts_hidden"
	var built := await _build_panel()
	if built.is_empty():
		return fail(c, "could not build the panel")
	var panel: CanvasLayer = built["panel"]
	if panel.visible:
		return fail(c, "the panel is on screen before anyone spoke")
	if GameState.paused:
		return fail(c, "the panel paused the world just by existing")
	return succeeded(c, "silent and invisible until a conversation starts")


func _t_panel_opens_and_pauses() -> Dictionary:
	var c := &"opening_a_line_shows_it_and_pauses_the_world"
	var built := await _build_panel()
	if built.is_empty():
		return fail(c, "could not build the panel")
	var service: DialogueService = built["service"]
	var panel: CanvasLayer = built["panel"]
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	# Asserted with no frames awaited: every one of these is written synchronously by
	# the started handler, so none of them depends on how fast this machine draws.
	if not panel.visible:
		return fail(c, "the panel did not appear")
	if not GameState.paused or not tree.paused:
		return fail(c, "the conversation did not stop the world")
	var name_label := panel.get_node_or_null(^"Panel/Column/NameLabel") as Label
	if name_label == null or name_label.text != "Mira":
		return fail(c, "the panel credits '%s'" % (
			"nobody" if name_label == null else name_label.text))
	var full := String(panel.get("_full_text"))
	if full.is_empty() or full != service.current_text():
		return fail(c, "the panel holds '%s' against the service's '%s'" % [
			full, service.current_text(),
		])
	if not bool(panel.get("_typing")):
		return fail(c, "the line arrived all at once instead of being typed")
	var continue_hint := panel.get_node_or_null(^"Panel/Column/Continue") as Label
	if continue_hint != null and continue_hint.visible:
		return fail(c, "the panel hints 'continue' while it is still typing")
	return succeeded(c, "'Mira' is speaking, and the valley is holding still")


func _t_two_presses_close() -> Dictionary:
	var c := &"the_first_press_finishes_the_line_and_the_second_advances"
	var built := await _build_panel()
	if built.is_empty():
		return fail(c, "could not build the panel")
	var service: DialogueService = built["service"]
	var panel: CanvasLayer = built["panel"]
	var text_label := panel.get_node_or_null(^"Panel/Column/TextLabel") as Label
	var continue_hint := panel.get_node_or_null(^"Panel/Column/Continue") as Label
	if text_label == null or continue_hint == null:
		return fail(c, "the generated panel is missing its labels")
	var finished := _recorder(&"dialogue_finished")
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	await _step(1)
	# Press one: the typewriter is unfinished, so the key reads rather than moves on.
	await _tap_key(_interact_key())
	await _step(1)
	if finished.count != 0:
		return fail(c, "the first press ended the conversation instead of finishing the line")
	if not panel.visible:
		return fail(c, "the first press closed the panel")
	var full := String(panel.get("_full_text"))
	if text_label.text != full or full.is_empty():
		return fail(c, "after the press the label holds %d of %d characters" % [
			text_label.text.length(), full.length(),
		])
	if bool(panel.get("_typing")):
		return fail(c, "the line is still typing after the finishing press")
	if not continue_hint.visible:
		return fail(c, "no continue hint once the line is fully readable")
	# Press two: the line is whole, so the same key moves on and the conversation ends.
	await _tap_key(_interact_key())
	await _step(1)
	if finished.count != 1:
		return fail(c, "the second press left the conversation at %d finishes" % finished.count)
	if panel.visible:
		return fail(c, "the panel outlived the conversation")
	if GameState.paused:
		return fail(c, "the panel left the world paused")
	_stop_recorders()
	return succeeded(c, "first key read the line, second key said goodbye")


func _t_replies_take_number_keys() -> Dictionary:
	var c := &"replies_hide_the_continue_hint_and_answer_the_number_keys"
	var built := await _build_panel()
	if built.is_empty():
		return fail(c, "could not build the panel")
	var service: DialogueService = built["service"]
	var panel: CanvasLayer = built["panel"]
	var continue_hint := panel.get_node_or_null(^"Panel/Column/Continue") as Label
	var choices := panel.get_node_or_null(^"Panel/Column/Choices") as VBoxContainer
	if continue_hint == null or choices == null:
		return fail(c, "the generated panel is missing its reply row")
	service.from_dict({
		"seen": {MIRA: {&"intro": 1}},
		"flags": {&"met_mira": true},
	})
	var finished := _recorder(&"dialogue_finished")
	var picked := _recorder(&"dialogue_choice_taken")
	if not service.open(MIRA):
		return fail(c, "the branching line would not open")
	await _step(1)
	if continue_hint.visible:
		return fail(c, "the panel hints 'continue' while replies are on screen")
	if choices.get_child_count() != 2:
		return fail(c, "%d reply buttons for 2 replies" % choices.get_child_count())
	var second := choices.get_child(1) as Button
	if second == null or second.text != "2. I'd rather not know.":
		return fail(c, "reply 2 reads '%s'" % (
			"nothing" if second == null else second.text))
	# The number key selects; it must not take the reply on its own — a menu key that
	# fires on the press that points at the row is how a player skips their own answer.
	await _tap_key(KEY_2)
	await _step(1)
	if int(panel.get("_selected")) != 1:
		return fail(c, "key 2 selected row %d" % int(panel.get("_selected")))
	if picked.count != 0:
		return fail(c, "the selection key already took the reply")
	if not service.is_open():
		return fail(c, "the conversation closed on selection")
	await _tap_key(KEY_ENTER)
	await _step(1)
	if picked.count != 1 or int(picked.arg(2)) != 1:
		return fail(c, "%d replies taken, last index %s" % [picked.count, str(picked.arg(2))])
	if not service.has_flag(&"mira_field_dodged"):
		return fail(c, "the chosen reply raised no flag")
	if finished.count != 1:
		return fail(c, "the reply left the conversation at %d finishes" % finished.count)
	if panel.visible or GameState.paused:
		return fail(c, "the panel did not close after the reply")
	_stop_recorders()
	return succeeded(c, "the second reply was selected by key and taken by key")


func _t_escape_closes() -> Dictionary:
	var c := &"walking_away_closes_the_panel"
	var built := await _build_panel()
	if built.is_empty():
		return fail(c, "could not build the panel")
	var service: DialogueService = built["service"]
	var panel: CanvasLayer = built["panel"]
	var finished := _recorder(&"dialogue_finished")
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	if not GameState.paused:
		return fail(c, "the conversation never paused the world")
	await _tap_key(KEY_ESCAPE)
	await _step(1)
	if finished.count != 1:
		return fail(c, "walking away owed a finish and left %d" % finished.count)
	if service.is_open():
		return fail(c, "the service still considers the conversation open")
	if panel.visible:
		return fail(c, "the panel is still on screen")
	if GameState.paused:
		return fail(c, "walking away left the world paused")
	_stop_recorders()
	return succeeded(c, "one step outside, and the conversation is over")


func _t_freed_panel_releases_pause() -> Dictionary:
	var c := &"a_dialogue_panel_freed_while_open_releases_the_pause"
	var built := await _build_panel()
	if built.is_empty():
		return fail(c, "could not build the panel")
	var service: DialogueService = built["service"]
	var panel: CanvasLayer = built["panel"]
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	if not GameState.paused:
		return fail(c, "the conversation never paused the world")
	# A scene reload mid-sentence: the panel is simply gone.
	panel.free()
	if GameState.paused or tree.paused:
		return fail(c, "a freed panel froze the game forever")
	return succeeded(c, "the panel took its pause with it on the way out")


# --- Through the real game ---------------------------------------------------------


func _t_press_opens_conversation() -> Dictionary:
	var c := &"talking_to_a_villager_opens_their_conversation"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the game")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var component: NpcInteractable = built["component"]
	var npc: Npc = built["npc"]
	var panel: CanvasLayer = built["panel"]
	var service: DialogueService = built["service"]
	var prompt := component.get_prompt(player)
	if not prompt.contains("Talk to Mira"):
		return fail(c, "standing in front of Mira, the prompt says '%s'" % prompt)
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at Mira: %s" % str(focused["why"]))
	var started := _recorder(&"dialogue_started")
	var finished := _recorder(&"dialogue_finished")
	var failed := _recorder(&"dialogue_failed")
	var talked := _recorder(&"npc_talked")
	# The whole loop through the real key: stand in front of a villager, press E, and
	# a conversation opens on her introduction.
	Input.action_press(InputActions.INTERACT)
	await _wait(0.3)
	Input.action_release(InputActions.INTERACT)
	await _step(3)
	if talked.count != 1 or StringName(talked.arg(0)) != MIRA:
		return fail(c, "%d greetings from one press" % talked.count)
	if failed.count != 0:
		return fail(c, "the conversation was refused: '%s'" % _fail_reason(failed))
	if started.count != 1:
		return fail(c, "%d conversations opened from one press" % started.count)
	if StringName(started.arg(0)) != MIRA or StringName(started.arg(1)) != &"intro":
		return fail(c, "the conversation opened on %s / %s" % [
			str(started.arg(0)), str(started.arg(1)),
		])
	if not panel.visible or not GameState.paused:
		return fail(c, "the press did not open and pause")
	var name_label := panel.get_node_or_null(^"Panel/Column/NameLabel") as Label
	if name_label == null or name_label.text != "Mira":
		return fail(c, "the panel credits '%s'" % (
			"nobody" if name_label == null else name_label.text))
	var text_label := panel.get_node_or_null(^"Panel/Column/TextLabel") as Label
	if text_label == null:
		return fail(c, "the generated panel has no TextLabel")
	# First press of the interact key while her line is typing: reads, does not move on.
	await _tap_key(_interact_key())
	await _step(1)
	if finished.count != 0 or not panel.visible:
		return fail(c, "the reading press moved past the line")
	var full := String(panel.get("_full_text"))
	if text_label.text != full or full.is_empty():
		return fail(c, "after the press the label holds %d of %d characters" % [
			text_label.text.length(), full.length(),
		])
	# Second press: advances, the introduction has no follow-up, the conversation ends.
	await _tap_key(_interact_key())
	await _step(1)
	if finished.count != 1:
		return fail(c, "the closing press left %d finishes" % finished.count)
	if panel.visible:
		return fail(c, "the panel outlived the conversation")
	if GameState.paused:
		return fail(c, "the world was never let go")
	if talked.count != 1:
		return fail(c, "the advance presses greeted %d times" % talked.count)
	_stop_recorders()
	return succeeded(c, "'%s', then two keys: read, and gone" % prompt)


func _t_greeting_without_service() -> Dictionary:
	var c := &"a_greeting_without_a_dialogue_service_still_says_hello"
	var built := await _build_village(false)
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var component: NpcInteractable = built["component"]
	var state: Node = built["state"]
	var prompt := component.get_prompt(state)
	if not prompt.contains("Talk to Mira"):
		return fail(c, "the prompt says '%s'" % prompt)
	var talked := _recorder(&"npc_talked")
	var started := _recorder(&"dialogue_started")
	var failed := _recorder(&"dialogue_failed")
	if not component.interact(state):
		return fail(c, "a greeting was refused because no conversation could follow it")
	if talked.count != 1:
		return fail(c, "%d greetings for one press" % talked.count)
	if started.count != 0:
		return fail(c, "a conversation opened with nothing to run it")
	if failed.count != 1:
		return fail(c, "%d failures for one missing service" % failed.count)
	if StringName(failed.arg(0)) != MIRA:
		return fail(c, "the failure names '%s'" % str(failed.arg(0)))
	if _fail_reason(failed) != &"no_service":
		return fail(c, "the refusal was '%s'" % _fail_reason(failed))
	_stop_recorders()
	return succeeded(c, "the hello happened and the missing panel was reported")


func _t_group_matches() -> Dictionary:
	var c := &"the_dialogue_group_finds_a_live_service"
	# The component finds the service by group, and the group is written out on both
	# sides — a literal that drifts is a conversation the player cannot reach with no
	# compile error to say so.
	if NpcInteractable.DIALOGUE_SERVICE_GROUP != DialogueService.SERVICE_GROUP:
		return fail(c, "the component looks for '%s' and the service registers as '%s'" % [
			NpcInteractable.DIALOGUE_SERVICE_GROUP, DialogueService.SERVICE_GROUP,
		])
	if NpcInteractable.DIALOGUE_SERVICE_GROUP == NpcManager.SERVICE_GROUP:
		return fail(c, "the dialogue service and the NPC manager share one group name")
	if NpcInteractable.DIALOGUE_SERVICE_GROUP == NpcInteractable.QUEST_SERVICE_GROUP:
		return fail(c, "the dialogue service and the quest service share one group name")
	# Two constants agreeing is not the same as a lookup working: the component's own
	# finder must return a live, registered service.
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a service")
	var service: DialogueService = built["service"]
	if not service.is_in_group(NpcInteractable.DIALOGUE_SERVICE_GROUP):
		return fail(c, "a live service is not in the group the component searches")
	if NpcInteractable._find_dialogue_service() != service:
		return fail(c, "the component's finder did not return the live service")
	return succeeded(c, "'%s' finds a working service" % NpcInteractable.DIALOGUE_SERVICE_GROUP)


func _t_attending_held() -> Dictionary:
	var c := &"the_villager_keeps_facing_you_until_the_conversation_ends"
	var built := await _build_village(true, true)
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npc"]
	var service: DialogueService = built["service"]
	# Short on purpose: the case is about *when* the release happens, not about the
	# default 1.2 seconds.
	manager.attend_seconds = 0.15
	if not manager.call("talk", npc, built["state"]):
		return fail(c, "the greeting itself was refused")
	if not npc.attending:
		return fail(c, "Mira was not turned to face the player by the greeting")
	if not service.open(MIRA):
		return fail(c, "Mira would not open")
	# Far past the 0.15-second attend: while the panel holds the pause the timer is
	# frozen, so she is still facing the player.
	await _wait(0.5)
	if not npc.attending:
		return fail(c, "she gave up listening while the conversation was still open")
	service.advance()
	if service.is_open():
		return fail(c, "the conversation outlived its last line")
	await _wait(0.5)
	if npc.attending:
		return fail(c, "she is still facing a conversation that ended")
	if GameState.paused:
		return fail(c, "the ended conversation left the world paused")
	return succeeded(c, "held while reading, released once the panel closed")


# --- Fixtures -----------------------------------------------------------------------


## A [DialogueService] alone, for everything about the rules.
func _build_service() -> Dictionary:
	_reset_rig()
	var script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	if script == null:
		return {}
	_ensure_rig()
	var service: DialogueService = script.new()
	service.name = "DialogueService"
	_rig.add_child(service)
	await _step(2)
	if not service.is_in_group(DialogueService.SERVICE_GROUP):
		return {}
	return {"service": service}


## A bag, the whole cast and (optionally) the conversation and the panel — no world,
## no player. The manager places the cast on ready from their own front steps, exactly
## as the game does.
func _build_village(with_service: bool = true, with_ui: bool = false) -> Dictionary:
	_reset_rig()
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	var service_script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	var ui_scene := load(DIALOGUE_UI_SCENE) as PackedScene
	if state_script == null or manager_script == null or ui_scene == null:
		return {}
	if with_service and service_script == null:
		return {}
	_ensure_rig()
	var state: PlayerStateService = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	var service: DialogueService = null
	if with_service:
		service = service_script.new()
		service.name = "DialogueService"
		_rig.add_child(service)
	var panel: CanvasLayer = null
	if with_ui:
		panel = ui_scene.instantiate() as CanvasLayer
		_rig.add_child(panel)
	await _step(4)
	var npc := manager.get_npc(MIRA)
	if npc == null or state.inventory == null:
		return {}
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return {}
	return {
		"state": state,
		"manager": manager,
		"npc": npc,
		"component": component,
		"service": service,
		"panel": panel,
	}


## The conversation and the panel, with no cast, no bag and no world.
##
## Enough for everything the panel draws and everything it pauses: the service is the
## only node it talks to, and the cases that open a conversation here are the cases that
## assert on the panel rather than on the village behind it.
func _build_panel() -> Dictionary:
	_reset_rig()
	var service_script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	var ui_scene := load(DIALOGUE_UI_SCENE) as PackedScene
	if service_script == null or ui_scene == null:
		return {}
	_ensure_rig()
	var service: DialogueService = service_script.new()
	service.name = "DialogueService"
	_rig.add_child(service)
	var panel := ui_scene.instantiate() as CanvasLayer
	if panel == null:
		return {}
	_rig.add_child(panel)
	await _step(3)
	if not service.is_in_group(DialogueService.SERVICE_GROUP):
		return {}
	return {"service": service, "panel": panel}


## The real valley, a real player, the whole cast, the conversation and the panel.
##
## The only arrangement in which the interact key can be asked the question a player
## asks it, which is why the acceptance case uses it rather than the service directly.
func _build_game() -> Dictionary:
	var world_packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	var service_script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	var ui_scene := load(DIALOGUE_UI_SCENE) as PackedScene
	if world_packed == null or player_packed == null or state_script == null \
			or manager_script == null or service_script == null or ui_scene == null:
		return {}
	_reset_rig()
	_ensure_rig()
	var world: WorldRoot = world_packed.instantiate()
	var player: PlayerController = player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)
	player.global_position = world.get_spawn_point()
	var state: PlayerStateService = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	var service: DialogueService = service_script.new()
	service.name = "DialogueService"
	_rig.add_child(service)
	var panel := ui_scene.instantiate() as CanvasLayer
	if panel == null:
		return {}
	_rig.add_child(panel)
	await _step(6)
	var probe := _find_first(player, "InteractionProbe") as InteractionProbe
	var npc := manager.get_npc(MIRA)
	if probe == null or npc == null or state.inventory == null:
		return {}
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return {}
	return {
		"world": world,
		"player": player,
		"probe": probe,
		"state": state,
		"manager": manager,
		"npc": npc,
		"component": component,
		"service": service,
		"panel": panel,
	}


## A tree of synthetic lines, for asking a rule a question the authored content does not
## happen to ask.
func _tree(npc_id: StringName, entries: Array) -> DialogueTree:
	var out := DialogueTree.new()
	out.npc_id = npc_id
	var list: Array[DialogueEntry] = []
	for entry: Variant in entries:
		if entry is DialogueEntry:
			list.append(entry)
	out.entries = list
	return out


## One synthetic line. The option keys read like the fields they set, so a case reads as
## the condition it is about to test rather than as plumbing.
func _entry(id: StringName, opts: Dictionary = {}) -> DialogueEntry:
	var entry := DialogueEntry.new()
	entry.id = id
	entry.text = str(opts.get("text", "An improvised line, written by the case under test."))
	if opts.has("season"):
		entry.season = int(opts["season"])
	if opts.has("weather"):
		entry.weather = int(opts["weather"])
	if opts.has("from"):
		entry.hour_from = int(opts["from"])
	if opts.has("to"):
		entry.hour_to = int(opts["to"])
	if opts.has("hearts"):
		entry.hearts = int(opts["hearts"])
	if opts.has("needs"):
		entry.requires_flag = StringName(str(opts["needs"]))
	if opts.has("next"):
		entry.next = StringName(str(opts["next"]))
	if opts.has("flags"):
		var raised: Array[StringName] = []
		for flag: Variant in opts["flags"]:
			raised.append(StringName(str(flag)))
		entry.set_flags = raised
	if opts.has("choices"):
		var offers: Array[DialogueChoice] = []
		for row: Variant in opts["choices"]:
			if not (row is Dictionary):
				continue
			var data := row as Dictionary
			var choice := DialogueChoice.new()
			# Both key spellings: a case writes `&"text"` and the field is a plain
			# String, and neither may silently produce an untickable reply.
			choice.text = str(data.get(&"text", data.get("text", "")))
			if data.has("next"):
				choice.next = StringName(str(data["next"]))
			if data.has("hearts"):
				choice.hearts = int(data["hearts"])
			offers.append(choice)
		entry.choices = offers
	return entry


## The context [method DialogueService.build_context] would build, spelled out.
func _ctx(season: int, weather: int, hour: int, hearts: int,
		flags: Dictionary = {}) -> Dictionary:
	return {
		"season": season, "weather": weather, "hour": hour,
		"hearts": hearts, "flags": flags,
	}


## The refusal half of a [signal EventBus.dialogue_failed] — argument one, because
## argument zero is the villager.
func _fail_reason(recorder: Object) -> StringName:
	if recorder == null:
		return &""
	var value: Variant = recorder.arg(1)
	if value == null:
		return &""
	return StringName(str(value))


## A recorder watching one [EventBus] signal, so a case can assert on the event rather
## than on a side effect.
func _recorder(signal_name: StringName) -> Object:
	var script := load(RECORDER_SCRIPT) as GDScript
	if script == null:
		return null
	var recorder: Object = script.new()
	recorder.watch(autoload(&"EventBus"), signal_name)
	_watchers.append({
		"bus": autoload(&"EventBus"), "signal": signal_name, "rec": recorder,
	})
	return recorder


func _stop_recorders() -> void:
	for watcher: Dictionary in _watchers:
		watcher["rec"].call("stop", watcher["bus"], watcher["signal"])
	_watchers = []


func _find_first(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := _find_first(child, node_name)
		if found != null:
			return found
	return null


## Puts the player next to [param npc] and aims at [param component].
func _stand_and_focus(
	player: PlayerController, probe: InteractionProbe, npc: Npc, component: NpcInteractable
) -> Dictionary:
	var aim := component.get_aim_point()
	var why := "no direction worked"
	for offset: Vector3 in [
		Vector3(0, 0, 2.2), Vector3(0, 0, -2.2), Vector3(2.2, 0, 0), Vector3(-2.2, 0, 0),
	]:
		player.global_position = Vector3(aim.x + offset.x, 0.2, aim.z + offset.z)
		await _step(4)
		var camera := probe.get_camera()
		if camera == null:
			return {"focused": false, "why": "no active camera in the viewport"}
		var dir := (aim - camera.global_position).normalized()
		player.set_yaw(atan2(-dir.x, -dir.z))
		player.camera_rig.set_pitch(atan2(dir.y, Vector2(dir.x, dir.z).length()))
		await _step(3)
		probe.update_focus()
		if probe.get_focus() == component:
			return {"focused": true, "why": ""}
		if probe.get_focus() == null:
			why = "ray hit nothing while aiming at %s" % npc.name
		else:
			why = "ray stopped at %s instead of %s" % [
				probe.get_focus().name, component.name,
			]
	return {"focused": false, "why": why}


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "DialogueTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	_stop_recorders()
	if _rig != null and is_instance_valid(_rig):
		# `free()` rather than `queue_free()`: the next case builds its own rig, and a
		# freed node's `_exit_tree` is what disconnects the panel from the bus.
		_rig.free()
	_rig = null
	# A case that failed mid-conversation must not freeze the one after it. The panel
	# releases its own pause in `_exit_tree`; this is the belt for a case that took the
	# pause without leaving a panel behind to give it back.
	if GameState.paused:
		GameState.set_paused(false)


func _step(frames: int) -> void:
	# `tree`, not `get_tree()`: a TestSuite is a RefCounted and has none of its own.
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


## Waits for wall-clock time, with a ceiling so a wedged engine fails the case instead
## of hanging the suite.
func _wait(seconds: float, frame_ceiling: int = 900) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline and frames < frame_ceiling:
		await tree.process_frame
		frames += 1


## A real key press and release, delivered as an event.
##
## Real events rather than `Input.action_press`, because the panel reads the raw key —
## the number keys carry no action binding at all, and a held action cannot select a row
## and then take it on the next press.
func _tap_key(code: int) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await tree.process_frame


## The keycode the interact action is bound to right now, read from the InputMap so a
## remap is what the test presses rather than what the test assumed.
func _interact_key() -> int:
	if InputMap.has_action(InputActions.INTERACT):
		for event: InputEvent in InputMap.action_get_events(InputActions.INTERACT):
			if event is InputEventKey:
				var code := (event as InputEventKey).physical_keycode
				if code == 0:
					code = (event as InputEventKey).keycode
				if code != 0:
					return code
	return KEY_E