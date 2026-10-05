extends TestSuite
## Group 15 — Quests: the jobs villagers offer, and what the player owes them.
##
## Covers the five layers in the order they answer questions: content ([QuestData],
## [QuestObjective], [QuestReward] and [QuestRegistry]), the player's answer to a job
## ([QuestProgress]), the rules ([QuestService]), the one key that offers and hands back
## ([NpcInteractable]), and the save.
##
## ## Why no case here calls `check_*` and branches on the result
##
## `check_true` and its siblings return a `Dictionary`, and an empty dictionary is truthy
## in GDScript. A suite written as `if check_equals(...): return check_equals(...)` therefore
## passes on failure. Every case in this file instead uses a guard — `if wrong: return
## fail(case, "the actual problem")` — which is what the other suites do and which cannot
## pass by accident.
##
## ## Why the item funnels are all three of them
##
## A `collect` objective counts things arriving in the bag. "Arriving" has three producers
## in this project — harvesting publishes [signal EventBus.item_added], gathering publishes
## [signal EventBus.resource_collected] and buying publishes
## [signal EventBus.item_purchased] — and a quest system listening to only the first leaves
## the firewood and foundations jobs unfinishable, because wood and stone arrive through
## gathering. `gathering_the_item_moves_the_objective` walks all three for exactly that
## reason.
##
## ## Why every turn-in asserts both halves
##
## A hand-in is items leaving the bag and gold arriving in the purse. Checking the purse
## alone passes a quest system that mints money; checking the bag alone passes a thief.
## Both halves or it is not a test — the same rule the NPC suite follows for gifts.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const RECORDER_SCRIPT := "res://tests/helpers/event_recorder.gd"

## Loaded by path rather than named, for the documented reason: naming [NpcManager] or
## [QuestService] here pulls their whole dependency chain into this file's compile, which
## is the `class_name` cycle trap `AGENTS.md` warns about. `test_npc` does the same.
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const QUEST_SERVICE_SCRIPT := "res://scripts/quest/quest_service.gd"

## The villagers the content names, so every failure message points at a person a reader
## can go and look at rather than at an index.
const MIRA := &"mira"
const BRAM := &"bram"
const FEN := &"fen"
const SABLE := &"sable"
const ODETTE := &"odette"
const HALDA := &"halda"

const MIRA_JOB := &"q_mira_first_harvest"
const BRAM_JOB := &"q_bram_foundations"
const FEN_JOB := &"q_fen_firewood"
const SABLE_JOB := &"q_sable_the_fence"
const ODETTE_JOB := &"q_odette_first_frost"

## A job id nothing claims, for the "unknown quest" refusals.
const GHOST_JOB := &"q_no_such_job_was_ever_authored"
## An item no definition backs, for the reward-authoring checks.
const GHOST_ITEM := &"ghost_item_never_authored"

const PARSNIP := &"parsnip"
const WILD_BERRY := &"wild_berry"
const WOOD := &"wood"
const STONE := &"stone"
const IRON_ORE := &"iron_ore"

## Every refusal the [EventBus] documents for accepting and handing in, in one list.
##
## Duplicated here rather than read out of [QuestService] for the reason the NPC suite
## duplicates its own: a vocabulary *derived* from the code under test cannot fail.
const REFUSAL_REASONS: Array[StringName] = [
	&"unknown_quest", &"already_active", &"already_turned_in", &"on_cooldown",
	&"wrong_villager", &"no_player_state", &"bag_too_full",
	&"objective_incomplete", &"missing_items",
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
	Input.action_release(&"interact")
	_reset_rig()


func get_cases() -> Array[StringName]:
	return [
		# --- content --------------------------------------------------------------
		&"quests_are_on_disk_and_uniquely_named",
		&"no_two_quests_share_an_id",
		&"every_quest_is_valid",
		&"every_giver_has_a_villager",
		&"every_objective_kind_is_authored",
		&"a_delivery_never_names_its_own_giver",
		&"every_reward_names_a_villager_and_items_that_exist",
		&"every_quest_reads_as_english",
		&"an_objective_never_says_woods_or_stones",
		&"an_incomplete_objective_is_not_valid",
		&"a_reward_that_pays_nothing_is_not_valid",
		&"a_quest_paying_a_villager_who_does_not_exist_is_not_valid",
		# --- the objective, asked directly ----------------------------------------
		&"a_collect_needs_the_count_gathered",
		&"a_collect_needs_the_items_still_in_the_bag",
		&"a_delivery_needs_both_the_item_and_the_person",
		&"a_talk_needs_the_conversation",
		&"an_objective_with_an_unknown_kind_is_not_valid",
		# --- the loop -------------------------------------------------------------
		&"a_villager_offers_their_job",
		&"a_quest_can_be_accepted",
		&"the_same_job_cannot_be_taken_twice",
		&"an_unknown_job_cannot_be_accepted",
		&"a_job_that_does_not_fit_in_the_bag_is_refused",
		&"an_unfinished_job_is_not_offered_again",
		&"gathering_the_item_moves_the_objective",
		&"objective_is_the_only_way_to_turn_in",
		&"turning_in_pays_gold_and_takes_the_items",
		&"turning_in_pays_the_item_reward",
		&"turning_in_awards_friendship",
		&"a_reward_never_counts_towards_another_job",
		&"a_delivery_completes_at_its_target",
		&"a_talk_quest_completes_by_asking",
		&"a_quest_cannot_be_handed_to_the_wrong_villager",
		# --- the repeat rules -----------------------------------------------------
		&"a_one_off_quest_is_never_offered_again",
		&"a_weekly_quest_comes_back_after_a_week",
		&"a_weekly_quest_answered_too_soon_is_refused",
		# --- the refusals ---------------------------------------------------------
		&"every_quest_refusal_has_its_own_reason",
		&"a_failed_turn_in_leaves_the_bag_and_the_purse_alone",
		# --- the save -------------------------------------------------------------
		&"the_quest_log_survives_a_save_and_reload",
		&"an_empty_save_invents_no_jobs",
		&"a_finished_one_off_stays_finished_across_a_reload",
		&"a_save_naming_a_job_we_do_not_have_is_kept",
		# --- through the real game ------------------------------------------------
		&"the_prompt_offers_a_job_when_nothing_is_in_hand",
		&"the_prompt_offers_a_hand_in_when_the_objective_is_met",
		&"asking_about_a_job_works_the_real_interact_key",
		&"holding_a_present_still_wins_over_a_job_offer",
		&"the_quest_service_group_matches_the_interactable",
	]


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"quests_are_on_disk_and_uniquely_named":
			return await _t_quests_on_disk()
		&"no_two_quests_share_an_id":
			return await _t_no_duplicate_ids()
		&"every_quest_is_valid":
			return await _t_quests_valid()
		&"every_giver_has_a_villager":
			return await _t_givers_are_villagers()
		&"every_objective_kind_is_authored":
			return await _t_every_kind_authored()
		&"a_delivery_never_names_its_own_giver":
			return await _t_delivery_target_differs()
		&"every_reward_names_a_villager_and_items_that_exist":
			return await _t_reward_targets_exist()
		&"every_quest_reads_as_english":
			return await _t_reads_as_english()
		&"an_objective_never_says_woods_or_stones":
			return await _t_names_no_fake_plurals()
		&"an_incomplete_objective_is_not_valid":
			return await _t_incomplete_objective_invalid()
		&"a_reward_that_pays_nothing_is_not_valid":
			return await _t_empty_reward_invalid()
		&"a_quest_paying_a_villager_who_does_not_exist_is_not_valid":
			return await _t_unknown_giver_reward_invalid()
		&"a_collect_needs_the_count_gathered":
			return await _t_collect_needs_count()
		&"a_collect_needs_the_items_still_in_the_bag":
			return await _t_collect_needs_bag()
		&"a_delivery_needs_both_the_item_and_the_person":
			return await _t_delivery_needs_both()
		&"a_talk_needs_the_conversation":
			return await _t_talk_needs_talk()
		&"an_objective_with_an_unknown_kind_is_not_valid":
			return await _t_unknown_kind_invalid()
		&"a_villager_offers_their_job":
			return await _t_offer_visible()
		&"a_quest_can_be_accepted":
			return await _t_accept()
		&"the_same_job_cannot_be_taken_twice":
			return await _t_accept_twice()
		&"an_unknown_job_cannot_be_accepted":
			return await _t_accept_unknown()
		&"a_job_that_does_not_fit_in_the_bag_is_refused":
			return await _t_accept_bag_full()
		&"an_unfinished_job_is_not_offered_again":
			return await _t_active_not_offered()
		&"gathering_the_item_moves_the_objective":
			return await _t_progress_moves()
		&"objective_is_the_only_way_to_turn_in":
			return await _t_cannot_complete_without_objective()
		&"turning_in_pays_gold_and_takes_the_items":
			return await _t_turn_in_pays()
		&"turning_in_pays_the_item_reward":
			return await _t_turn_in_items()
		&"turning_in_awards_friendship":
			return await _t_turn_in_hearts()
		&"a_reward_never_counts_towards_another_job":
			return await _t_reward_not_progress()
		&"a_delivery_completes_at_its_target":
			return await _t_delivery_flow()
		&"a_talk_quest_completes_by_asking":
			return await _t_talk_flow()
		&"a_quest_cannot_be_handed_to_the_wrong_villager":
			return await _t_wrong_villager()
		&"a_one_off_quest_is_never_offered_again":
			return await _t_once_never_repeats()
		&"a_weekly_quest_comes_back_after_a_week":
			return await _t_weekly_repeats()
		&"a_weekly_quest_answered_too_soon_is_refused":
			return await _t_weekly_too_soon()
		&"every_quest_refusal_has_its_own_reason":
			return await _t_every_reason_reachable()
		&"a_failed_turn_in_leaves_the_bag_and_the_purse_alone":
			return await _t_failed_turn_in_is_atomic()
		&"the_quest_log_survives_a_save_and_reload":
			return await _t_save_round_trip()
		&"an_empty_save_invents_no_jobs":
			return await _t_save_without_quests()
		&"a_finished_one_off_stays_finished_across_a_reload":
			return await _t_save_keeps_one_off_finished()
		&"a_save_naming_a_job_we_do_not_have_is_kept":
			return await _t_save_unknown_job()
		&"the_prompt_offers_a_job_when_nothing_is_in_hand":
			return await _t_prompt_offers()
		&"the_prompt_offers_a_hand_in_when_the_objective_is_met":
			return await _t_prompt_turns_in()
		&"asking_about_a_job_works_the_real_interact_key":
			return await _t_press_accepts()
		&"holding_a_present_still_wins_over_a_job_offer":
			return await _t_gift_still_works()
		&"the_quest_service_group_matches_the_interactable":
			return await _t_group_matches()
	return fail(case, "no case implementation for %s" % case)


# --- Content --------------------------------------------------------------------


func _t_quests_on_disk() -> Dictionary:
	var c := &"quests_are_on_disk_and_uniquely_named"
	var quests := QuestRegistry.all_quests()
	if quests.is_empty():
		return fail(c, "there are no quests at all, so nothing below is testing anything")
	var ids: Array[String] = []
	for data: QuestData in quests:
		if String(data.id).is_empty():
			return fail(c, "a quest with no id: '%s'" % data.title)
		ids.append(String(data.id))
	# Sorted, because a world built twice must offer the same job in the same order or a
	# save lines up against the wrong villager.
	var sorted := ids.duplicate()
	sorted.sort()
	if ids != sorted:
		return fail(c, "the registry is not in a stable order: %s" % ", ".join(ids))
	return succeeded(c, "%d quests, %s" % [quests.size(), ", ".join(ids)])


func _t_no_duplicate_ids() -> Dictionary:
	var c := &"no_two_quests_share_an_id"
	var dupes := QuestRegistry.duplicate_ids()
	if not dupes.is_empty():
		return fail(c, "two files claim the id(s) %s" % ", ".join(dupes))
	# Checked independently of the registry's own bookkeeping, because the registry
	# quietly keeps the first file it saw and logs the second: a bug there would hide
	# exactly the case this is here to catch.
	var seen: Dictionary = {}
	for data: QuestData in QuestRegistry.all_quests():
		if seen.has(data.id):
			return fail(c, "'%s' is reachable twice" % data.id)
		seen[data.id] = true
	return succeeded(c, "no id is claimed twice")


func _t_quests_valid() -> Dictionary:
	var c := &"every_quest_is_valid"
	var quests := QuestRegistry.all_quests()
	var broken: Array[String] = []
	for data: QuestData in quests:
		if not data.is_valid():
			broken.append(String(data.id))
	if not broken.is_empty():
		return fail(c, "%s cannot be completed as authored" % ", ".join(broken))
	if not QuestRegistry.invalid_ids().is_empty():
		return fail(c, "the registry also reports %s" % ", ".join(
			QuestRegistry.invalid_ids()
		))
	return succeeded(c, "all %d jobs are completable" % quests.size())


func _t_givers_are_villagers() -> Dictionary:
	var c := &"every_giver_has_a_villager"
	var givers := QuestRegistry.givers()
	if givers.is_empty():
		return fail(c, "no villager offers any work")
	for giver: Variant in givers.keys():
		var id := StringName(str(giver))
		if not NpcRegistry.has_npc(id):
			return fail(c, "'%s' offers work but is not in the valley" % id)
	# Someone who offers nothing is a villager the player can never be given anything to
	# do, which is worth a sentence rather than a number.
	var silent: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if not givers.has(data.id):
			silent.append(String(data.id))
	return succeeded(c, "%d villagers offer work; %d offer none" % [
		givers.size(), silent.size(),
	])


func _t_every_kind_authored() -> Dictionary:
	var c := &"every_objective_kind_is_authored"
	var used: Dictionary = {}
	for data: QuestData in QuestRegistry.all_quests():
		if data.objective != null:
			used[data.objective.kind] = true
	var missing: Array[String] = []
	for kind: StringName in QuestObjective.KINDS:
		if not used.has(kind):
			missing.append(String(kind))
	if not missing.is_empty():
		return fail(c, "no quest uses the objective kind(s) %s" % ", ".join(missing))
	return succeeded(c, "all %d kinds are in play" % QuestObjective.KINDS.size())


func _t_delivery_target_differs() -> Dictionary:
	var c := &"a_delivery_never_names_its_own_giver"
	var deliveries := 0
	for data: QuestData in QuestRegistry.all_quests():
		if data.objective == null or data.objective.kind != QuestObjective.KIND_DELIVER:
			continue
		deliveries += 1
		# A delivery to the person who asked for it is a collect with two prompts. This
		# is the authoring mistake that otherwise ships as a quest the player can finish
		# in two places.
		if data.objective.target_npc == data.giver:
			return fail(c, "'%s' is a delivery to its own giver %s" % [data.id, data.giver])
		if not NpcRegistry.has_npc(data.objective.target_npc):
			return fail(c, "'%s' is delivered to %s, who is not in the valley" % [
				data.id, data.objective.target_npc,
			])
	if deliveries == 0:
		return fail(c, "no delivery quest exists, so the kind is untested in content")
	return succeeded(c, "%d deliveries, all to somebody else" % deliveries)


func _t_reward_targets_exist() -> Dictionary:
	var c := &"every_reward_names_a_villager_and_items_that_exist"
	for data: QuestData in QuestRegistry.all_quests():
		var reward := data.reward
		if reward == null:
			return fail(c, "'%s' pays nothing at all" % data.id)
		for heart: QuestHeartReward in reward.hearts:
			if heart == null:
				return fail(c, "'%s' pays an empty heart slot" % data.id)
			if not NpcRegistry.has_npc(heart.npc):
				return fail(c, "'%s' pays hearts to %s, who is not in the valley" % [
					data.id, heart.npc,
				])
		for item_id: StringName in reward.items:
			# The legacy quests paid out a `topaz` no registry had ever heard of, which
			# is what this check is for: a reward the player cannot hold is a promise the
			# game cannot keep.
			if not NpcData.is_known_item(item_id):
				return fail(c, "'%s' pays '%s', which nothing produces" % [data.id, item_id])
	return succeeded(c, "every reward names a villager and an item that exist")


func _t_reads_as_english() -> Dictionary:
	var c := &"every_quest_reads_as_english"
	for data: QuestData in QuestRegistry.all_quests():
		if data.title.strip_edges().is_empty():
			return fail(c, "'%s' has no title" % data.id)
		if data.description.strip_edges().is_empty():
			return fail(c, "'%s' has nothing to read when it is offered" % data.id)
		var objective := data.describe_objective()
		if objective.strip_edges().is_empty():
			return fail(c, "'%s' describes its objective as nothing" % data.id)
		# A raw id in a player-facing sentence means something was never authored.
		# `q_mira_first_harvest` in the middle of a prompt is the symptom.
		if objective.find(String(data.id)) >= 0:
			return fail(c, "'%s' shows its own id to the player: '%s'" % [data.id, objective])
		if data.describe_objective().find("_") >= 0:
			return fail(c, "'%s' shows a raw identifier: '%s'" % [data.id, objective])
		# Every villager's name, in the same sentence. The three objective kinds each
		# name somebody — the giver, or the delivery target — and any of them printing a
		# bare id puts a database key in front of the player.
		for who: StringName in [data.giver, data.objective.target_npc]:
			if who.is_empty():
				continue
			if objective.find(String(who)) >= 0:
				return fail(c, "'%s' names the villager '%s' rather than the villager: '%s'" % [
					data.id, who, objective,
				])
		# "to the giver" is the schema's own word. It read fine in a log line next to the
		# name of the person asking, and reads as nothing at all on a journal row, which
		# is the one place the player has to find the villager themselves.
		if objective.to_lower().contains("the giver"):
			return fail(c, "'%s' tells the player to bring it to 'the giver': '%s'" % [
				data.id, objective,
			])
	return succeeded(c, "every job reads as a sentence, and names a villager")


func _t_names_no_fake_plurals() -> Dictionary:
	var c := &"an_objective_never_says_woods_or_stones"
	# Found by playing it, not by reading the code: the tracker said "Bring 20 Woods to
	# Fen". The quest id was right, the count was right, and every automated check passed,
	# because nothing was reading the prose.
	#
	# The cases that matter are the ones where the plural is *not* simply the singular plus
	# an "s" — "Wood" stays "Wood". An earlier draft of this test skipped exactly those,
	# on the reasoning that a noun needing no change cannot be wrong, and so passed against
	# the very bug that prompted it. Nothing here skips: the item's own plural is the only
	# accepted answer, and the +s form is rejected whenever it differs.
	#
	# What this cannot catch: an item whose `plural_name` was never filled in. Then
	# `name_of` and the line agree on "Stones" and there is nothing here to object to —
	# deciding which nouns are mass ones is the author's call, not this lane's. Removing
	# `plural_name` from `stone.tres` leaves the suite green, and it should: that is a
	# content omission to spot in review, not a logic regression to assert against.
	var checked := 0
	for data: QuestData in QuestRegistry.all_quests():
		var objective: QuestObjective = data.objective
		if objective.kind == QuestObjective.KIND_TALK:
			continue
		var item_id := objective.item_id
		if item_id.is_empty():
			continue
		var line := data.describe_objective()
		var singular := QuestReward.item_name(item_id)
		var plural := QuestReward.name_of(item_id, maxi(objective.count, 2))
		var wrong := "%ss" % singular
		# Whole-word on both sides. `find` is useless here: "Wood" is inside "Woods", so
		# the correct line matches the wrong one and the wrong one matches the correct one.
		if not line.contains(" %s " % plural):
			return fail(c, "'%s' should read '%s': '%s'" % [data.id, plural, line])
		if plural != wrong and line.contains(" %s " % wrong):
			return fail(c, "'%s' says '%s' instead of '%s': '%s'" % [data.id, wrong, plural, line])
		checked += 1
	# A vacuous pass is the failure mode that matters: the loop can find nothing to check
	# and still report success, which is what happened the first time this ran.
	if checked < 4:
		return fail(c, "only %d of the item objectives were checked" % checked)
	return succeeded(c, "every job names its nouns correctly, with no invented plural")


func _t_incomplete_objective_invalid() -> Dictionary:
	var c := &"an_incomplete_objective_is_not_valid"
	var headless := QuestObjective.new()
	if headless.is_valid():
		return fail(c, "an objective with no kind is valid")
	headless.kind = QuestObjective.KIND_COLLECT
	headless.item_id = PARSNIP
	# "Bring some parsnips" is not a number an author can mean, so a count below one is
	# refused rather than quietly treated as one.
	headless.count = 0
	if headless.is_valid():
		return fail(c, "a collect for zero of something is valid")
	headless.count = 5
	# A collect that also names a target is two quests in one field.
	headless.target_npc = MIRA
	if headless.is_valid():
		return fail(c, "a collect naming a target is valid")
	return succeeded(c, "half-authored objectives are refused")


func _t_empty_reward_invalid() -> Dictionary:
	var c := &"a_reward_that_pays_nothing_is_not_valid"
	var reward := QuestReward.new()
	if not reward.is_empty():
		return fail(c, "a reward that pays nothing does not say it is empty")
	# "Pays nothing" and "is malformed" are different content bugs and are asked about
	# separately, exactly as [QuestReward.is_empty] documents. A reward of nothing is
	# structurally fine - [QuestData.is_valid] is the one that refuses to ship it.
	reward.gold = -1
	if reward.is_valid():
		return fail(c, "a reward that charges the player is valid")
	reward.gold = 100
	reward.item_amount = 0
	if reward.is_valid():
		return fail(c, "a reward that hands over nothing per item is valid")
	reward.item_amount = 1
	reward.hearts = [null]
	if reward.is_valid():
		return fail(c, "a reward with a hole where a villager should be is valid")
	reward.hearts = []
	reward.gold = 100
	reward.items = [PARSNIP]
	if not reward.is_valid():
		return fail(c, "a reward of 100 gold and a real item is refused")
	# The refusal that matters is the one a quest actually hits: an authored quest paying
	# nothing in any currency is not loadable content.
	var quest := QuestRegistry.get_quest(MIRA_JOB)
	if quest == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	var broke := quest.duplicate(true) as QuestData
	broke.reward = QuestReward.new()
	if broke.is_valid():
		return fail(c, "a quest paying nothing in gold, items or friendship is valid")
	return succeeded(c, "an empty or negative reward is refused")


func _t_unknown_giver_reward_invalid() -> Dictionary:
	var c := &"a_quest_paying_a_villager_who_does_not_exist_is_not_valid"
	var quest := QuestRegistry.get_quest(MIRA_JOB)
	if quest == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	# Authored copy rather than the live resource: a test that edits the loaded quest
	# leaves it edited for every case that follows.
	var broken := quest.duplicate(true) as QuestData
	broken.reward = broken.reward.duplicate(true) as QuestReward
	broken.reward.gold = 0
	broken.reward.items = [GHOST_ITEM]
	broken.reward.item_amount = 1
	broken.reward.hearts = []
	if broken.is_valid():
		return fail(c, "a quest paying '%s' is valid" % GHOST_ITEM)
	broken.reward = broken.reward.duplicate(true) as QuestReward
	broken.reward.items = []
	broken.reward.gold = 0
	var heart := QuestHeartReward.new()
	heart.npc = &"a_villager_who_never_existed"
	heart.amount = 1
	broken.reward.hearts = [heart]
	if broken.is_valid():
		return fail(c, "a quest paying a villager who does not exist is valid")
	return succeeded(c, "rewards naming nothing real are refused")


# --- The objective, asked directly --------------------------------------------


func _t_collect_needs_count() -> Dictionary:
	var c := &"a_collect_needs_the_count_gathered"
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	var progress := QuestProgress.create(MIRA_JOB)
	progress.collected = data.objective.count - 1
	if data.objective.is_satisfied_by(progress, data.objective.count):
		return fail(c, "%d of %d counts as done" % [
			progress.collected, data.objective.count,
		])
	progress.note_item_added(1)
	if not data.objective.is_satisfied_by(progress, data.objective.count):
		return fail(c, "%d of %d does not" % [progress.collected, data.objective.count])
	# The line a journal draws. One of the two numbers being wrong is invisible in the
	# world and obvious here.
	if data.objective.current_amount(progress) != data.objective.count:
		return fail(c, "the journal would read '%s'" % progress.describe(
			data.objective, QuestReward.item_name(data.objective.item_id)
		))
	return succeeded(c, "%d of %d only counts as done at %d" % [
		data.objective.count, data.objective.count, data.objective.count,
	])


func _t_collect_needs_bag() -> Dictionary:
	var c := &"a_collect_needs_the_items_still_in_the_bag"
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	var progress := QuestProgress.create(MIRA_JOB)
	# Everything gathered, none of it left. Counting only what was gathered completes the
	# job having delivered nothing, which is worse than the opposite mistake.
	progress.collected = data.objective.count
	if data.objective.is_satisfied_by(progress, 0):
		return fail(c, "a full tally and an empty bag counts as done")
	if data.objective.is_satisfied_by(progress, data.objective.count - 1):
		return fail(c, "%d of %d in the bag counts as done" % [
			data.objective.count - 1, data.objective.count,
		])
	return succeeded(c, "a gather with nothing left in hand is not done")


func _t_delivery_needs_both() -> Dictionary:
	var c := &"a_delivery_needs_both_the_item_and_the_person"
	var data := QuestRegistry.get_quest(SABLE_JOB)
	if data == null:
		return fail(c, "no %s in the content" % SABLE_JOB)
	var objective := data.objective
	if objective.kind != QuestObjective.KIND_DELIVER:
		return fail(c, "%s is a '%s', not a delivery" % [SABLE_JOB, objective.kind])
	var progress := QuestProgress.create(SABLE_JOB)
	# The item alone is not the delivery — this is the case that makes `spoke_to_target`
	# exist.
	if objective.is_satisfied_by(progress, objective.count):
		return fail(c, "iron ore in the bag is a finished delivery on its own")
	progress.spoke_to_target = true
	if objective.is_satisfied_by(progress, 0):
		return fail(c, "the conversation alone is a finished delivery")
	if not objective.is_satisfied_by(progress, objective.count):
		return fail(c, "the item and the conversation together are not a delivery")
	# Reads 0 of 1 until the conversation, so a journal never claims progress the player
	# has not made.
	if objective.current_amount(progress) != 1:
		return fail(c, "a finished delivery reads %d" % objective.current_amount(progress))
	return succeeded(c, "a delivery needs the thing and the person")


func _t_talk_needs_talk() -> Dictionary:
	var c := &"a_talk_needs_the_conversation"
	var data := QuestRegistry.get_quest(ODETTE_JOB)
	if data == null:
		return fail(c, "no %s in the content" % ODETTE_JOB)
	var objective := data.objective
	if objective.kind != QuestObjective.KIND_TALK:
		return fail(c, "%s is a '%s', not a conversation" % [ODETTE_JOB, objective.kind])
	if not objective.item_id.is_empty():
		return fail(c, "a talk objective carries the item '%s'" % objective.item_id)
	var progress := QuestProgress.create(ODETTE_JOB)
	if objective.is_satisfied_by(progress, 0):
		return fail(c, "a talk objective is done before anyone has spoken")
	progress.spoke_to_target = true
	if not objective.is_satisfied_by(progress, 0):
		return fail(c, "speaking to %s did not finish it" % objective.target_npc)
	if objective.required_amount() != 1:
		return fail(c, "a talk objective wants %d, not one" % objective.required_amount())
	return succeeded(c, "a conversation is the whole of %s" % ODETTE_JOB)


func _t_unknown_kind_invalid() -> Dictionary:
	var c := &"an_objective_with_an_unknown_kind_is_not_valid"
	var objective := QuestObjective.new()
	objective.kind = &"hunt_something_please"
	objective.item_id = PARSNIP
	objective.count = 3
	if objective.is_valid():
		return fail(c, "'hunt_something_please' is a valid objective")
	# The vocabulary is closed, and an unknown kind answers nothing rather than falling
	# through to a satisfied-by-default arm.
	var progress := QuestProgress.create(GHOST_JOB)
	progress.collected = 99
	progress.spoke_to_target = true
	if objective.is_satisfied_by(progress, 99):
		return fail(c, "an unknown kind counts as satisfied")
	if objective.current_amount(progress) != 0:
		return fail(c, "an unknown kind reports progress")
	if objective.describe() != "Nothing to do":
		return fail(c, "an unknown kind describes itself as '%s'" % objective.describe())
	return succeeded(c, "an unauthored objective kind is inert")


# --- The loop ------------------------------------------------------------------


func _t_offer_visible() -> Dictionary:
	var c := &"a_villager_offers_their_job"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var mine: Array[StringName] = []
	for data: QuestData in QuestRegistry.all_quests():
		mine.append(data.id)
		if quests.title_of(data.id) != data.title:
			return fail(c, "'%s' is called '%s' in a prompt" % [
				data.id, quests.title_of(data.id),
			])
		if data.objective.kind == QuestObjective.KIND_TALK \
				or data.objective.kind == QuestObjective.KIND_DELIVER:
			if quests.title_of(data.id).is_empty():
				return fail(c, "%s has no prompt title" % data.id)
	# Each villager is asked what they would like the player to do, and the answer is one
	# of *their* jobs. Not "the first job in the registry": handing Mira Bram's job would
	# make the giver field decorative.
	for giver: Variant in QuestRegistry.givers().keys():
		var id := StringName(str(giver))
		var offered := quests.next_offer_from(id)
		if offered.is_empty():
			return fail(c, "%s has a job and will not mention it" % id)
		if not mine.has(offered):
			return fail(c, "%s offered '%s', which is not one of their jobs" % [id, offered])
	if quests.title_of(GHOST_JOB) != "":
		return fail(c, "an unknown job has a title")
	return succeeded(c, "%d villagers each have a job to offer" % QuestRegistry.givers().size())


func _t_accept() -> Dictionary:
	var c := &"a_quest_can_be_accepted"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var accepted := _recorder(&"quest_accepted")
	var refused := _recorder(&"quest_accepted_failed")
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "accepting %s was refused" % MIRA_JOB)
	if not quests.is_active(MIRA_JOB):
		return fail(c, "%s is not active after being accepted" % MIRA_JOB)
	if quests.next_offer_from(MIRA) == MIRA_JOB:
		return fail(c, "Mira still offers %s after handing it over" % MIRA_JOB)
	if accepted.count != 1:
		return fail(c, "%d quest_accepted events from one acceptance" % accepted.count)
	if refused.count != 0:
		return fail(c, "a successful acceptance published a failure")
	if StringName(accepted.arg(0)) != MIRA_JOB or StringName(accepted.arg(1)) != MIRA:
		return fail(c, "published as '%s' from '%s'" % [
			str(accepted.arg(0)), str(accepted.arg(1)),
		])
	_stop_recorders()
	# Success and failure are different events, which is the one thing the bus forbids
	# anybody from collapsing. If both had fired, the check above would never run.
	if quests.active_quests().size() != 1:
		return fail(c, "%d jobs in hand after accepting one" % quests.active_quests().size())
	return succeeded(c, "%s is in hand" % MIRA_JOB)


func _t_accept_twice() -> Dictionary:
	var c := &"the_same_job_cannot_be_taken_twice"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "the first acceptance was refused")
	var refused := _recorder(&"quest_accepted_failed")
	if quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "the same job was taken twice")
	if refused.count != 1 or StringName(refused.arg(1)) != QuestService.REASON_ALREADY_ACTIVE:
		return fail(c, "refused as '%s'" % str(refused.arg(1)))
	# A refused acceptance leaves no trace: one job in hand, and the tally never moved.
	var progress := quests.get_progress(MIRA_JOB)
	if progress == null or not progress.is_active() or progress.collected != 0:
		return fail(c, "the refusal wrote to the job it refused")
	_stop_recorders()
	return succeeded(c, "the second press is refused as already_active")


func _t_accept_unknown() -> Dictionary:
	var c := &"an_unknown_job_cannot_be_accepted"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var accepted := _recorder(&"quest_accepted")
	var refused := _recorder(&"quest_accepted_failed")
	if quests.accept(GHOST_JOB, built["state"]):
		return fail(c, "a job nobody authored was accepted")
	if quests.get_progress(GHOST_JOB) != null:
		return fail(c, "an invented job was written into the log")
	if refused.count != 1 or StringName(refused.arg(1)) != QuestService.REASON_UNKNOWN_QUEST:
		return fail(c, "refused as '%s'" % str(refused.arg(1)))
	if accepted.count != 0:
		return fail(c, "a refusal published a success")
	_stop_recorders()
	return succeeded(c, "an invented job is refused as unknown_quest")


func _t_accept_bag_full() -> Dictionary:
	var c := &"a_job_that_does_not_fit_in_the_bag_is_refused"
	# A four-slot bag, all four taken. Refused at acceptance rather than at the counter:
	# a job the player can accept and then never finish is a bug they report.
	var built := await _build_service(4)
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var bag: Inventory = built["bag"]
	for tool: StringName in [&"hoe", &"watering_can", &"axe", &"pickaxe"]:
		if bag.add(tool, 1) != 1:
			return fail(c, "could not fill the bag with %s" % tool)
	if bag.free_slot_count() != 0:
		return fail(c, "the bag is not full: %d slots free" % bag.free_slot_count())
	var quests: QuestService = built["quests"]
	var refused := _recorder(&"quest_accepted_failed")
	if quests.accept(BRAM_JOB, built["state"]):
		return fail(c, "accepted a job whose %d %s will not fit" % [
			QuestRegistry.get_quest(BRAM_JOB).objective.count, STONE,
		])
	if StringName(refused.arg(1)) != QuestService.REASON_BAG_TOO_FULL:
		return fail(c, "refused as '%s'" % str(refused.arg(1)))
	if quests.get_progress(BRAM_JOB) != null:
		return fail(c, "a refused job was written into the log")
	_stop_recorders()
	return succeeded(c, "a job that cannot fit is refused up front")


func _t_active_not_offered() -> Dictionary:
	var c := &"an_unfinished_job_is_not_offered_again"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	if quests.next_offer_from(MIRA) != MIRA_JOB:
		return fail(c, "Mira does not start with a job to offer")
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)
	# Halfway through is not finished, and "would you like another job?" while standing in
	# a field holding four parsnips is the question that loses the transaction.
	if quests.next_offer_from(MIRA) != &"":
		return fail(c, "an unfinished job is still on offer: '%s'" % quests.next_offer_from(MIRA))
	if quests.ready_to_turn_in_from(MIRA) != &"":
		return fail(c, "an unfinished job is ready to hand in")
	return succeeded(c, "an unfinished job is neither offered nor payable")


func _t_progress_moves() -> Dictionary:
	var c := &"gathering_the_item_moves_the_objective"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	if not quests.accept(FEN_JOB, built["state"]):
		return fail(c, "could not accept %s" % FEN_JOB)
	var need := QuestRegistry.get_quest(FEN_JOB).objective.count
	var moved := _recorder(&"quest_progress_changed")

	# Three producers of "the player now holds this", all of which have to count. Wood
	# arrives by gathering rather than by harvesting, so a quest system listening only to
	# the harvest signal leaves this job counting nothing at all.
	for funnel: StringName in [&"harvest", &"gather", &"buy"]:
		var before := quests.get_progress(FEN_JOB).collected
		_gather(bag, WOOD, 3, funnel)
		var after := quests.get_progress(FEN_JOB).collected
		if after != before + 3:
			return fail(c, "3 %s arriving by '%s' moved the tally %d -> %d" % [
				WOOD, funnel, before, after,
			])
		if moved.count == 0:
			return fail(c, "no progress event for %s arriving by '%s'" % [WOOD, funnel])
		if StringName(moved.arg(0)) != FEN_JOB:
			return fail(c, "the progress event named '%s'" % str(moved.arg(0)))
		if int(moved.arg(1)) != after or int(moved.arg(2)) != need:
			return fail(c, "published '%d of %d' when the tally is %d" % [
				int(moved.arg(1)), int(moved.arg(2)), after,
			])
	# Enough of the load arrives to finish the job, in one delivery that overshoots it:
	# the tally has to stop at the ask rather than record every log that crossed the
	# counter, which is both what the journal shows and what gets saved.
	_gather(bag, WOOD, need, "gather")
	if quests.get_progress(FEN_JOB).collected != need:
		return fail(c, "the tally went past what was asked for: %d of %d" % [
			quests.get_progress(FEN_JOB).collected, need,
		])
	# Something else entirely leaves it alone.
	_gather(bag, STONE, 4, "gather")
	if quests.get_progress(FEN_JOB).collected != need:
		return fail(c, "stone moved a wood job")
	_stop_recorders()
	return succeeded(c, "all three funnels move the tally, and only up to the ask")


func _t_cannot_complete_without_objective() -> Dictionary:
	var c := &"objective_is_the_only_way_to_turn_in"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var refused := _recorder(&"quest_turned_in_failed")
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)

	# The counter before anything has been gathered.
	if quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "handed in a job with nothing gathered")
	if StringName(refused.arg(2)) != QuestService.REASON_OBJECTIVE_INCOMPLETE:
		return fail(c, "refused as '%s'" % str(refused.arg(2)))

	# The bag is full of parsnips the player already owned. Accepting is not doing.
	_gather_raw(bag, PARSNIP, 5)
	if quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "a bag that already held the answer completed the job")
	var progress := quests.get_progress(MIRA_JOB)
	if progress == null or progress.is_turned_in():
		return fail(c, "a refused hand-in marked the job finished")
	if progress.collected != 0:
		return fail(c, "parsnips the player already held counted as gathered: %d" % progress.collected)
	# Spent again, so the next refusal is about the job rather than about leftovers.
	if bag.remove(PARSNIP, 5) != 5:
		return fail(c, "could not put the pre-owned parsnips back")

	# Gathered, then spent. Two refusals, because the player needs to be told which one
	# happened: "bring me five parsnips" with none gathered is not the same sentence as
	# the same request with all five eaten.
	_gather(bag, PARSNIP, 5, "harvest")
	if bag.remove(PARSNIP, 5) != 5:
		return fail(c, "could not spend the parsnips")
	refused.watch(autoload(&"EventBus"), &"quest_turned_in_failed")
	if quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "handed in a job whose items were spent")
	if StringName(refused.arg(2)) != QuestService.REASON_MISSING_ITEMS:
		return fail(c, "refused as '%s'" % str(refused.arg(2)))

	# Gathered and kept: the same job, the same press, now it pays.
	_gather(bag, PARSNIP, 5, "harvest")
	if not quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "refused a finished job as '%s'" % str(refused.arg(2)))
	if not quests.get_progress(MIRA_JOB).is_turned_in():
		return fail(c, "a paid job is not recorded as finished")
	_stop_recorders()
	return succeeded(c, "three refusals and one payment, all from the same job")


func _t_turn_in_pays() -> Dictionary:
	var c := &"turning_in_pays_gold_and_takes_the_items"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var wallet: Wallet = built["wallet"]
	var data := QuestRegistry.get_quest(BRAM_JOB)
	if data == null:
		return fail(c, "no %s in the content" % BRAM_JOB)
	if not quests.accept(BRAM_JOB, built["state"]):
		return fail(c, "could not accept %s" % BRAM_JOB)
	var need := data.objective.count
	_gather(bag, STONE, need, "gather")
	var gold_before := wallet.gold
	var stone_before := bag.count(STONE)
	var paid := _recorder(&"quest_turned_in")
	if not quests.turn_in(BRAM_JOB, built["state"], BRAM):
		return fail(c, "refused a finished job")
	# Both halves or it is not a test: a purse that grew without the stone leaving is a
	# printing press, and a bag that emptied without the purse growing is a theft.
	if bag.count(STONE) != stone_before - need:
		return fail(c, "the bag went %d -> %d %s, expected to lose %d" % [
			stone_before, bag.count(STONE), STONE, need,
		])
	if wallet.gold != gold_before + data.reward.gold:
		return fail(c, "the purse went %d -> %d, expected +%d" % [
			gold_before, wallet.gold, data.reward.gold,
		])
	if paid.count != 1 or StringName(paid.arg(0)) != BRAM_JOB:
		return fail(c, "published as '%s'" % str(paid.arg(0)))
	_stop_recorders()
	return succeeded(c, "%d %s for %dg" % [need, STONE, data.reward.gold])


func _t_turn_in_items() -> Dictionary:
	var c := &"turning_in_pays_the_item_reward"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(BRAM_JOB)
	if data == null:
		return fail(c, "no %s in the content" % BRAM_JOB)
	if not quests.accept(BRAM_JOB, built["state"]):
		return fail(c, "could not accept %s" % BRAM_JOB)
	_gather(bag, STONE, data.objective.count, "gather")
	var berry_before := bag.count(WILD_BERRY)
	if not quests.turn_in(BRAM_JOB, built["state"], BRAM):
		return fail(c, "refused a finished job")
	var wanted := data.reward.item_amount if not data.reward.distinct_items().is_empty() else 0
	if bag.count(WILD_BERRY) != berry_before + wanted:
		return fail(c, "the bag went %d -> %d %s, expected to gain %d" % [
			berry_before, bag.count(WILD_BERRY), WILD_BERRY, wanted,
		])
	if wanted > 0 and bag.count(WILD_BERRY) > data.reward.item_amount:
		return fail(c, "the reward paid %d %s for one line of content" % [
			bag.count(WILD_BERRY), WILD_BERRY,
		])
	return succeeded(c, "paid %d %s into the bag" % [wanted, WILD_BERRY])


func _t_turn_in_hearts() -> Dictionary:
	var c := &"turning_in_awards_friendship"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	var mira: Npc = built["npcs"][MIRA]
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)
	_gather(bag, PARSNIP, data.objective.count, "harvest")
	var hearts_before := mira.friendship.hearts()
	var moved := _recorder(&"npc_friendship_changed")
	if not quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "refused a finished job")
	var want := 0
	for heart: QuestHeartReward in data.reward.hearts:
		if heart.npc == MIRA:
			want += heart.amount
	if mira.friendship.hearts() != hearts_before + want:
		return fail(c, "%s went %d -> %d hearts, expected +%d" % [
			MIRA, hearts_before, mira.friendship.hearts(), want,
		])
	if want > 0 and moved.count < 1:
		return fail(c, "a friendship change was never published")
	# A reward is paid through the NPC system rather than by editing a Friendship, so
	# the villager the player never met is paid too when the content says so.
	if StringName(moved.arg(0)) == &"" and want > 0:
		return fail(c, "published with no villager named")
	return succeeded(c, "%s gained %d heart(s)" % [MIRA, want])


func _t_reward_not_progress() -> Dictionary:
	var c := &"a_reward_never_counts_towards_another_job"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	if not quests.accept(BRAM_JOB, built["state"]):
		return fail(c, "could not accept %s" % BRAM_JOB)
	# A second job in hand for the same item, so paying one of them has something it
	# could inflate if the payout went through the ordinary "arrived in the bag" funnel.
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)
	_gather(bag, STONE, QuestRegistry.get_quest(BRAM_JOB).objective.count, "gather")
	var arrived := _recorder(&"item_added")
	var moved := _recorder(&"quest_progress_changed")
	if not quests.turn_in(BRAM_JOB, built["state"], BRAM):
		return fail(c, "refused a finished job")
	if bag.count(WILD_BERRY) < 1:
		return fail(c, "the reward did not arrive, so nothing was proven")
	# The payment is not a gathering. A quest that paid itself would let the player buy
	# a job with the reward of the job they just finished and never lift a finger.
	if arrived.count != 0:
		return fail(c, "the payout announced %d arrivals" % arrived.count)
	if moved.count != 0:
		return fail(c, "the payout moved %d objectives" % moved.count)
	if quests.get_progress(MIRA_JOB).collected != 0:
		return fail(c, "the reward inflated %s to %d" % [
			MIRA_JOB, quests.get_progress(MIRA_JOB).collected,
		])
	_stop_recorders()
	return succeeded(c, "paying one job moved no other job")


func _t_delivery_flow() -> Dictionary:
	var c := &"a_delivery_completes_at_its_target"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var npcs: Dictionary = built["npcs"]
	var data := QuestRegistry.get_quest(SABLE_JOB)
	if data == null:
		return fail(c, "no %s in the content" % SABLE_JOB)
	var bram: Npc = npcs[BRAM]
	if not quests.accept(SABLE_JOB, built["state"]):
		return fail(c, "could not accept %s" % SABLE_JOB)
	_gather(bag, IRON_ORE, data.objective.count, "gather")
	# The ore is in the bag and nobody has been spoken to: not a delivery yet.
	if quests.is_ready_to_turn_in(SABLE_JOB):
		return fail(c, "%s is ready before anyone has been spoken to" % SABLE_JOB)
	# Talking to somebody else is not progress either.
	_talk_to(built, npcs[MIRA])
	if quests.is_ready_to_turn_in(SABLE_JOB):
		return fail(c, "speaking to %s finished a delivery to %s" % [MIRA, BRAM])
	_talk_to(built, bram)
	if not quests.is_ready_to_turn_in(SABLE_JOB):
		return fail(c, "speaking to %s did not finish the delivery" % BRAM)
	# Sable is the one who asked, so she is the one who pays.
	if quests.ready_to_turn_in_from(BRAM) == SABLE_JOB:
		return fail(c, "Bram offered to pay for %s" % SABLE_JOB)
	if quests.ready_to_turn_in_from(SABLE) != SABLE_JOB:
		return fail(c, "Sable does not know the job is ready")
	var ore_before := bag.count(IRON_ORE)
	if not quests.turn_in(SABLE_JOB, built["state"], SABLE):
		return fail(c, "refused a finished delivery")
	if bag.count(IRON_ORE) != ore_before - data.objective.count:
		return fail(c, "the ore is still in the bag")
	return succeeded(c, "%s ore reached %s and was paid for by %s" % [
		IRON_ORE, BRAM, SABLE,
	])


func _t_talk_flow() -> Dictionary:
	var c := &"a_talk_quest_completes_by_asking"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var npcs: Dictionary = built["npcs"]
	if not quests.accept(ODETTE_JOB, built["state"]):
		return fail(c, "could not accept %s" % ODETTE_JOB)
	if quests.is_ready_to_turn_in(ODETTE_JOB):
		return fail(c, "%s is ready before anyone has spoken" % ODETTE_JOB)
	# Asking somebody else does not do it.
	_talk_to(built, npcs[SABLE])
	if quests.is_ready_to_turn_in(ODETTE_JOB):
		return fail(c, "speaking to %s finished a job about %s" % [SABLE, HALDA])
	_talk_to(built, npcs[HALDA])
	if not quests.is_ready_to_turn_in(ODETTE_JOB):
		return fail(c, "speaking to %s did not finish it" % HALDA)
	var gold_before: int = built["wallet"].gold
	if not quests.turn_in(ODETTE_JOB, built["state"], ODETTE):
		return fail(c, "refused a finished job")
	# Nothing to take out of the bag, because nothing was ever put in it.
	if not bag.is_empty():
		return fail(c, "a conversation took something: %s" % bag.summary())
	if int(built["wallet"].gold) <= gold_before:
		return fail(c, "the purse did not move")
	return succeeded(c, "asking %s paid out with nothing taken" % HALDA)


func _t_wrong_villager() -> Dictionary:
	var c := &"a_quest_cannot_be_handed_to_the_wrong_villager"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)
	_gather(bag, PARSNIP, data.objective.count, "harvest")
	var gold_before: int = built["wallet"].gold
	var refused := _recorder(&"quest_turned_in_failed")
	# A bystander takes no delivery. Without the villager being passed in, this check does
	# not happen at all and the job can be handed to whoever the player walked past.
	if quests.turn_in(MIRA_JOB, built["state"], FEN):
		return fail(c, "%s paid %s for Mira's job" % [FEN, MIRA])
	if StringName(refused.arg(2)) != QuestService.REASON_WRONG_VILLAGER:
		return fail(c, "refused as '%s'" % str(refused.arg(2)))
	if not quests.get_progress(MIRA_JOB).is_active():
		return fail(c, "a refused hand-in finished the job anyway")
	if int(built["wallet"].gold) != gold_before:
		return fail(c, "a refused hand-in paid the player")
	if bag.count(PARSNIP) != data.objective.count:
		return fail(c, "a refused hand-in took the parsnips")
	# Empty is "don't care", which is what the service's own callers use.
	if not quests.turn_in(MIRA_JOB, built["state"]):
		return fail(c, "the real giver was refused as '%s'" % str(refused.arg(2)))
	_stop_recorders()
	return succeeded(c, "a bystander takes nothing, the giver pays")


# --- The repeat rules ---------------------------------------------------------


func _t_once_never_repeats() -> Dictionary:
	var c := &"a_one_off_quest_is_never_offered_again"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	if data.repeats_forever():
		return fail(c, "%s is marked repeatable" % MIRA_JOB)
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)
	_gather(bag, PARSNIP, data.objective.count, "harvest")
	if not quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "refused a finished job")
	# No amount of waiting brings it back.
	for _day: int in range(QuestProgress.WEEKLY_INTERVAL_DAYS * 3):
		_day_rolls()
	if quests.next_offer_from(MIRA) == MIRA_JOB:
		return fail(c, "a one-off job came back after %d days" % (
			QuestProgress.WEEKLY_INTERVAL_DAYS * 3
		))
	var refused := _recorder(&"quest_accepted_failed")
	if quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "a one-off job was taken again")
	if StringName(refused.arg(1)) != QuestService.REASON_ALREADY_TURNED_IN:
		return fail(c, "refused as '%s', not already_turned_in" % str(refused.arg(1)))
	# "Finished for good" and "not until next week" are two sentences, and a player who
	# is told the wrong one either waits a week for nothing or gives up on the job.
	if quests.get_progress(MIRA_JOB).turn_ins != 1:
		return fail(c, "the hand-in was counted %d times" % quests.get_progress(MIRA_JOB).turn_ins)
	_stop_recorders()
	return succeeded(c, "%s stays finished" % MIRA_JOB)


func _t_weekly_repeats() -> Dictionary:
	var c := &"a_weekly_quest_comes_back_after_a_week"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(ODETTE_JOB)
	if data == null:
		return fail(c, "no %s in the content" % ODETTE_JOB)
	if not data.repeats_forever():
		return fail(c, "%s is not marked repeatable, so this proves nothing" % ODETTE_JOB)
	if not quests.accept(ODETTE_JOB, built["state"]):
		return fail(c, "could not accept %s" % ODETTE_JOB)
	_talk_to(built, null)
	if not quests.turn_in(ODETTE_JOB, built["state"], ODETTE):
		return fail(c, "refused a finished job")
	var turn_ins := quests.get_progress(ODETTE_JOB).turn_ins
	# One day short of the week, still nothing: a cooldown that is off by one is a job
	# that is offered on the wrong day forever.
	for day: int in range(QuestProgress.WEEKLY_INTERVAL_DAYS - 1):
		_day_rolls()
		if quests.next_offer_from(ODETTE) == ODETTE_JOB:
			return fail(c, "the job came back %d days early" % (day + 1))
	if quests.next_offer_from(ODETTE) == ODETTE_JOB:
		return fail(c, "the job came back %d days early" % (QuestProgress.WEEKLY_INTERVAL_DAYS - 1))
	_day_rolls()
	if quests.next_offer_from(ODETTE) != ODETTE_JOB:
		return fail(c, "the job did not come back after %d days" % QuestProgress.WEEKLY_INTERVAL_DAYS)
	if not quests.accept(ODETTE_JOB, built["state"]):
		return fail(c, "could not take the job back")
	var progress := quests.get_progress(ODETTE_JOB)
	# A streak, not a fresh start: `turn_ins` is the player's history with this job.
	if progress.turn_ins != turn_ins:
		return fail(c, "the hand-in count restarted at %d" % progress.turn_ins)
	if progress.collected != 0 or progress.spoke_to_target:
		return fail(c, "the second run inherited the first one's progress")
	if progress.days_since_turn_in != -1:
		return fail(c, "the second run inherited a cooldown of %d" % (
			progress.days_since_turn_in
		))
	if not progress.is_active():
		return fail(c, "the second run is not active")
	return succeeded(c, "back on day %d, with the streak intact" % QuestProgress.WEEKLY_INTERVAL_DAYS)


func _t_weekly_too_soon() -> Dictionary:
	var c := &"a_weekly_quest_answered_too_soon_is_refused"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	if not quests.accept(ODETTE_JOB, built["state"]):
		return fail(c, "could not accept %s" % ODETTE_JOB)
	_talk_to(built, null)
	if not quests.turn_in(ODETTE_JOB, built["state"], ODETTE):
		return fail(c, "refused a finished job")
	var refused := _recorder(&"quest_accepted_failed")
	if quests.accept(ODETTE_JOB, built["state"]):
		return fail(c, "took a weekly job the day after finishing it")
	if StringName(refused.arg(1)) != QuestService.REASON_ON_COOLDOWN:
		return fail(c, "refused as '%s'" % str(refused.arg(1)))
	# The refusal must not have reopened the job behind the player's back. Resetting
	# before checking the bag would leave them holding a job they had already finished.
	var progress := quests.get_progress(ODETTE_JOB)
	if not progress.is_turned_in() or progress.turn_ins != 1:
		return fail(c, "the refused acceptance reopened the job: state '%s', %d hand-ins" % [
			progress.state, progress.turn_ins,
		])
	if quests.is_active(ODETTE_JOB):
		return fail(c, "the refused acceptance made the job active")
	if quests.is_ready_to_turn_in(ODETTE_JOB):
		return fail(c, "the refused acceptance left the job payable")
	_stop_recorders()
	return succeeded(c, "on_cooldown, and the finished job stays finished")


# --- The refusals -------------------------------------------------------------


func _t_every_reason_reachable() -> Dictionary:
	var c := &"every_quest_refusal_has_its_own_reason"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var npcs: Dictionary = built["npcs"]
	var state: Node = built["state"]
	var bus := autoload(&"EventBus")
	var recorder := _recorder(&"quest_turned_in_failed")
	var accepted_failures := _recorder(&"quest_accepted_failed")
	var seen: Dictionary = {}

	# unknown_quest: a job nobody authored, on both doors.
	quests.turn_in(GHOST_JOB, state, MIRA)
	if _reason(recorder) != QuestService.REASON_UNKNOWN_QUEST:
		return fail(c, "an unknown hand-in was refused as '%s'" % _reason(recorder))
	seen[QuestService.REASON_UNKNOWN_QUEST] = true
	quests.accept(GHOST_JOB, state)
	if StringName(accepted_failures.arg(1)) != QuestService.REASON_UNKNOWN_QUEST:
		return fail(c, "an unknown job was refused as '%s'" % str(accepted_failures.arg(1)))
	seen[QuestService.REASON_UNKNOWN_QUEST] = true

	# no_player_state: no bag anywhere in the tree to take the items out of. The service
	# is asked without a state of its own, so it has to fall back to the tree and find
	# nothing there.
	quests.player_state = null
	var seat := state.get_parent()
	if seat == null:
		return fail(c, "the player state was never in the tree")
	seat.remove_child(state)
	await _step(1)
	quests.accept(MIRA_JOB, null)
	seat.add_child(state)
	await _step(1)
	if StringName(accepted_failures.arg(1)) != QuestService.REASON_NO_PLAYER_STATE:
		return fail(c, "a job with no bag was refused as '%s'" % str(accepted_failures.arg(1)))
	seen[QuestService.REASON_NO_PLAYER_STATE] = true

	# already_active: the same job twice.
	if not quests.accept(MIRA_JOB, state):
		return fail(c, "could not accept %s" % MIRA_JOB)
	quests.accept(MIRA_JOB, state)
	if StringName(accepted_failures.arg(1)) != QuestService.REASON_ALREADY_ACTIVE:
		return fail(c, "a second acceptance was refused as '%s'" % str(accepted_failures.arg(1)))
	seen[QuestService.REASON_ALREADY_ACTIVE] = true

	# objective_incomplete: at the counter with nothing gathered.
	quests.turn_in(MIRA_JOB, state, MIRA)
	if _reason(recorder) != QuestService.REASON_OBJECTIVE_INCOMPLETE:
		return fail(c, "an unfinished job was refused as '%s'" % _reason(recorder))
	seen[QuestService.REASON_OBJECTIVE_INCOMPLETE] = true

	# missing_items: gathered, then spent. A different sentence for the player.
	_gather(bag, PARSNIP, QuestRegistry.get_quest(MIRA_JOB).objective.count, "harvest")
	if bag.remove(PARSNIP, QuestRegistry.get_quest(MIRA_JOB).objective.count) < 1:
		return fail(c, "could not spend the parsnips")
	quests.turn_in(MIRA_JOB, state, MIRA)
	if _reason(recorder) != QuestService.REASON_MISSING_ITEMS:
		return fail(c, "a job whose items were spent was refused as '%s'" % _reason(recorder))
	seen[QuestService.REASON_MISSING_ITEMS] = true

	# wrong_villager: a bystander.
	_gather(bag, PARSNIP, QuestRegistry.get_quest(MIRA_JOB).objective.count, "harvest")
	quests.turn_in(MIRA_JOB, state, FEN)
	if _reason(recorder) != QuestService.REASON_WRONG_VILLAGER:
		return fail(c, "a bystander was refused as '%s'" % _reason(recorder))
	seen[QuestService.REASON_WRONG_VILLAGER] = true

	# already_turned_in: pay a one-off and come back for seconds.
	if not quests.turn_in(MIRA_JOB, state, MIRA):
		return fail(c, "refused a finished job as '%s'" % _reason(recorder))
	quests.accept(MIRA_JOB, state)
	if StringName(accepted_failures.arg(1)) != QuestService.REASON_ALREADY_TURNED_IN:
		return fail(c, "a finished one-off was refused as '%s'" % str(accepted_failures.arg(1)))
	seen[QuestService.REASON_ALREADY_TURNED_IN] = true

	# on_cooldown: a weekly job the day after. A delivery, so it needs both halves of the
	# objective - the ore in the bag *and* the conversation with the person it is for.
	if not quests.accept(SABLE_JOB, state):
		return fail(c, "could not accept %s" % SABLE_JOB)
	var delivery := QuestRegistry.get_quest(SABLE_JOB).objective
	_gather(bag, delivery.item_id, delivery.count, "gather")
	_talk_to(built, npcs[BRAM])
	if not quests.turn_in(SABLE_JOB, state, SABLE):
		return fail(c, "could not hand in %s as '%s'" % [SABLE_JOB, _reason(recorder)])
	quests.accept(SABLE_JOB, state)
	if StringName(accepted_failures.arg(1)) != QuestService.REASON_ON_COOLDOWN:
		return fail(c, "a job on cooldown was refused as '%s'" % str(accepted_failures.arg(1)))
	seen[QuestService.REASON_ON_COOLDOWN] = true

	# bag_too_full: a four-slot bag, full, asked for a job needing room.
	var narrow := QuestService.new()
	narrow.name = "NarrowQuestService"
	_rig.add_child(narrow)
	var small := PlayerStateService.new()
	small.name = "SmallState"
	small.bag_slots = 4
	_rig.add_child(small)
	narrow.player_state = small
	for tool: StringName in [&"hoe", &"watering_can", &"axe", &"pickaxe"]:
		if small.inventory.add(tool, 1) != 1:
			return fail(c, "could not fill the small bag with %s" % tool)
	accepted_failures.watch(bus, &"quest_accepted_failed")
	if narrow.accept(BRAM_JOB, small):
		return fail(c, "a job needing room was accepted into a full bag")
	if StringName(accepted_failures.arg(1)) != QuestService.REASON_BAG_TOO_FULL:
		return fail(c, "a full bag was refused as '%s'" % str(accepted_failures.arg(1)))
	seen[QuestService.REASON_BAG_TOO_FULL] = true

	var missing: Array[String] = []
	for reason: StringName in REFUSAL_REASONS:
		if not seen.has(reason):
			missing.append(String(reason))
	if not missing.is_empty():
		return fail(c, "documented but never produced: %s" % ", ".join(missing))
	# Every reason is a distinct word, which is the whole point of enumerating them.
	var words: Dictionary = {}
	for reason: StringName in REFUSAL_REASONS:
		if words.has(reason):
			return fail(c, "'%s' is listed twice" % reason)
		words[reason] = true
	_stop_recorders()
	return succeeded(c, "all %d refusal reasons are distinct and reachable" % REFUSAL_REASONS.size())


func _t_failed_turn_in_is_atomic() -> Dictionary:
	var c := &"a_failed_turn_in_leaves_the_bag_and_the_purse_alone"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var wallet: Wallet = built["wallet"]
	var state: Node = built["state"]
	var npcs: Dictionary = built["npcs"]
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	var need := data.objective.count
	if not quests.accept(MIRA_JOB, state):
		return fail(c, "could not accept %s" % MIRA_JOB)
	var gold_before := wallet.gold
	var hearts_before: int = (npcs[MIRA] as Npc).friendship.hearts()

	# One refusal at a time, with the whole world watched across all of them: one of them
	# taking the parsnips while paying nothing is the bug this exists to catch.
	var refused := _recorder(&"quest_turned_in_failed")

	# Nothing gathered, everything else perfect.
	bag.set_contents([])
	if quests.turn_in(MIRA_JOB, state, MIRA):
		return fail(c, "a hand-in with nothing gathered was paid")
	if StringName(refused.arg(2)) != QuestService.REASON_OBJECTIVE_INCOMPLETE:
		return fail(c, "refused as '%s'" % str(refused.arg(2)))

	# Gathered, then spent. The same refusal from the opposite direction.
	_gather(bag, PARSNIP, need, "harvest")
	if bag.remove(PARSNIP, need) != need:
		return fail(c, "could not spend the parsnips")
	if quests.turn_in(MIRA_JOB, state, MIRA):
		return fail(c, "a hand-in with nothing in the bag was paid")
	if StringName(refused.arg(2)) != QuestService.REASON_MISSING_ITEMS:
		return fail(c, "refused as '%s'" % str(refused.arg(2)))

	# Gathered, kept, and offered to a bystander.
	_gather(bag, PARSNIP, need, "harvest")
	if quests.turn_in(MIRA_JOB, state, FEN):
		return fail(c, "a bystander was paid for Mira's job")
	if StringName(refused.arg(2)) != QuestService.REASON_WRONG_VILLAGER:
		return fail(c, "refused as '%s'" % str(refused.arg(2)))

	# Nothing about the world moved across three refusals.
	if bag.count(PARSNIP) != need:
		return fail(c, "a refused hand-in took the parsnips: %d left" % bag.count(PARSNIP))
	if wallet.gold != gold_before:
		return fail(c, "the purse went %d -> %d" % [gold_before, wallet.gold])
	if (npcs[MIRA] as Npc).friendship.hearts() != hearts_before:
		return fail(c, "%s gained a heart for a hand-in that never happened" % MIRA)
	if not quests.get_progress(MIRA_JOB).is_active():
		return fail(c, "a refused hand-in finished the job")
	if quests.next_offer_from(MIRA) == MIRA_JOB:
		return fail(c, "a refused hand-in put the job back on offer")
	# And the job is still finishable, so a refusal is not a dead end.
	if not quests.turn_in(MIRA_JOB, state, MIRA):
		return fail(c, "the job could not be finished afterwards")
	_stop_recorders()
	return succeeded(c, "three refusals moved nothing, and the job was still finishable")


# --- The save -----------------------------------------------------------------


func _t_save_round_trip() -> Dictionary:
	var c := &"the_quest_log_survives_a_save_and_reload"
	var built := await _build_village()
	if built.is_empty():
		return fail(c, "could not stand up a village")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var state: Node = built["state"]
	# Two jobs, one of each interesting shape: half-gathered, and finished.
	if not quests.accept(MIRA_JOB, state):
		return fail(c, "could not accept %s" % MIRA_JOB)
	if not quests.accept(SABLE_JOB, state):
		return fail(c, "could not accept %s" % SABLE_JOB)
	_gather(bag, PARSNIP, 3, "harvest")
	_talk_to(built, (built["npcs"] as Dictionary)[BRAM])
	_talk_to(built, (built["npcs"] as Dictionary)[HALDA])
	var saved: Dictionary = quests.to_dict()
	if saved.size() != 2:
		return fail(c, "the save holds %d jobs" % saved.size())

	var reloaded: QuestService = QuestService.new()
	reloaded.name = "ReloadedQuestService"
	_rig.add_child(reloaded)
	reloaded.player_state = state
	reloaded.from_dict(saved)
	var mira := reloaded.get_progress(MIRA_JOB)
	if mira == null or not mira.is_active():
		return fail(c, "%s did not survive" % MIRA_JOB)
	if mira.collected != 3:
		return fail(c, "%s came back at %d gathered" % [MIRA_JOB, mira.collected])
	var sable := reloaded.get_progress(SABLE_JOB)
	if sable == null or not sable.spoke_to_target:
		return fail(c, "the delivery conversation did not survive")
	# Keyed by id rather than by position, so a job added next month cannot silently
	# reassign the player's progress to a different quest.
	if not saved.has(MIRA_JOB) or not saved.has(SABLE_JOB):
		return fail(c, "the save is keyed by something other than the job id")
	if reloaded.active_quests().size() != 2:
		return fail(c, "%d jobs in hand after the reload" % reloaded.active_quests().size())
	# A loaded job is not a finished job, and must not be payable for nothing.
	if reloaded.is_ready_to_turn_in(SABLE_JOB):
		return fail(c, "a reloaded delivery is ready with no ore in the bag")
	return succeeded(c, "two jobs, both shapes, both still true")


func _t_save_without_quests() -> Dictionary:
	var c := &"an_empty_save_invents_no_jobs"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	# A save from before this feature existed has no quest section at all. Loading it
	# must mean "no jobs", not "every job".
	quests.from_dict({})
	if quests.to_dict().size() != 0:
		return fail(c, "an empty save invented %d jobs" % quests.to_dict().size())
	if quests.active_quests().size() != 0:
		return fail(c, "%d jobs appeared from nothing" % quests.active_quests().size())
	if quests.next_offer_from(MIRA) != MIRA_JOB:
		return fail(c, "an empty save changed what Mira offers")
	# A job that never existed must not be resurrected by a save either.
	quests.from_dict({"nonsense": 4, MIRA_JOB: "not a dictionary"})
	if quests.to_dict().size() != 0:
		return fail(c, "a malformed save loaded %d entries" % quests.to_dict().size())
	_stop_recorders()
	return succeeded(c, "nothing loaded from nothing")


func _t_save_keeps_one_off_finished() -> Dictionary:
	var c := &"a_finished_one_off_stays_finished_across_a_reload"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	if not quests.accept(MIRA_JOB, built["state"]):
		return fail(c, "could not accept %s" % MIRA_JOB)
	_gather(bag, PARSNIP, data.objective.count, "harvest")
	if not quests.turn_in(MIRA_JOB, built["state"], MIRA):
		return fail(c, "refused a finished job")
	var saved: Dictionary = quests.to_dict()

	var reloaded: QuestService = QuestService.new()
	reloaded.name = "ReloadedQuestService"
	_rig.add_child(reloaded)
	reloaded.player_state = built["state"]
	reloaded.from_dict(saved)
	var progress := reloaded.get_progress(MIRA_JOB)
	# Kept rather than deleted, so the journal can still say so and a one-off stays
	# finished across a reload. A save that un-finishes a paid job is a duplication bug.
	if progress == null or not progress.is_turned_in():
		return fail(c, "%s came back as '%s'" % [MIRA_JOB, progress.state if progress else "gone"])
	if progress.turn_ins != 1:
		return fail(c, "the hand-in count came back as %d" % progress.turn_ins)
	if reloaded.next_offer_from(MIRA) == MIRA_JOB:
		return fail(c, "a finished one-off came back on offer after a reload")
	if reloaded.is_active(MIRA_JOB):
		return fail(c, "a finished one-off came back as active")
	var refused := _recorder(&"quest_accepted_failed")
	if reloaded.accept(MIRA_JOB, built["state"]):
		return fail(c, "a finished one-off was accepted again after a reload")
	if StringName(refused.arg(1)) != QuestService.REASON_ALREADY_TURNED_IN:
		return fail(c, "refused as '%s'" % str(refused.arg(1)))
	_stop_recorders()
	return succeeded(c, "%s is still finished in the save" % MIRA_JOB)


func _t_save_unknown_job() -> Dictionary:
	var c := &"a_save_naming_a_job_we_do_not_have_is_kept"
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a bag and a quest service")
	var quests: QuestService = built["quests"]
	var saved: Dictionary = quests.to_dict()
	# A job retired from the content mid-save. Dropping the entry takes the player's
	# history with it — including whether they had already finished it.
	saved[GHOST_JOB] = {
		"quest_id": GHOST_JOB, "state": QuestProgress.STATE_TURNED_IN,
		"collected": 0, "spoke_to_target": false, "turn_ins": 2, "days_since_turn_in": 4,
	}
	quests.from_dict(saved)
	var progress := quests.get_progress(GHOST_JOB)
	if progress == null:
		return fail(c, "a job we do not have was dropped from the save")
	if not progress.is_turned_in() or progress.turn_ins != 2:
		return fail(c, "the retired job came back as '%s' with %d hand-ins" % [
			progress.state, progress.turn_ins,
		])
	# And it is not quietly offered or paid, because there is nothing behind the id.
	if quests.title_of(GHOST_JOB) != "":
		return fail(c, "a retired job has a title")
	if quests.is_ready_to_turn_in(GHOST_JOB):
		return fail(c, "a retired job is payable")
	if quests.next_offer_from(MIRA) == GHOST_JOB:
		return fail(c, "a retired job is on offer")
	return succeeded(c, "the retired job is remembered and stays unplayable")


# --- Through the real game ----------------------------------------------------


func _t_prompt_offers() -> Dictionary:
	var c := &"the_prompt_offers_a_job_when_nothing_is_in_hand"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the game")
	var component: NpcInteractable = built["component"]
	var player: PlayerController = built["player"]
	if not _hold(built["state"], &"", 0):
		return fail(c, "could not empty the player's hand")
	var prompt := component.get_prompt(player)
	# Offered rather than both offered and handed in on one press: asking how somebody
	# is should not also end their job.
	if not prompt.contains(QuestRegistry.get_quest(MIRA_JOB).title):
		return fail(c, "standing in front of %s with nothing in hand, the prompt says '%s'" % [
			MIRA, prompt,
		])
	var decision := component.preview(player)
	if StringName(decision.get("action", &"")) != &"offer":
		return fail(c, "the press would be a '%s'" % str(decision.get("action", "")))
	if StringName(decision.get("quest_id", &"")) != MIRA_JOB:
		return fail(c, "the press would offer '%s'" % str(decision.get("quest_id", "")))
	return succeeded(c, "'%s'" % prompt)


func _t_prompt_turns_in() -> Dictionary:
	var c := &"the_prompt_offers_a_hand_in_when_the_objective_is_met"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the game")
	var quests: QuestService = built["quests"]
	var component: NpcInteractable = built["component"]
	var player: PlayerController = built["player"]
	var state: Node = built["state"]
	var bag: Inventory = built["bag"]
	var data := QuestRegistry.get_quest(MIRA_JOB)
	if data == null:
		return fail(c, "no %s in the content" % MIRA_JOB)
	var need := data.objective.count
	if not quests.accept(MIRA_JOB, state):
		return fail(c, "could not accept %s" % MIRA_JOB)
	# Holding a tool, which is the normal state of affairs: tools live in the first hotbar
	# slots, so this is what the prompt says for a player who walked over empty-handed
	# except for their hoe.
	if not _hold(state, &"hoe", 1):
		return fail(c, "could not put a hoe in hand")

	# Unfinished: the prompt asks about work rather than offering it a second time, and
	# certainly does not announce a payment.
	var before := component.get_prompt(player)
	if before.contains(data.title) and quests.ready_to_turn_in_from(MIRA) != MIRA_JOB:
		return fail(c, "an unfinished job is announced as payable: '%s'" % before)

	# Gathered, and kept. The hoe is still in hand.
	_gather(bag, PARSNIP, need, "harvest")
	if bag.count(PARSNIP) != need:
		return fail(c, "the parsnips did not stay in the bag")
	if quests.ready_to_turn_in_from(MIRA) != MIRA_JOB:
		return fail(c, "%s is not ready to hand in" % MIRA_JOB)
	var prompt := component.get_prompt(player)
	if not prompt.contains(data.title):
		return fail(c, "holding a hoe with the objective met, the prompt says '%s'" % prompt)
	var decision := component.preview(player)
	if StringName(decision.get("action", &"")) != &"turn_in":
		return fail(c, "the press would be a '%s'" % str(decision.get("action", "")))
	if StringName(decision.get("quest_id", &"")) != MIRA_JOB:
		return fail(c, "the press would hand in '%s'" % str(decision.get("quest_id", "")))

	# And a present still outranks the hand-in: Mira loves parsnips, so carrying the very
	# answer to her own job is a present first. Changing that would make her loved-gift
	# list unreachable while she is useful.
	state.call("select_slot", 1)
	var gift_prompt := component.get_prompt(player)
	if not gift_prompt.begins_with("Give the"):
		return fail(c, "holding the parsnips themselves, the prompt says '%s'" % gift_prompt)

	if not quests.turn_in(MIRA_JOB, state, MIRA):
		return fail(c, "the service refused the job the prompt offered to hand in")
	if bag.count(PARSNIP) != 0:
		return fail(c, "the hand-in left %d %s in the bag" % [bag.count(PARSNIP), PARSNIP])
	return succeeded(c, "'%s', and a present still wins over it" % prompt)


func _t_press_accepts() -> Dictionary:
	var c := &"asking_about_a_job_works_the_real_interact_key"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the game")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var component: NpcInteractable = built["component"]
	var npc: Npc = built["npc"]
	var quests: QuestService = built["quests"]
	if not _hold(built["state"], &"", 0):
		return fail(c, "could not empty the player's hand")
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at %s: %s" % [MIRA, str(focused["why"])])
	# The whole loop through the real key: stand in front of a villager, press E, and
	# the job is in the player's hands.
	var heard: Array[StringName] = []
	var bus := autoload(&"EventBus")
	var accepted := _recorder(&"quest_accepted")
	var listener := func(npc_id: StringName) -> void: heard.append(npc_id)
	bus.connect(&"npc_talked", listener)
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	if accepted.count != 1 or StringName(accepted.arg(0)) != MIRA_JOB:
		bus.disconnect(&"npc_talked", listener)
		return fail(c, "%d jobs accepted from one press" % accepted.count)
	if !quests.is_active(MIRA_JOB):
		bus.disconnect(&"npc_talked", listener)
		return fail(c, "the job is not in hand after the press")
	# The press is spent. A second one is a greeting, not a second copy of the job.
	accepted.watch(bus, &"quest_accepted")
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	bus.disconnect(&"npc_talked", listener)
	if accepted.count != 0:
		return fail(c, "a second press accepted the same job again")
	if heard.size() != 1 or heard[0] != MIRA:
		return fail(c, "the second press greeted %d times: %s" % [heard.size(), str(heard)])
	_stop_recorders()
	return succeeded(c, "one press took the job, the next said hello")


func _t_gift_still_works() -> Dictionary:
	var c := &"holding_a_present_still_wins_over_a_job_offer"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the game")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var component: NpcInteractable = built["component"]
	var npc: Npc = built["npc"]
	var quests: QuestService = built["quests"]
	# Mira loves wild berries and has a job for you at the same time. The job must not
	# make her unreachable as a friend, or her loved-gift list stops existing for as long
	# as she is useful.
	if not _hold(built["state"], WILD_BERRY, 1):
		return fail(c, "could not put a %s in hand" % WILD_BERRY)
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at %s: %s" % [MIRA, str(focused["why"])])
	var prompt := component.get_prompt(player)
	if not prompt.begins_with("Give the"):
		return fail(c, "holding a present she loves, the prompt says '%s'" % prompt)
	var bag: Inventory = built["bag"]
	var berries_before := bag.count(WILD_BERRY)
	var points_before := npc.friendship.points
	var accepted := _recorder(&"quest_accepted")
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	if accepted.count != 0:
		return fail(c, "a present also accepted a job")
	if bag.count(WILD_BERRY) != berries_before - 1:
		return fail(c, "the %s is still in the bag" % WILD_BERRY)
	if npc.friendship.points <= points_before:
		return fail(c, "friendship did not move for a loved gift")
	if quests.is_active(MIRA_JOB):
		return fail(c, "the press quietly took the job as well")
	_stop_recorders()
	return succeeded(c, "one key, and the present won")


func _t_group_matches() -> Dictionary:
	var c := &"the_quest_service_group_matches_the_interactable"
	# The component finds the service by group rather than by name, and the group is
	# written out as a literal in both files to avoid a `class_name` cycle. That is only
	# safe if the two literals agree, so they are compared rather than trusted — a literal
	# that drifts is a quest system the player cannot reach and no compile error.
	if NpcInteractable.QUEST_SERVICE_GROUP != QuestService.SERVICE_GROUP:
		return fail(c, "the component looks for '%s' and the service registers as '%s'" % [
			NpcInteractable.QUEST_SERVICE_GROUP, QuestService.SERVICE_GROUP,
		])
	# Same shape of problem one layer down: the service and the manager each look the
	# other up by group, and the quest service resolves the manager that way when `main`
	# has not handed it one.
	if QuestService.SERVICE_GROUP == NpcManager.SERVICE_GROUP:
		return fail(c, "the quest service and the NPC manager share one group name")
	# And the group is not merely spelled the same in both files: a live service really is
	# findable by the literal the component searches for, which is the difference between
	# two constants agreeing and a lookup working.
	var built := await _build_service()
	if built.is_empty():
		return fail(c, "could not stand up a quest service")
	var quests: QuestService = built["quests"]
	if not quests.is_in_group(NpcInteractable.QUEST_SERVICE_GROUP):
		return fail(c, "a live service is not in the group the component searches")
	if quests.next_offer_from(MIRA).is_empty():
		return fail(c, "the live service offers nothing, so nothing is findable")
	return succeeded(c, "'%s' finds a working service" % NpcInteractable.QUEST_SERVICE_GROUP)


# --- Fixtures -----------------------------------------------------------------


## A bag and a quest service, and no village.
##
## Enough for every case that is about the rules rather than about people. The service is
## loaded by path rather than named, for the reason [method _build_game] gives.
func _build_service(bag_slots: int = 24) -> Dictionary:
	_reset_rig()
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var quest_script := load(QUEST_SERVICE_SCRIPT) as GDScript
	if state_script == null or quest_script == null:
		return {}
	_ensure_rig()
	var state: PlayerStateService = state_script.new()
	state.name = "PlayerState"
	# Before the node enters the tree: the bag is built in `_ready` from this.
	state.bag_slots = maxi(bag_slots, 4)
	_rig.add_child(state)
	var quests: QuestService = quest_script.new()
	quests.name = "QuestService"
	quests.player_state = state
	_rig.add_child(quests)
	await _step(2)
	if state.inventory == null or state.wallet == null:
		return {}
	return {
		"state": state,
		"bag": state.inventory,
		"wallet": state.wallet,
		"quests": quests,
	}


## A bag, a quest service and the whole cast, with no world and no player.
##
## Enough for anything about who pays and who has to be spoken to. The [NpcManager]
## places the cast on ready from their own front steps, exactly as the game does, so the
## friendships under test are the ones the game would start with.
func _build_village() -> Dictionary:
	_reset_rig()
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	var quest_script := load(QUEST_SERVICE_SCRIPT) as GDScript
	if state_script == null or manager_script == null or quest_script == null:
		return {}
	_ensure_rig()
	var state: PlayerStateService = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	var quests: QuestService = quest_script.new()
	quests.name = "QuestService"
	quests.player_state = state
	quests.npc_manager = manager
	_rig.add_child(quests)
	await _step(4)
	var npcs: Dictionary = {}
	for data: NpcData in NpcRegistry.all_npcs():
		var npc := manager.get_npc(data.id)
		if npc == null:
			return {}
		npcs[data.id] = npc
	if state.inventory == null or npcs.is_empty():
		return {}
	return {
		"state": state,
		"bag": state.inventory,
		"wallet": state.wallet,
		"quests": quests,
		"manager": manager,
		"npcs": npcs,
	}


## The real valley, a real player and a real interaction probe.
##
## The only arrangement in which the prompt can be asked the question a player asks it,
## which is why the acceptance cases use it rather than the service directly.
func _build_game() -> Dictionary:
	var world_packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	var quest_script := load(QUEST_SERVICE_SCRIPT) as GDScript
	if world_packed == null or player_packed == null or state_script == null \
			or manager_script == null or quest_script == null:
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
	state.call("grant_starter_loadout")
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	var quests: QuestService = quest_script.new()
	quests.name = "QuestService"
	quests.player_state = state
	quests.npc_manager = manager
	_rig.add_child(quests)
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
		"bag": state.inventory,
		"wallet": state.wallet,
		"quests": quests,
		"manager": manager,
		"npc": npc,
		"component": component,
	}


## Puts [param item_id] in the bag and publishes the event the named [param funnel] would.
##
## Three funnels because the project has three producers of "the player now holds this",
## and the order is the real one every time: the bag first, then the announcement. A test
## that published the event before filling the bag would pass a service that read the
## event's amount instead of the bag's.
func _gather(bag: Inventory, item_id: StringName, amount: int, funnel: StringName) -> void:
	if int(bag.add(item_id, amount)) != amount:
		return
	var bus := autoload(&"EventBus")
	match funnel:
		&"harvest":
			bus.emit_signal(&"item_added", item_id, amount)
		&"gather":
			bus.emit_signal(&"resource_collected", item_id, amount)
		&"buy":
			bus.emit_signal(&"item_purchased", item_id, amount, 0)
		_:
			pass


## Announces a day, the way the clock does, so the services that count days are the ones
## being tested rather than a private field poked directly.
func _day_rolls(day: int = 1) -> void:
	autoload(&"EventBus").emit_signal(&"day_started", day)


## Fills the bag without announcing anything, which is what the player already owned
## before they were offered the job.
func _gather_raw(bag: Inventory, item_id: StringName, amount: int) -> void:
	bag.add(item_id, amount)


## Says hello to [param npc], through the manager, so the conversation is the real one.
##
## A null [param npc] is an explicit "nobody in particular", for the cases that only need
## [signal EventBus.npc_talked] to have happened for the talk objective.
func _talk_to(built: Dictionary, npc: Npc) -> void:
	var bus := autoload(&"EventBus")
	if npc == null:
		bus.emit_signal(&"npc_talked", HALDA)
		return
	built["manager"].call("talk", npc, built["state"])


## Puts [param item_id] in the player's hand and nowhere else.
##
## Empties the bag first so the item lands in slot 0, which is the only slot the hotbar
## can be looking at — an item in slot 20 is in the bag and not in the player's hand, a
## distinction the prompt cases would otherwise rediscover one failure at a time.
func _hold(state: Node, item_id: StringName, amount: int) -> bool:
	var bag := state.get("inventory") as Inventory
	if bag == null:
		return false
	bag.set_contents([])
	if not item_id.is_empty() and int(bag.add(item_id, amount)) != amount:
		return false
	state.call("select_slot", 0)
	return true


## A recorder watching one [EventBus] signal, so a case can assert on the last event's
## arguments rather than on a side effect.
func _recorder(signal_name: StringName) -> Object:
	var script := load(RECORDER_SCRIPT) as GDScript
	if script == null:
		return null
	var recorder: Object = script.new()
	recorder.watch(autoload(&"EventBus"), signal_name)
	_watchers.append({"bus": autoload(&"EventBus"), "signal": signal_name, "rec": recorder})
	return recorder


func _stop_recorders() -> void:
	for watcher: Dictionary in _watchers:
		watcher["rec"].call("stop", watcher["bus"], watcher["signal"])
	_watchers = []


## Argument [param index] of a recorder's last event, as the vocabulary's own type.
##
## A local lambda would read the same and does not compile, because a lambda stored in a
## local cannot be called by name. One method is the smallest thing that works.
func _reason(recorder: Object, index: int = 2) -> StringName:
	if recorder == null:
		return &""
	return StringName(recorder.arg(index))


func _find_first(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := _find_first(child, node_name)
		if found != null:
			return found
	return null


## Puts the player next to [param npc] and aims at [param component].
##
## Several offsets rather than one, because the village is scattered and a fixed offset
## regularly leaves a tree between the camera and the villager — a failure that teaches
## nothing.
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
	_rig.name = "QuestTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	_stop_recorders()
	if _rig != null and is_instance_valid(_rig):
		# `free()` rather than `queue_free()`: the next case builds its own rig, and a
		# freed node's `_exit_tree` is what disconnects the quest service from the bus.
		_rig.free()
	_rig = null


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