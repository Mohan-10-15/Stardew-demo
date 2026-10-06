extends TestSuite
## Villagers: who they are, what they think of the player, and the one key that both
## says hello and hands over a present.
##
## Group 14 — NPC system.
##
## Covers the four layers in the order they answer questions: content
## ([NpcData], [NpcRegistry]), the score ([Friendship]), the body ([Npc]) and the rules
## ([NpcManager], [NpcInteractable]).
##
## ## Why every transaction asserts both halves
##
## A gift is one thing moving out of the bag and one number moving up. Checking the
## points alone passes a villager who scores a present the player still owns; checking
## the bag alone passes a thief. Both halves or it is not a test.
##
## ## Why the refusals are enumerated
##
## Every refusal has its own reason string because every refusal is a *different*
## sentence to the player, and `talking`, `giving`, and `holding the wrong thing` are
## three different sentences. `every_npc_refusal_has_its_own_reason` walks the
## vocabulary the [EventBus] documents and proves each one is reachable, which is the
## same contract `EventBus.gathering_failed` is held to.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
## The real HUD, so the prompt label is checked as the player sees it rather than as the
## component behind it describes it. See [method _t_label_follows_state].
const HUD_SCENE := "res://scenes/ui/interaction_hud.tscn"

## Mira is the villager the content actually names, and naming one rather than
## "the first" makes every failure message point at a villager a reader can go and look
## at. Her lists are: loves wild_berry and parsnip, likes spring_onion and potato,
## dislikes stone.
const MIRA := &"mira"
const HER_LOVED := &"wild_berry"
const HER_LIKED := &"spring_onion"
const HER_DISLIKED := &"stone"
## Her other loved gift, and the one with no [ItemDefinition] behind it — a harvested crop
## is in the bag under its crop id. See [method _t_crop_gift].
const HER_PARSNIP := &"parsnip"

## A tag nobody owns, for the "no definition behind this stack" refusal.
const GHOST_ITEM := &"ghost_item_never_authored"

var _rig: Node3D = null
## Talk refusals seen during the current case, as `{npc, reason}`.
var _talk_failures: Array[Dictionary] = []
## Gift refusals seen during the current case, as `{npc, item, reason}`.
var _gift_failures: Array[Dictionary] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		# --- content --------------------------------------------------------------
		&"villagers_are_on_disk_and_uniquely_named",
		&"every_villager_is_valid",
		&"every_villager_draws_a_real_model",
		&"every_villager_has_a_name_a_player_can_read",
		&"every_named_gift_is_something_the_player_can_hold",
		&"no_gift_is_in_two_lists_at_once",
		&"every_disliked_gift_is_something_a_player_could_hand_over",
		&"the_cast_is_not_all_in_the_same_outfit",
		&"a_birthday_reads_as_a_real_date",
		&"an_unset_birthday_says_nothing_rather_than_the_first_of_spring",
		# --- the score ------------------------------------------------------------
		&"a_new_friendship_is_a_stranger",
		&"hearts_only_move_when_the_points_say_so",
		&"the_tier_name_follows_the_heart_count",
		&"a_loved_gift_is_worth_the_most_and_a_disliked_one_costs_you",
		&"friendship_never_leaves_its_bounds",
		&"a_maxed_friendship_reports_that_nothing_landed",
		&"a_gift_is_still_counted_when_the_meter_cannot_move",
		&"two_gifts_a_week_and_not_a_third",
		&"one_loved_gift_a_day",
		&"a_new_day_clears_todays_gifts_but_not_the_weeks",
		&"a_friendship_save_round_trips_and_clamps_a_hand_edited_one",
		# --- the body -------------------------------------------------------------
		&"a_villager_stands_on_the_ground_at_their_own_doorstep",
		&"a_villager_wanders_inside_their_own_radius",
		&"a_villager_holds_still_while_being_spoken_to",
		&"the_day_rollover_sends_everyone_home",
		&"two_villagers_with_the_same_id_walk_the_same_way",
		&"a_villager_is_solid_and_carries_an_interaction_component",
		&"a_villager_with_nothing_to_say_says_nothing",
		# --- the authored day ------------------------------------------------------
		&"schedules_point_every_villager_at_a_real_place",
		&"a_scheduled_villager_walks_to_their_post_and_holds_it",
		&"the_walkability_grid_reaches_every_named_place",
		# --- the rules ------------------------------------------------------------
		&"talking_turns_a_villager_to_face_the_player",
		&"a_gift_takes_the_item_and_moves_the_score_together",
		&"a_harvested_crop_is_a_present_too",
		&"a_refused_gift_leaves_the_bag_and_the_score_alone",
		&"a_disliked_gift_is_taken_and_costs_friendship",
		&"a_tool_in_hand_is_not_a_present",
		&"the_third_gift_of_the_week_is_refused",
		&"a_second_loved_gift_the_same_day_is_refused",
		&"the_daily_gift_limits_clear_at_midnight",
		&"giving_something_other_than_what_is_in_hand_is_refused",
		&"an_empty_hand_has_nothing_to_give",
		&"a_stack_with_no_definition_behind_it_is_refused",
		&"a_tier_change_is_published",
		# --- the save -------------------------------------------------------------
		&"the_whole_cast_save_round_trips",
		&"a_save_naming_a_villager_we_do_not_have_is_skipped",
		# --- through the real game ------------------------------------------------
		&"the_valley_spawns_the_whole_cast",
		&"every_villager_can_be_reached_on_foot",
		&"the_prompt_survives_walking_up_to_a_villager",
		&"talking_to_a_villager_works_the_real_interact_key",
		&"holding_a_gift_turns_the_same_key_into_a_present",
		# --- what the player is actually told -------------------------------------
		&"a_refused_present_says_why_on_the_prompt",
		&"a_refused_present_still_says_hello_and_publishes_itself",
		&"the_prompt_label_follows_the_state_it_describes",
		# --- the refusal vocabulary ----------------------------------------------
		&"every_npc_refusal_has_its_own_reason",
	]


func setup() -> void:
	_rig = null
	_talk_failures = []
	_gift_failures = []


func teardown() -> void:
	# Never leave a simulated keypress or a live refusal listener behind: both outlive
	# the case that made them and poison the next one in ways that read as flakes.
	Input.action_release(&"interact")
	var bus := autoload(&"EventBus")
	if bus != null:
		if bus.npc_talk_failed.is_connected(_record_talk_failure):
			bus.npc_talk_failed.disconnect(_record_talk_failure)
		if bus.npc_gift_failed.is_connected(_record_gift_failure):
			bus.npc_gift_failed.disconnect(_record_gift_failure)
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	# Per *case*, not per suite: [method TestSuite.setup] runs once for the whole file,
	# so reasons recorded there would carry into cases that never touched them.
	_talk_failures = []
	_gift_failures = []
	match case:
		&"villagers_are_on_disk_and_uniquely_named":
			return await _t_cast_on_disk()
		&"every_villager_is_valid":
			return await _t_cast_valid()
		&"every_villager_draws_a_real_model":
			return await _t_cast_models()
		&"every_villager_has_a_name_a_player_can_read":
			return await _t_cast_names()
		&"every_named_gift_is_something_the_player_can_hold":
			return await _t_gifts_exist()
		&"no_gift_is_in_two_lists_at_once":
			return await _t_gifts_disjoint()
		&"every_disliked_gift_is_something_a_player_could_hand_over":
			return await _t_dislikes_are_giftable()
		&"the_cast_is_not_all_in_the_same_outfit":
			return await _t_cast_distinct()
		&"a_birthday_reads_as_a_real_date":
			return await _t_birthdays()
		&"an_unset_birthday_says_nothing_rather_than_the_first_of_spring":
			return await _t_unset_birthday()
		&"a_new_friendship_is_a_stranger":
			return await _t_stranger()
		&"hearts_only_move_when_the_points_say_so":
			return await _t_heart_threshold()
		&"the_tier_name_follows_the_heart_count":
			return await _t_tier_names()
		&"a_loved_gift_is_worth_the_most_and_a_disliked_one_costs_you":
			return await _t_points_ordering()
		&"friendship_never_leaves_its_bounds":
			return await _t_friendship_bounds()
		&"a_maxed_friendship_reports_that_nothing_landed":
			return await _t_maxed_reports_zero()
		&"a_gift_is_still_counted_when_the_meter_cannot_move":
			return await _t_maxed_still_counts()
		&"two_gifts_a_week_and_not_a_third":
			return await _t_weekly_limit()
		&"one_loved_gift_a_day":
			return await _t_loved_daily_limit()
		&"a_new_day_clears_todays_gifts_but_not_the_weeks":
			return await _t_new_day()
		&"a_friendship_save_round_trips_and_clamps_a_hand_edited_one":
			return await _t_friendship_save()
		&"a_villager_stands_on_the_ground_at_their_own_doorstep":
			return await _t_stands_on_ground()
		&"a_villager_wanders_inside_their_own_radius":
			return await _t_wander_radius()
		&"a_villager_holds_still_while_being_spoken_to":
			return await _t_attending_holds_still()
		&"the_day_rollover_sends_everyone_home":
			return await _t_day_sends_home()
		&"two_villagers_with_the_same_id_walk_the_same_way":
			return await _t_deterministic()
		&"a_villager_is_solid_and_carries_an_interaction_component":
			return await _t_solid_and_component()
		&"a_villager_with_nothing_to_say_says_nothing":
			return await _t_no_definition()
		&"schedules_point_every_villager_at_a_real_place":
			return await _t_schedules_resolve()
		&"a_scheduled_villager_walks_to_their_post_and_holds_it":
			return await _t_scheduled_walk()
		&"the_walkability_grid_reaches_every_named_place":
			return await _t_navigation_grid()
		&"talking_turns_a_villager_to_face_the_player":
			return await _t_talk_faces()
		&"a_gift_takes_the_item_and_moves_the_score_together":
			return await _t_gift_both_halves()
		&"a_harvested_crop_is_a_present_too":
			return await _t_crop_gift()
		&"a_refused_gift_leaves_the_bag_and_the_score_alone":
			return await _t_refused_gift_is_atomic()
		&"a_disliked_gift_is_taken_and_costs_friendship":
			return await _t_disliked_gift()
		&"a_tool_in_hand_is_not_a_present":
			return await _t_tool_not_a_gift()
		&"the_third_gift_of_the_week_is_refused":
			return await _t_third_gift_refused()
		&"a_second_loved_gift_the_same_day_is_refused":
			return await _t_second_loved_refused()
		&"the_daily_gift_limits_clear_at_midnight":
			return await _t_rollover_clears_limits()
		&"giving_something_other_than_what_is_in_hand_is_refused":
			return await _t_wrong_item_refused()
		&"an_empty_hand_has_nothing_to_give":
			return await _t_empty_hand()
		&"a_stack_with_no_definition_behind_it_is_refused":
			return await _t_undefined_stack()
		&"a_tier_change_is_published":
			return await _t_tier_change_published()
		&"the_whole_cast_save_round_trips":
			return await _t_cast_save()
		&"a_save_naming_a_villager_we_do_not_have_is_skipped":
			return await _t_save_unknown_npc()
		&"the_valley_spawns_the_whole_cast":
			return await _t_valley_spawns_cast()
		&"every_villager_can_be_reached_on_foot":
			return await _t_reachable()
		&"the_prompt_survives_walking_up_to_a_villager":
			return await _t_point_blank_prompt()
		&"talking_to_a_villager_works_the_real_interact_key":
			return await _t_talk_through_input()
		&"holding_a_gift_turns_the_same_key_into_a_present":
			return await _t_gift_through_input()
		&"a_refused_present_says_why_on_the_prompt":
			return await _t_refusal_explains_itself()
		&"a_refused_present_still_says_hello_and_publishes_itself":
			return await _t_refusal_through_input()
		&"the_prompt_label_follows_the_state_it_describes":
			return await _t_label_follows_state()
		&"every_npc_refusal_has_its_own_reason":
			return await _t_every_refusal_reason()
	return fail(case, "no case implementation for %s" % case)


# --- Content --------------------------------------------------------------------


func _t_cast_on_disk() -> Dictionary:
	var c := &"villagers_are_on_disk_and_uniquely_named"
	var cast := NpcRegistry.all_npcs()
	if cast.is_empty():
		return fail(c, "there are no villagers at all, so nothing below is testing anything")
	var dupes := NpcRegistry.duplicate_ids()
	if not dupes.is_empty():
		return fail(c, "two files claim the id(s) %s" % ", ".join(dupes))
	# Sorted by id, because a world built twice must place the cast in the same order
	# or a save lines up against the wrong villager.
	var ids: Array[String] = []
	for data: NpcData in cast:
		ids.append(String(data.id))
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	if ids != sorted_ids:
		return fail(c, "NpcRegistry.all_npcs() is not in id order: %s" % ", ".join(ids))
	return succeeded(c, "%d villagers, unique ids, stable order" % cast.size())


func _t_cast_valid() -> Dictionary:
	var c := &"every_villager_is_valid"
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if not data.is_valid():
			bad.append(String(data.id))
	if not bad.is_empty():
		return fail(c, "is_valid() says no to: %s" % ", ".join(bad))
	return succeeded(c, "all %d definitions are valid" % NpcRegistry.all_npcs().size())


func _t_cast_models() -> Dictionary:
	var c := &"every_villager_draws_a_real_model"
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if not ModelArt.can_load(data.model):
			bad.append("%s -> %s" % [data.id, data.model])
			continue
		var box := ModelArt.natural_aabb(data.model)
		if box.size.y <= 0.0:
			bad.append("%s measures 0m tall" % data.id)
	if not bad.is_empty():
		return fail(c, "no usable body for: %s" % ", ".join(bad))
	return succeeded(c, "every villager has a model that loads and measures")


func _t_cast_names() -> Dictionary:
	var c := &"every_villager_has_a_name_a_player_can_read"
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		# A display name a player reads, never the id. `is_valid` already refuses an
		# empty one; this refuses a name that is just the id with an underscore.
		if data.display_name == String(data.id) or data.display_name.contains("_"):
			bad.append("%s reads as '%s'" % [data.id, data.display_name])
		if data.description.is_empty():
			bad.append("%s has no description" % data.id)
	if not bad.is_empty():
		return fail(c, ", ".join(bad))
	return succeeded(c, "every villager is named and described for a player")


func _t_gifts_exist() -> Dictionary:
	var c := &"every_named_gift_is_something_the_player_can_hold"
	# `is_known_item`, not `ItemRegistry.has_item`: a harvested crop enters the bag under
	# its crop id and is defined in the crop directory, so an item-registry-only check
	# called ten of the twenty-two authored gifts a bug the player would find the moment
	# they tried to hand Mira the parsnip she loves.
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		for gift: StringName in data.loved_gifts + data.liked_gifts + data.disliked_gifts:
			if not NpcData.is_known_item(gift):
				bad.append("%s wants '%s', which no content defines" % [data.id, gift])
	if not bad.is_empty():
		return fail(c, ", ".join(bad))
	return succeeded(c, "every named gift resolves to something in the bag")


func _t_gifts_disjoint() -> Dictionary:
	var c := &"no_gift_is_in_two_lists_at_once"
	# Checked list by list rather than by leaning on `is_valid`, so the failure names
	# the villager and the two lists instead of just "invalid".
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		for gift: StringName in data.loved_gifts:
			if data.liked_gifts.has(gift):
				bad.append("%s: '%s' is both loved and liked" % [data.id, gift])
			if data.disliked_gifts.has(gift):
				bad.append("%s: '%s' is both loved and disliked" % [data.id, gift])
		for gift: StringName in data.liked_gifts:
			if data.disliked_gifts.has(gift):
				bad.append("%s: '%s' is both liked and disliked" % [data.id, gift])
	if not bad.is_empty():
		return fail(c, ", ".join(bad))
	return succeeded(c, "loved, liked and disliked are three separate questions")


func _t_dislikes_are_giftable() -> Dictionary:
	var c := &"every_disliked_gift_is_something_a_player_could_hand_over"
	# A dislike that can never fire is dead content the author believes in. Rake is not
	# giftable at all, so "dislikes the hoe" is a rule the game can never reach.
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		for gift: StringName in data.disliked_gifts:
			if not NpcData.is_giftable_id(gift):
				bad.append("%s dislikes '%s', which cannot be given" % [data.id, gift])
	if not bad.is_empty():
		return fail(c, ", ".join(bad))
	return succeeded(c, "every disliked gift is a thing the game would actually hand over")


func _t_cast_distinct() -> Dictionary:
	var c := &"the_cast_is_not_all_in_the_same_outfit"
	var per_appearance := NpcRegistry.count_per_appearance()
	var cast_size := NpcRegistry.all_npcs().size()
	if per_appearance.size() <= 1:
		return fail(c, "all %d villagers wear one appearance" % cast_size)
	for key: String in per_appearance:
		# Two in a costume is an author's choice; four is a bug nobody noticed.
		if int(per_appearance[key]) > 2:
			return fail(c, "%d villagers wear the same body and tint (%s)" % [
				int(per_appearance[key]), key,
			])
	return succeeded(c, "%d villagers across %d appearances" % [cast_size, per_appearance.size()])


func _t_birthdays() -> Dictionary:
	var c := &"a_birthday_reads_as_a_real_date"
	var bad: Array[String] = []
	var with_birthday := 0
	for data: NpcData in NpcRegistry.all_npcs():
		if not data.has_birthday():
			continue
		with_birthday += 1
		var said := data.describe_birthday()
		if said.is_empty():
			bad.append("%s has season %d, which is not a season" % [data.id, data.birthday_season])
			continue
		var expected := "%d %s" % [data.birthday_day, NpcData.SEASON_NAMES[data.birthday_season]]
		if said != expected:
			bad.append("%s says '%s', expected '%s'" % [data.id, said, expected])
	if with_birthday == 0:
		return fail(c, "not one villager has a birthday, so nothing is being tested")
	return succeeded(c, "%d birthdays read as real dates" % with_birthday)


func _t_unset_birthday() -> Dictionary:
	var c := &"an_unset_birthday_says_nothing_rather_than_the_first_of_spring"
	# The sentinel is month 0 day 0, which is *not* Spring 1st. A field that defaulted
	# silently would give every unnamed villager the same birthday, on the first of the
	# first month, forever.
	var data := NpcData.new()
	data.id = &"nobody"
	data.display_name = "Nobody"
	if data.has_birthday():
		return fail(c, "a fresh NpcData claims to have a birthday")
	if not data.describe_birthday().is_empty():
		return fail(c, "an unset birthday reads as '%s'" % data.describe_birthday())
	return succeeded(c, "an unset birthday says nothing")


# --- The score ------------------------------------------------------------------


func _t_stranger() -> Dictionary:
	var c := &"a_new_friendship_is_a_stranger"
	var f := Friendship.new()
	if f.points != 0:
		return fail(c, "a new friendship starts on %d points" % f.points)
	if f.hearts() != 0:
		return fail(c, "a new friendship starts on %d hearts" % f.hearts())
	if f.tier_name() != "Stranger":
		return fail(c, "a new friendship reads as '%s'" % f.tier_name())
	if not f.can_gift_today():
		return fail(c, "a new friendship cannot be given a gift at all")
	return succeeded(c, "0 points, 0 hearts, %s" % f.tier_name())


func _t_heart_threshold() -> Dictionary:
	var c := &"hearts_only_move_when_the_points_say_so"
	var f := Friendship.new()
	# Just short of a heart, and then just past it. The point of storing points rather
	# than hearts is that a gift worth less than a whole heart is *kept*, not rounded
	# away; this is the assertion that says so.
	f.points = Friendship.POINTS_PER_HEART - 1
	if f.hearts() != 0:
		return fail(c, "%d points already counts as a heart" % f.points)
	f.points += 1
	if f.hearts() != 1:
		return fail(c, "%d points is not yet a heart" % f.points)
	return succeeded(c, "the heart boundary is exactly %d points" % Friendship.POINTS_PER_HEART)


func _t_tier_names() -> Dictionary:
	var c := &"the_tier_name_follows_the_heart_count"
	if Friendship.TIER_NAMES.size() != Friendship.TIER_THRESHOLDS.size():
		return fail(c, "%d tier names for %d thresholds" % [
			Friendship.TIER_NAMES.size(), Friendship.TIER_THRESHOLDS.size(),
		])
	for i: int in range(Friendship.TIER_NAMES.size()):
		var f := Friendship.new()
		f.points = Friendship.TIER_THRESHOLDS[i] * Friendship.POINTS_PER_HEART
		if f.tier_name() != Friendship.TIER_NAMES[i]:
			return fail(c, "%d hearts reads as '%s', expected '%s'" % [
				Friendship.TIER_THRESHOLDS[i], f.tier_name(), Friendship.TIER_NAMES[i],
			])
	# The backwards walk exists so a maxed friendship does not read as its first tier.
	var maxed := Friendship.new()
	maxed.points = Friendship.MAX_POINTS
	if maxed.tier_name() != Friendship.TIER_NAMES[Friendship.TIER_NAMES.size() - 1]:
		return fail(c, "ten hearts reads as '%s'" % maxed.tier_name())
	if maxed.hearts() != Friendship.MAX_HEARTS:
		return fail(c, "MAX_POINTS is %d hearts, not %d" % [maxed.hearts(), Friendship.MAX_HEARTS])
	return succeeded(c, "%d tier names, and the top one is reachable" % Friendship.TIER_NAMES.size())


func _t_points_ordering() -> Dictionary:
	var c := &"a_loved_gift_is_worth_the_most_and_a_disliked_one_costs_you"
	var loved := Friendship.points_for(NpcData.REACTION_LOVED)
	var liked := Friendship.points_for(NpcData.REACTION_LIKED)
	var neutral := Friendship.points_for(NpcData.REACTION_NEUTRAL)
	var disliked := Friendship.points_for(NpcData.REACTION_DISLIKED)
	# The order is the design, not an accident: handing someone the wrong thing has to
	# be a *worse* mistake than handing them nothing.
	if not (loved > liked and liked > neutral and neutral > 0 and disliked < 0):
		return fail(c, "loved=%d liked=%d neutral=%d disliked=%d" % [
			loved, liked, neutral, disliked,
		])
	if Friendship.points_for(&"not_a_reaction") != 0:
		return fail(c, "an unknown reaction is worth something")
	return succeeded(c, "loved=%d liked=%d neutral=%d disliked=%d" % [loved, liked, neutral, disliked])


func _t_friendship_bounds() -> Dictionary:
	var c := &"friendship_never_leaves_its_bounds"
	var low := Friendship.new()
	low.award(NpcData.REACTION_DISLIKED)
	if low.points != 0:
		return fail(c, "a disliked gift at zero friendship took the score to %d" % low.points)
	var high := Friendship.new()
	for _gift: int in range(200):
		high.award(NpcData.REACTION_LOVED)
	if high.points != Friendship.MAX_POINTS:
		return fail(c, "200 loved gifts reached %d points, cap is %d" % [
			high.points, Friendship.MAX_POINTS,
		])
	return succeeded(c, "clamped to [0, %d] from both ends" % Friendship.MAX_POINTS)


func _t_maxed_reports_zero() -> Dictionary:
	var c := &"a_maxed_friendship_reports_that_nothing_landed"
	# The caller logs what the gift was worth. Reporting the *intended* 80 here would
	# tell the player their present mattered when it bought nothing at all.
	var f := Friendship.new()
	f.points = Friendship.MAX_POINTS
	var landed := f.award(NpcData.REACTION_LOVED)
	if landed != 0:
		return fail(c, "a maxed friendship reported %d points landing" % landed)
	if f.tier_name() != Friendship.TIER_NAMES[Friendship.TIER_NAMES.size() - 1]:
		return fail(c, "a maxed friendship reads as '%s'" % f.tier_name())
	return succeeded(c, "reported 0, still %s" % f.tier_name())


func _t_maxed_still_counts() -> Dictionary:
	var c := &"a_gift_is_still_counted_when_the_meter_cannot_move"
	# Otherwise maxing one relationship hands out unlimited free presents: the points
	# stop moving so the counters would never stop either.
	var f := Friendship.new()
	f.points = Friendship.MAX_POINTS
	f.award(NpcData.REACTION_LOVED)
	if f.gifts_today != 1:
		return fail(c, "gifts_today is %d after one gift" % f.gifts_today)
	if f.gifts_this_week != 1:
		return fail(c, "gifts_this_week is %d after one gift" % f.gifts_this_week)
	if f.loved_today != 1:
		return fail(c, "loved_today is %d after one loved gift" % f.loved_today)
	return succeeded(c, "the gift still cost the weekly budget")


func _t_weekly_limit() -> Dictionary:
	var c := &"two_gifts_a_week_and_not_a_third"
	var f := Friendship.new()
	for _gift: int in range(Friendship.WEEKLY_GIFT_LIMIT):
		if not f.can_gift_today():
			return fail(c, "refused gift %d of %d" % [_gift + 1, Friendship.WEEKLY_GIFT_LIMIT])
		f.award(NpcData.REACTION_NEUTRAL)
	if f.can_gift_today():
		return fail(c, "still giftable after %d gifts this week" % Friendship.WEEKLY_GIFT_LIMIT)
	# The daily counters are a separate question: a spent week is not a spent day.
	if not f.can_gift_loved_today():
		return fail(c, "the week ran out and took the daily loved cap with it")
	return succeeded(c, "%d a week, refused the %dth" % [
		Friendship.WEEKLY_GIFT_LIMIT, Friendship.WEEKLY_GIFT_LIMIT + 1,
	])


func _t_loved_daily_limit() -> Dictionary:
	var c := &"one_loved_gift_a_day"
	var f := Friendship.new()
	for _gift: int in range(Friendship.LOVED_GIFT_LIMIT):
		if not f.can_gift_loved_today():
			return fail(c, "refused loved gift %d of %d" % [
				_gift + 1, Friendship.LOVED_GIFT_LIMIT,
			])
		f.award(NpcData.REACTION_LOVED)
	if f.can_gift_loved_today():
		return fail(c, "still giftable a loved gift after %d today" % Friendship.LOVED_GIFT_LIMIT)
	if not f.can_gift_today():
		return fail(c, "the loved cap also closed the weekly budget")
	return succeeded(c, "%d loved a day, refused the next" % Friendship.LOVED_GIFT_LIMIT)


func _t_new_day() -> Dictionary:
	var c := &"a_new_day_clears_todays_gifts_but_not_the_weeks"
	var f := Friendship.new()
	f.award(NpcData.REACTION_LOVED)
	f.award(NpcData.REACTION_LIKED)
	if f.gifts_today != 2 or f.loved_today != 1:
		return fail(c, "setup did not register: today=%d loved=%d" % [f.gifts_today, f.loved_today])
	f.new_day()
	if f.gifts_today != 0 or f.loved_today != 0:
		return fail(c, "a new day left today=%d loved=%d" % [f.gifts_today, f.loved_today])
	if f.gifts_this_week != 2:
		return fail(c, "a new day also cleared the week (%d)" % f.gifts_this_week)
	# Both weekly slots are spent above, so `can_gift_today()` being false there proves
	# nothing — the week really is over. The question this case exists to answer is
	# whether *one* gift survives a day boundary, so it asks about that.
	var carried := Friendship.new()
	carried.award(NpcData.REACTION_LIKED)
	carried.new_day()
	if not carried.can_gift_today():
		return fail(c, "the weekly budget was closed by a daily reset")
	return succeeded(c, "daily counters cleared, the week's second slot survived")


func _t_friendship_save() -> Dictionary:
	var c := &"a_friendship_save_round_trips_and_clamps_a_hand_edited_one"
	var f := Friendship.new()
	f.points = 420
	f.gifts_today = 1
	f.loved_today = 1
	f.gifts_this_week = 2
	var restored := f.copy()
	if restored.to_dict() != f.to_dict():
		return fail(c, "%s came back as %s" % [str(f.to_dict()), str(restored.to_dict())])
	# A save edited by hand, or written by a build with a higher cap, must not open the
	# game with a friendship no gift could climb out of.
	var edited := Friendship.new()
	edited.from_dict({"points": -4000, "gifts_today": -3, "gifts_this_week": 99})
	if edited.points != 0:
		return fail(c, "a friendship of -4000 loaded as %d" % edited.points)
	if edited.gifts_today != 0:
		return fail(c, "gifts_today of -3 loaded as %d" % edited.gifts_today)
	if edited.points > Friendship.MAX_POINTS:
		return fail(c, "a friendship past the cap loaded as %d" % edited.points)
	return succeeded(c, "round-tripped, and a hand-edited save is clamped")


# --- The body -------------------------------------------------------------------


func _t_stands_on_ground() -> Dictionary:
	var c := &"a_villager_stands_on_the_ground_at_their_own_doorstep"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc: Npc = manager.call("npcs")[0]
	var expected := NpcManager.ground_position(npc.data.home)
	# Placement is written before the node enters the tree, so this is the position it
	# was *placed* at rather than the one gravity has since settled.
	if absf(npc.position.y - expected.y) > 0.001:
		return fail(c, "%s stands at y=%.3f, ground at %.3f" % [
			npc.data.id, npc.position.y, expected.y,
		])
	return succeeded(c, "%s stands on the ground at %s" % [npc.data.id, str(npc.global_position)])


func _t_wander_radius() -> Dictionary:
	var c := &"a_villager_wanders_inside_their_own_radius"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc: Npc = manager.call("npcs")[0]
	var home := npc.data.home
	var limit := npc.data.wander_radius + 0.5
	var worst := 0.0
	# Real physics frames, not a direct `_advance` call: the question is whether the
	# villager stays in the village, and gravity and fences are part of that.
	for _tick: int in range(120):
		await _step(1)
		worst = maxf(worst, Vector2(npc.position.x - home.x, npc.position.z - home.y).length())
	if worst > limit:
		return fail(c, "%s wandered %.2fm from home, radius is %.1fm" % [
			npc.data.id, worst, npc.data.wander_radius,
		])
	if worst < 0.1:
		return fail(c, "%s never left their doorstep, so nothing was tested" % npc.data.id)
	return succeeded(c, "%s stayed within %.2fm of home (radius %.1fm)" % [
		npc.data.id, worst, npc.data.wander_radius,
	])


func _t_attending_holds_still() -> Dictionary:
	var c := &"a_villager_holds_still_while_being_spoken_to"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc: Npc = manager.call("npcs")[0]
	var player: Node3D = built["player"]
	# Far enough that the villager is definitely mid-patrol when the conversation starts.
	await _wait(0.5)
	npc.attending = true
	# The sample starts after the stop, not at it: `attending` decelerates rather than
	# teleports, so measuring from the instant it is set measures the braking distance
	# instead of whether they stand still while listening.
	await _wait(0.4)
	var before := Vector2(npc.position.x, npc.position.z)
	await _wait(0.6)
	var after := Vector2(npc.position.x, npc.position.z)
	if before.distance_to(after) > 0.05:
		return fail(c, "%s walked %.3fm while being spoken to" % [npc.data.id, before.distance_to(after)])
	npc.attending = false
	await _wait(0.8)
	var moved := Vector2(npc.position.x, npc.position.z)
	if moved.distance_to(after) < 0.05:
		return fail(c, "%s stood like a stone once the conversation ended" % npc.data.id)
	if player == null:
		return fail(c, "no player in the fixture")
	return succeeded(c, "held still for the conversation, then walked again")


func _t_day_sends_home() -> Dictionary:
	var c := &"the_day_rollover_sends_everyone_home"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc: Npc = manager.call("npcs")[0]
	await _wait(0.5)
	var wandered := Vector2(npc.position.x, npc.position.z).distance_to(npc.data.home)
	if wandered < 0.5:
		return fail(c, "%s was already home, so the rollover has nothing to prove" % npc.data.id)
	manager.call("_on_day_started", 2)
	# Measured before the next tick rather than a couple of frames after: `go_home` puts
	# them on the doorstep and the wander resumes at once, so a later sample measures a
	# villager already walking to work rather than one who failed to come home.
	var home_again := Vector2(npc.position.x, npc.position.z).distance_to(npc.data.home)
	if home_again > 0.001:
		return fail(c, "%s is %.2fm from home the morning after" % [npc.data.id, home_again])
	await _wait(0.5)
	var drifted := Vector2(npc.position.x, npc.position.z).distance_to(npc.data.home)
	if drifted > npc.data.wander_radius:
		return fail(c, "%s woke up on the doorstep and then left the village (%.2fm)" % [
			npc.data.id, drifted,
		])
	return succeeded(c, "%s was %.1fm out, woke on the doorstep, and stayed inside %.1fm" % [
		npc.data.id, wandered, npc.data.wander_radius,
	])


func _t_deterministic() -> Dictionary:
	var c := &"two_villagers_with_the_same_id_walk_the_same_way"
	# Not a cosmetic property: a test that asserts "she stays inside her radius" is
	# worthless if it passes by luck, and a player replaying a day gets the same village.
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var data := NpcRegistry.get_npc(MIRA)
	if data == null:
		return fail(c, "no %s in the content" % MIRA)
	var twin_a := _spawn_twin("twin_a", data)
	var twin_b := _spawn_twin("twin_b", data)
	await _wait(1.2)
	var drift := twin_a.global_position.distance_to(twin_b.global_position)
	if drift > 0.001:
		return fail(c, "two identical villagers drifted %.4fm apart" % drift)
	return succeeded(c, "both walked the identical path for 1.2s")


func _t_solid_and_component() -> Dictionary:
	var c := &"a_villager_is_solid_and_carries_an_interaction_component"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var missing: Array[String] = []
	for npc: Npc in manager.call("npcs"):
		if npc.collision_layer != PhysicsLayers.NPC:
			missing.append("%s is not on the NPC layer" % npc.data.id)
		if npc.get_node_or_null(^"CollisionShape3D") == null:
			missing.append("%s has no collider" % npc.data.id)
		if npc.get_node_or_null(^"Model") == null:
			missing.append("%s has no model" % npc.data.id)
		var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
		if component == null:
			missing.append("%s has no interaction component" % npc.data.id)
			continue
		if component.get_npc_ref() != npc:
			missing.append("%s's component points at somebody else" % npc.data.id)
		if component.npc_id_of() != npc.data.id:
			missing.append("%s's component reports the wrong id" % npc.data.id)
	if not missing.is_empty():
		return fail(c, ", ".join(missing))
	return succeeded(c, "all %d villagers are solid, drawn and interactable" % manager.call("count"))


func _t_no_definition() -> Dictionary:
	var c := &"a_villager_with_nothing_to_say_says_nothing"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc: Npc = manager.call("npcs")[0]
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component to ask")
	var id := npc.data.id
	# Set after `_ready`, deliberately: a definition-less villager added to a live tree
	# logs an engine error, and this case is about what the *rules* say, not about
	# surviving a bad spawn.
	npc.data = null
	var said := npc.describe()
	if said != "Nobody":
		return fail(c, "a definition-less villager describes itself as '%s'" % said)
	if component.interact(built["player"]):
		return fail(c, "a definition-less villager was talked to")
	if not _saw_talk_reason(&"nothing_to_say"):
		return fail(c, "no reason given for a villager with nothing to say")
	npc.data = NpcRegistry.get_npc(id)
	return succeeded(c, "refused as nothing_to_say, and said so")


# --- The rules ------------------------------------------------------------------


func _t_talk_faces() -> Dictionary:
	var c := &"talking_turns_a_villager_to_face_the_player"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc: Npc = manager.call("npcs")[0]
	var player: Node3D = built["player"]
	# Placed to one side rather than straight ahead, so "faced the player" cannot pass by
	# accident on a villager who happens to be pointing that way already.
	player.global_position = npc.global_position + Vector3(2.0, 0.0, 0.0)
	npc.wandering = false
	await _step(2)
	# Facing away to begin with, so the turn has somewhere to go.
	npc.rotation.y = PI * 0.5
	var before := npc.rotation.y
	if not bool(manager.call("talk", npc, player)):
		return fail(c, "talking to %s was refused" % npc.data.id)
	# Wait for the turn to land rather than counting frames: the turn is rate-limited, so
	# the question worth asking is whether they end up facing the player, and a fixed
	# frame budget would be asserting the turn *rate* instead — which is a tuning choice,
	# not a rule.
	var off_by := PI
	var ticks := 0
	while ticks < 240 and off_by > 0.2:
		await tree.physics_frame
		ticks += 1
		off_by = _facing_error(npc, player)
	if off_by > 0.25:
		return fail(c, "%s still faces %.2f rad from the player after %d ticks (yaw %.2f)" % [
			npc.data.id, off_by, ticks, npc.rotation.y,
		])
	if absf(wrapf(npc.rotation.y - before, -PI, PI)) < 0.1:
		return fail(c, "%s did not turn at all" % npc.data.id)
	if not npc.attending:
		return fail(c, "%s is not attending the conversation" % npc.data.id)
	return succeeded(c, "%s turned from %.2f to %.2f, %.2f rad off the player" % [
		npc.data.id, before, npc.rotation.y, off_by,
	])


## How far [param npc]'s forward axis is from the direction of [param player], in radians.
##
## The requirement stated as a player's own eyes would see it, rather than as a yaw
## number: a yaw assertion bakes in whichever sign convention the facing maths happens to
## use, which is exactly how a villager can turn its back on the player and still satisfy
## a test that "proves" it turned to face them.
func _facing_error(npc: Npc, player: Node3D) -> float:
	var forward := -npc.global_transform.basis.z
	var towards := player.global_position - npc.global_position
	towards.y = 0.0
	if forward.length() < 0.5 or towards.length() < 0.5:
		return PI
	return forward.normalized().angle_to(towards.normalized())


func _t_gift_both_halves() -> Dictionary:
	var c := &"a_gift_takes_the_item_and_moves_the_score_together"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var bag: Inventory = built["bag"]
	var state: Node = built["state"]
	if not _hold(state, HER_LOVED, 3):
		return fail(c, "could not put %d %s in hand" % [3, HER_LOVED])
	var before := bag.count(HER_LOVED)
	var points_before := npc.friendship.points
	var given := npc.gift_preview(HER_LOVED)
	if not bool(given.get("ok", false)):
		return fail(c, "the preview refused a gift the press was about to accept: %s" % str(given))
	if StringName(given.get("reaction", &"")) != NpcData.REACTION_LOVED:
		return fail(c, "Mira's reaction to her own loved gift is '%s'" % str(given.get("reaction", "")))
	if not bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "give_gift refused: %s" % _last_gift_reason())
	var after := bag.count(HER_LOVED)
	var points_after := npc.friendship.points
	# Both halves or it is not a test: a present that is still in the bag did not
	# transfer, and a score that moved without the item leaving is a printing press.
	if after != before - 1:
		return fail(c, "the bag went %d -> %d %s" % [before, after, HER_LOVED])
	if points_after - points_before != Friendship.POINTS_LOVED:
		return fail(c, "friendship went %d -> %d, expected +%d" % [
			points_before, points_after, Friendship.POINTS_LOVED,
		])
	return succeeded(c, "1 %s left the bag and friendship went %d -> %d" % [
		HER_LOVED, points_before, points_after,
	])


func _t_crop_gift() -> Dictionary:
	var c := &"a_harvested_crop_is_a_present_too"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var bag: Inventory = built["bag"]
	var state: Node = built["state"]
	# Mira loves parsnips, and a parsnip is a [CropData]: the harvested crop lands in the
	# bag under its crop id with no [ItemDefinition] behind it. Asking the item registry
	# whether that is giftable is what made the game's most natural present impossible —
	# the prompt said "Talk to Mira" while the player stood there holding her favourite
	# food.
	var crop := CropRegistry.get_crop(HER_PARSNIP)
	if crop == null:
		return fail(c, "no %s crop in the content" % HER_PARSNIP)
	if not NpcData.is_giftable_id(HER_PARSNIP):
		return fail(c, "a harvested crop is not giftable")
	if not _hold(state, HER_PARSNIP, 2):
		return fail(c, "could not put a %s in hand" % HER_PARSNIP)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var decision := component.preview(built["player"])
	if StringName(decision.get("action", &"")) != &"gift":
		return fail(c, "holding a %s the prompt offers '%s' (%s)" % [
			HER_PARSNIP, str(decision.get("action", "")), str(decision.get("text", "")),
		])
	if String(decision.get("text", "")) != "Give the %s" % crop.display_name:
		return fail(c, "the prompt says '%s', expected the crop's own name" % str(decision.get("text", "")))
	var before := bag.count(HER_PARSNIP)
	var points_before := npc.friendship.points
	if not bool(manager.call("give_gift", npc, HER_PARSNIP, built["player"])):
		return fail(c, "give_gift refused a crop: %s" % _last_gift_reason())
	if bag.count(HER_PARSNIP) != before - 1:
		return fail(c, "the bag went %d -> %d %s" % [before, bag.count(HER_PARSNIP), HER_PARSNIP])
	if npc.friendship.points - points_before != Friendship.POINTS_LOVED:
		return fail(c, "friendship went %d -> %d on a crop she loves" % [
			points_before, npc.friendship.points,
		])
	return succeeded(c, "1 %s left the bag and friendship went %d -> %d" % [
		HER_PARSNIP, points_before, npc.friendship.points,
	])


func _t_refused_gift_is_atomic() -> Dictionary:
	var c := &"a_refused_gift_leaves_the_bag_and_the_score_alone"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var bag: Inventory = built["bag"]
	var state: Node = built["state"]
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	# The weekly budget is spent, so this press is a refusal that costs nothing.
	npc.friendship.gifts_this_week = Friendship.WEEKLY_GIFT_LIMIT
	var bag_before := bag.count(HER_LOVED)
	var points_before := npc.friendship.points
	if bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "a gift was accepted with the week's budget already spent")
	if not _saw_gift_reason(&"gift_limit_reached"):
		return fail(c, "the refusal reason was '%s'" % _last_gift_reason())
	if bag.count(HER_LOVED) != bag_before:
		return fail(c, "a refused gift still took the item (%d -> %d)" % [
			bag_before, bag.count(HER_LOVED),
		])
	if npc.friendship.points != points_before:
		return fail(c, "a refused gift still scored (%d -> %d)" % [
			points_before, npc.friendship.points,
		])
	return succeeded(c, "refused as gift_limit_reached; bag and score untouched")


func _t_disliked_gift() -> Dictionary:
	var c := &"a_disliked_gift_is_taken_and_costs_friendship"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var bag: Inventory = built["bag"]
	var state: Node = built["state"]
	# Something she likes first, so there is friendship there to lose. A dislike at zero
	# is clamped to zero and would prove nothing about the cost.
	if not _hold(state, HER_LIKED, 1):
		return fail(c, "could not put %s in hand" % HER_LIKED)
	if not bool(manager.call("give_gift", npc, HER_LIKED, built["player"])):
		return fail(c, "the liked gift was refused: %s" % _last_gift_reason())
	var warm := npc.friendship.points
	if warm <= 0:
		return fail(c, "a liked gift left the friendship at %d" % warm)
	if not _hold(state, HER_DISLIKED, 1):
		return fail(c, "could not put %s in hand" % HER_DISLIKED)
	var stone_before := bag.count(HER_DISLIKED)
	if not bool(manager.call("give_gift", npc, HER_DISLIKED, built["player"])):
		return fail(c, "a disliked gift was refused: %s" % _last_gift_reason())
	if bag.count(HER_DISLIKED) != stone_before - 1:
		return fail(c, "the disliked gift did not leave the bag")
	# Taken *and* costly. A gift that is refused is safe; one that is accepted and
	# quietly scores nothing is the bug this case exists for.
	if npc.friendship.points != warm + Friendship.POINTS_DISLIKED:
		return fail(c, "friendship went %d -> %d on a disliked gift" % [
			warm, npc.friendship.points,
		])
	if npc.friendship.points >= 0 and npc.friendship.points == warm:
		return fail(c, "handing Mira a rock cost her nothing")
	return succeeded(c, "Mira took the rock and friendship went %d -> %d" % [
		warm, npc.friendship.points,
	])


func _t_tool_not_a_gift() -> Dictionary:
	var c := &"a_tool_in_hand_is_not_a_present"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var state: Node = built["state"]
	var bag: Inventory = built["bag"]
	if not _hold(state, &"axe", 1):
		return fail(c, "could not put the axe in hand")
	var preview := npc.gift_preview(&"axe")
	if bool(preview.get("ok", false)):
		return fail(c, "an axe is offered as a present")
	if StringName(preview.get("reason", &"")) != &"not_giftable":
		return fail(c, "the reason for refusing an axe is '%s'" % str(preview.get("reason", "")))
	# The key must not become dead: holding a rake and wanting to say hello is a normal
	# thing to want, so the same press has to talk instead.
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var decision := component.preview(built["player"])
	if StringName(decision.get("action", &"")) != &"talk":
		return fail(c, "holding an axe the key offers '%s' instead of talking" % str(decision.get("action", "")))
	var before := bag.count(&"axe")
	if not component.interact(built["player"]):
		return fail(c, "talking was refused while holding an axe")
	if bag.count(&"axe") != before:
		return fail(c, "the axe left the bag")
	return succeeded(c, "refused as not_giftable, and the key still says hello")


func _t_third_gift_refused() -> Dictionary:
	var c := &"the_third_gift_of_the_week_is_refused"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var state: Node = built["state"]
	# Two real gifts first, so the refusal is the third and not the first.
	for _gift: int in range(Friendship.WEEKLY_GIFT_LIMIT):
		if not _hold(state, HER_LIKED, 1):
			return fail(c, "could not put %s in hand" % HER_LIKED)
		if not bool(manager.call("give_gift", npc, HER_LIKED, built["player"])):
			return fail(c, "gift %d of the week was refused: %s" % [
				_gift + 1, _last_gift_reason(),
			])
	if npc.friendship.gifts_this_week != Friendship.WEEKLY_GIFT_LIMIT:
		return fail(c, "two gifts registered as %d" % npc.friendship.gifts_this_week)
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	if bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "the third gift of the week was accepted")
	if not _saw_gift_reason(&"gift_limit_reached"):
		return fail(c, "the third gift was refused as '%s'" % _last_gift_reason())
	return succeeded(c, "two accepted, the third refused as gift_limit_reached")


func _t_second_loved_refused() -> Dictionary:
	var c := &"a_second_loved_gift_the_same_day_is_refused"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var state: Node = built["state"]
	if not _hold(state, HER_LOVED, 2):
		return fail(c, "could not put two %s in hand" % HER_LOVED)
	if not bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "the first loved gift was refused: %s" % _last_gift_reason())
	if bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "the second loved gift was accepted")
	if not _saw_gift_reason(&"already_gifted_today"):
		return fail(c, "the second loved gift was refused as '%s'" % _last_gift_reason())
	# The daily cap must not have cost the weekly budget its second slot.
	if not npc.friendship.can_gift_today():
		return fail(c, "a refused second gift still spent the week")
	return succeeded(c, "one loved gift a day, refused as already_gifted_today")


func _t_rollover_clears_limits() -> Dictionary:
	var c := &"the_daily_gift_limits_clear_at_midnight"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var state: Node = built["state"]
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	if not bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "the loved gift was refused: %s" % _last_gift_reason())
	if npc.friendship.can_gift_loved_today():
		return fail(c, "the daily loved cap never closed")
	var bus := autoload(&"EventBus")
	if bus == null:
		return fail(c, "no EventBus to publish the day")
	bus.day_started.emit(2)
	await _step(2)
	if npc.friendship.loved_today != 0:
		return fail(c, "loved_today is %d the morning after" % npc.friendship.loved_today)
	if not npc.friendship.can_gift_loved_today():
		return fail(c, "the loved cap survived the day rollover")
	# The week is 28 days of four, so the first of the month is Monday. This is the one
	# place the weekly budget clears, and it has to be the *first*, not every day.
	if not _hold(state, HER_LIKED, 1):
		return fail(c, "could not put %s in hand" % HER_LIKED)
	if not bool(manager.call("give_gift", npc, HER_LIKED, built["player"])):
		return fail(c, "the day-2 gift was refused: %s" % _last_gift_reason())
	bus.day_started.emit(1)
	await _step(2)
	if npc.friendship.gifts_this_week != 0:
		return fail(c, "the week budget is %d on the first of the month" % npc.friendship.gifts_this_week)
	return succeeded(c, "daily cap cleared on day 2, weekly budget on the first")


func _t_wrong_item_refused() -> Dictionary:
	var c := &"giving_something_other_than_what_is_in_hand_is_refused"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var bag: Inventory = built["bag"]
	var state: Node = built["state"]
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	var before := bag.count(HER_DISLIKED)
	# The player swapped slots between reading the prompt and pressing the key.
	if bool(manager.call("give_gift", npc, HER_DISLIKED, built["player"])):
		return fail(c, "gave %s while holding %s" % [HER_DISLIKED, HER_LOVED])
	if not _saw_gift_reason(&"nothing_to_do"):
		return fail(c, "the refusal reason was '%s'" % _last_gift_reason())
	if bag.count(HER_DISLIKED) != before:
		return fail(c, "a refused gift took the wrong item")
	return succeeded(c, "refused as nothing_to_do, and took nothing")


func _t_empty_hand() -> Dictionary:
	var c := &"an_empty_hand_has_nothing_to_give"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var state: Node = built["state"]
	if not _hold(state, "", 0):
		return fail(c, "could not empty the player's hand")
	if bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		return fail(c, "gave a gift out of an empty hand")
	if not _saw_gift_reason(&"no_item_held"):
		return fail(c, "the refusal reason was '%s'" % _last_gift_reason())
	return succeeded(c, "refused as no_item_held")


func _t_undefined_stack() -> Dictionary:
	var c := &"a_stack_with_no_definition_behind_it_is_refused"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var bag: Inventory = built["bag"]
	if not _hold(built["state"], HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	# Rename the stack in place: a save from a build that had this item, or a definition
	# deleted after the save was written. Different from "not held" and from "not a
	# tool", and it has to say so.
	var stack: Inventory.ItemStack = bag.get_slot(0)
	if stack == null:
		return fail(c, "nothing in slot 0 to rename")
	stack.id = GHOST_ITEM
	var points_before := npc.friendship.points
	if bool(manager.call("give_gift", npc, GHOST_ITEM, built["player"])):
		return fail(c, "gave a stack with no definition behind it")
	if not _saw_gift_reason(&"no_item"):
		return fail(c, "the refusal reason was '%s'" % _last_gift_reason())
	if npc.friendship.points != points_before:
		return fail(c, "a refused gift still scored")
	return succeeded(c, "refused as no_item")


func _t_tier_change_published() -> Dictionary:
	var c := &"a_tier_change_is_published"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var state: Node = built["state"]
	# One short of a heart, so the gift below is the one that crosses the line.
	npc.friendship.points = Friendship.POINTS_PER_HEART - Friendship.POINTS_LOVED
	if npc.friendship.tier_name() != "Stranger":
		return fail(c, "setup: %d points already reads as '%s'" % [
			npc.friendship.points, npc.friendship.tier_name(),
		])
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	var seen: Array[Dictionary] = []
	var bus := autoload(&"EventBus")
	if bus == null:
		return fail(c, "no EventBus")
	var listener := func(npc_id: StringName, hearts: int, tier: String) -> void:
		seen.append({"id": npc_id, "hearts": hearts, "tier": tier})
	bus.npc_friendship_changed.connect(listener)
	if not bool(manager.call("give_gift", npc, HER_LOVED, built["player"])):
		bus.npc_friendship_changed.disconnect(listener)
		return fail(c, "the gift was refused: %s" % _last_gift_reason())
	bus.npc_friendship_changed.disconnect(listener)
	if seen.size() != 1:
		return fail(c, "%d tier changes published, expected 1" % seen.size())
	if StringName(seen[0]["id"]) != npc.data.id:
		return fail(c, "published for '%s'" % str(seen[0]["id"]))
	if npc.friendship.tier_name() != String(seen[0]["tier"]):
		return fail(c, "published '%s' but the friendship reads '%s'" % [
			str(seen[0]["tier"]), npc.friendship.tier_name(),
		])
	return succeeded(c, "crossing a heart published %s (%d hearts)" % [
		str(seen[0]["tier"]), int(seen[0]["hearts"]),
	])


# --- The save -------------------------------------------------------------------


func _t_cast_save() -> Dictionary:
	var c := &"the_whole_cast_save_round_trips"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var mira := _mira(manager)
	if mira == null:
		return fail(c, "no %s in the cast" % MIRA)
	mira.friendship.points = 640
	mira.friendship.gifts_this_week = 1
	var sable: Npc = manager.call("get_npc", &"sable")
	if sable != null:
		sable.friendship.points = 95
	var saved: Dictionary = manager.call("to_dict")
	if saved.size() != manager.call("count"):
		return fail(c, "the save holds %d villagers, the cast is %d" % [
			saved.size(), manager.call("count"),
		])
	for npc: Npc in manager.call("npcs"):
		npc.friendship.points = 0
		npc.friendship.gifts_this_week = 0
	manager.call("from_dict", saved)
	if mira.friendship.points != 640 or mira.friendship.gifts_this_week != 1:
		return fail(c, "%s came back on %d points (%d this week)" % [
			MIRA, mira.friendship.points, mira.friendship.gifts_this_week,
		])
	if sable != null and int(sable.friendship.points) != 95:
		return fail(c, "sable came back on %d points" % int(sable.friendship.points))
	return succeeded(c, "%d villagers round-tripped" % saved.size())


func _t_save_unknown_npc() -> Dictionary:
	var c := &"a_save_naming_a_villager_we_do_not_have_is_skipped"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var before: int = manager.call("count")
	var mira := _mira(manager)
	if mira == null:
		return fail(c, "no %s in the cast" % MIRA)
	mira.friendship.points = 300
	# Content gets cut between builds. A removed villager must not make an old save
	# unloadable, and must not be mistaken for a corrupted one.
	manager.call("from_dict", {
		&"a_villager_who_was_cut_from_the_game": {"points": 900},
		MIRA: {"points": 111},
	})
	if manager.call("count") != before:
		return fail(c, "the cast changed size: %d -> %d" % [before, manager.call("count")])
	if mira.friendship.points != 111:
		return fail(c, "%s is on %d points, expected the save's 111" % [
			MIRA, mira.friendship.points,
		])
	return succeeded(c, "an unknown villager was skipped and the rest still loaded")


# --- Through the real game ------------------------------------------------------


func _t_valley_spawns_cast() -> Dictionary:
	var c := &"the_valley_spawns_the_whole_cast"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var expected := NpcRegistry.all_npcs().size()
	if manager.call("count") != expected:
		return fail(c, "%d villagers in the valley, %d definitions on disk" % [
			manager.call("count"), expected,
		])
	var missing: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if manager.call("get_npc", data.id) == null:
			missing.append(String(data.id))
	if not missing.is_empty():
		return fail(c, "nobody by the name of: %s" % ", ".join(missing))
	return succeeded(c, "all %d villagers are standing in the valley" % expected)


func _t_reachable() -> Dictionary:
	var c := &"every_villager_can_be_reached_on_foot"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var space := _space_state(built)
	if space == null:
		return fail(c, "no physics space to test against")
	var probe := SphereShape3D.new()
	probe.radius = 0.4
	# Standing this close is comfortably inside the 3m reach, so a villager with nowhere
	# to stand is a content placement problem rather than a reach problem.
	var standing := 2.4
	var stuck: Array[String] = []
	for npc: Npc in manager.call("npcs"):
		var found := false
		for i: int in range(12):
			var angle := TAU * float(i) / 12.0
			var spot := npc.global_position + Vector3(
				cos(angle) * standing, 0.9, sin(angle) * standing
			)
			if _space_is_clear(space, probe, spot):
				found = true
				break
		if not found:
			stuck.append(String(npc.data.id))
	if not stuck.is_empty():
		return fail(c, "no standing spot within %.1fm of: %s" % [standing, ", ".join(stuck)])
	return succeeded(c, "all %d villagers can be walked up to" % manager.call("count"))


func _t_point_blank_prompt() -> Dictionary:
	var c := &"the_prompt_survives_walking_up_to_a_villager"
	# Found by playing, not by reasoning, and the same bug as `test_gathering`'s: a ray
	# does not hit a shape it starts inside, so a player who walks right up to somebody
	# would lose the prompt at exactly the range they naturally close to. Every other
	# case here stands well back, which is why the suite can be green and the game wrong.
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var npc: Npc = _mira(built["manager"])
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var aim := component.get_aim_point()
	for offset: Vector3 in [
		Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0), Vector3(0, 0, 0.9), Vector3(0, 0, -0.9),
	]:
		player.global_position = Vector3(aim.x + offset.x, 0.2, aim.z + offset.z)
		await _step(4)
		var camera := probe.get_camera()
		if camera == null:
			return fail(c, "no active camera in the viewport")
		var dir := (aim - camera.global_position).normalized()
		player.set_yaw(atan2(-dir.x, -dir.z))
		player.camera_rig.set_pitch(atan2(dir.y, Vector2(dir.x, dir.z).length()))
		await _step(3)
		probe.update_focus()
		if probe.get_focus() == component:
			var prompt := component.get_prompt(player)
			if not prompt.contains(String(npc.data.display_name)):
				return fail(c, "the prompt at %.1fm says '%s'" % [
					Vector2(offset.x, offset.z).length(), prompt,
				])
			return succeeded(c, "'%s' at %.1fm, inside the interaction volume" % [
				prompt, Vector2(offset.x, offset.z).length(),
			])
	return fail(c, "the crosshair lost the villager from 0.9m")


func _t_talk_through_input() -> Dictionary:
	var c := &"talking_to_a_villager_works_the_real_interact_key"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var npc: Npc = _mira(built["manager"])
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at %s: %s" % [MIRA, str(focused["why"])])
	var heard: Array[StringName] = []
	var bus := autoload(&"EventBus")
	var listener := func(npc_id: StringName) -> void: heard.append(npc_id)
	bus.npc_talked.connect(listener)
	# The real key, held long enough for the probe to notice, released like a player.
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	bus.npc_talked.disconnect(listener)
	if heard.size() != 1:
		return fail(c, "%d conversations from one press" % heard.size())
	if heard[0] != npc.data.id:
		return fail(c, "talked to '%s'" % str(heard[0]))
	if not npc.attending:
		return fail(c, "%s is not attending the player" % npc.data.id)
	return succeeded(c, "one press, one hello, to %s" % npc.data.id)


func _t_gift_through_input() -> Dictionary:
	var c := &"holding_a_gift_turns_the_same_key_into_a_present"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var npc: Npc = _mira(built["manager"])
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var bag: Inventory = built["bag"]
	if not _hold(built["state"], HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at %s: %s" % [MIRA, str(focused["why"])])
	# One key, two meanings, and the prompt is what says which.
	var prompt := component.get_prompt(player)
	if not prompt.begins_with("Give the"):
		return fail(c, "holding %s, the prompt says '%s'" % [HER_LOVED, prompt])
	var bag_before := bag.count(HER_LOVED)
	var points_before := npc.friendship.points
	var given: Array[Dictionary] = []
	var bus := autoload(&"EventBus")
	var listener := func(npc_id: StringName, item_id: StringName, reaction: StringName) -> void:
		given.append({"id": npc_id, "item": item_id, "reaction": reaction})
	bus.npc_gifted.connect(listener)
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	bus.npc_gifted.disconnect(listener)
	if given.size() != 1:
		return fail(c, "%d gifts from one press: %s" % [given.size(), str(given)])
	if StringName(given[0]["reaction"]) != NpcData.REACTION_LOVED:
		return fail(c, "published as '%s'" % str(given[0]["reaction"]))
	if bag.count(HER_LOVED) != bag_before - 1:
		return fail(c, "the %s is still in the bag" % HER_LOVED)
	if npc.friendship.points != points_before + Friendship.POINTS_LOVED:
		return fail(c, "friendship went %d -> %d" % [points_before, npc.friendship.points])
	return succeeded(c, "'%s' -> %d %s out of the bag, %d -> %d points" % [
		prompt, 1, HER_LOVED, points_before, npc.friendship.points,
	])


## The refusal says itself, on the prompt, before the press.
##
## The verb has to stay short — "Talk to Mira" is scannable, "Talk to Mira, who already has
## a gift from you today, because you gave them a wild berry at 07:20" is not — so the
## explanation is the note beside it. Without the note the prompt changes from "Give the
## Wild Berry" to "Talk to Mira" and the player has no way to tell a full villager from a
## game that lost track of what they are holding. Found by `tools/playtest_npc.gd`.
func _t_refusal_explains_itself() -> Dictionary:
	var c := &"a_refused_present_says_why_on_the_prompt"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var player: PlayerController = built["player"]

	if not _hold(built["state"], HER_LOVED, 2):
		return fail(c, "could not put two %s in hand" % HER_LOVED)
	var offered := component.get_prompt(player)
	var quiet := component.get_prompt_note(player)
	if not offered.begins_with("Give the"):
		return fail(c, "a fresh villager offers '%s'" % offered)
	if not quiet.is_empty():
		return fail(c, "nothing has been refused yet, but the note reads '%s'" % quiet)
	# Spend the day.
	if not bool(manager.call("give_gift", npc, HER_LOVED, player)):
		return fail(c, "the first %s was refused" % HER_LOVED)
	var after := component.get_prompt(player)
	var note := component.get_prompt_note(player)
	if after.begins_with("Give the"):
		return fail(c, "%s is full for the day and still promises '%s'" % [MIRA, after])
	if not after.begins_with("Talk to"):
		return fail(c, "the refused present left the prompt as '%s'" % after)
	if note.is_empty():
		return fail(c, "the present was refused and the prompt does not say so")
	if not note.contains(MIRA.capitalize()):
		return fail(c, "the note '%s' does not name who is full" % note)
	# And a tool, which was never a gift, has nothing to explain.
	if not _hold(built["state"], &"axe", 1):
		return fail(c, "could not put an axe in hand")
	if not component.get_prompt_note(player).is_empty():
		return fail(c, "holding an axe the note explains a refusal that was never attempted")
	return succeeded(c, "'%s' -> '%s' (%s)" % [offered, after, note])


## The refusal is published even though the press fell back to a greeting.
##
## One key both talks and gives, so the only way to reach a refusal through the keyboard is
## a present the villager will not take — and that press used to say hello and publish
## nothing. A distinct success event with no distinct failure is the one thing
## `AGENTS.md` forbids, and from the player's side it is worse: the berry stays in the bag
## and the game looks broken.
func _t_refusal_through_input() -> Dictionary:
	var c := &"a_refused_present_still_says_hello_and_publishes_itself"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var bag: Inventory = built["bag"]
	if not _hold(built["state"], HER_LOVED, 2):
		return fail(c, "could not put two %s in hand" % HER_LOVED)
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at %s: %s" % [MIRA, str(focused["why"])])

	# First present: taken.
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	if npc.friendship.points != Friendship.POINTS_LOVED:
		return fail(c, "the first press did not give the present (%d points)" % npc.friendship.points)
	var after_first := bag.count(HER_LOVED)

	# Second: refused, spoken about, and the hello still happens.
	var talked: Array[StringName] = []
	var bus := autoload(&"EventBus")
	var hello := func(npc_id: StringName) -> void: talked.append(npc_id)
	bus.npc_talked.connect(hello)
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	bus.npc_talked.disconnect(hello)

	if not _saw_gift_reason(&"already_gifted_today"):
		return fail(c, "the second press published %s" % str(_gift_failures))
	if talked.size() != 1 or talked[0] != npc.data.id:
		return fail(c, "the refused press said hello %d times: %s" % [talked.size(), str(talked)])
	if bag.count(HER_LOVED) != after_first:
		return fail(c, "a refused present took the %s anyway (%d left)" % [HER_LOVED, bag.count(HER_LOVED)])
	if not npc.attending:
		return fail(c, "%s is not attending after the refused press" % MIRA)
	return succeeded(c, "refused as already_gifted_today, still said hello, bag untouched")


## The label on screen agrees with the state, whenever it changes.
##
## Everything else in this suite asks the *component* what it would say, which is how a
## stale label survives: the component knows the truth, the HUD drew it once when the
## crosshair moved, and nothing ever compared the two. This drives the real HUD and reads
## the real [Label] through the three state changes a player can make without moving the
## crosshair — giving a present, switching hands, and being refused.
func _t_label_follows_state() -> Dictionary:
	var c := &"the_prompt_label_follows_the_state_it_describes"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]

	# The real HUD scene, in the same tree the probe is in, so it binds as it does in the
	# game rather than being poked directly.
	var hud_packed := load(HUD_SCENE) as PackedScene
	if hud_packed == null:
		return fail(c, "no HUD scene at %s" % HUD_SCENE)
	var hud := hud_packed.instantiate()
	_ensure_rig()
	_rig.add_child(hud)
	await _step(4)
	var label := hud.get_node_or_null(^"PromptContainer/PromptLabel") as Label
	if label == null:
		return fail(c, "the HUD has no prompt label")

	if not _hold(built["state"], HER_LOVED, 2):
		return fail(c, "could not put two %s in hand" % HER_LOVED)
	var focused := await _stand_and_focus(player, probe, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at %s: %s" % [MIRA, str(focused["why"])])
	if not label.text.contains("Give the"):
		return fail(c, "holding a present the label reads '%s'" % label.text)

	# Give it. The label has to notice without the crosshair moving.
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(4)
	if label.text.contains("Give the"):
		return fail(c, "%s is full for the day and the label still reads '%s'" % [MIRA, label.text])
	if not label.text.contains("gift from you today"):
		return fail(c, "the label does not explain the refusal: '%s'" % label.text)

	# Switch hands without looking away: no gift is offered for a hoe, and the explanation
	# goes with the present it was about. A hoe was never a refused gift, so the note has
	# nothing left to say.
	if not _hold(built["state"], &"axe", 1):
		return fail(c, "could not put an axe in hand")
	await _step(4)
	if label.text.contains("Give the"):
		return fail(c, "holding an axe the label still offers a gift: '%s'" % label.text)
	if label.text.contains("gift from you today"):
		return fail(c, "the label still explains a refused gift nobody is holding: '%s'" % label.text)
	return succeeded(c, "label tracked the gift, the refusal and the switch: '%s'" % label.text)


func _t_every_refusal_reason() -> Dictionary:
	var c := &"every_npc_refusal_has_its_own_reason"
	# Walks the vocabulary the [EventBus] documents and proves each is reachable, with a
	# value nothing else produces. Two rules sharing a reason is two different sentences
	# behind one value, and any listener keyed on it has to guess which happened.
	var seen: Dictionary = {}

	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var state: Node = built["state"]
	var npc := _mira(manager)
	if npc == null:
		return fail(c, "no %s in the cast" % MIRA)
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	if component == null:
		return fail(c, "no interaction component")
	var player: Node3D = built["player"]

	# no_npc: a component with no villager behind it.
	var orphan := NpcInteractable.new()
	orphan.name = "Orphan"
	_rig.add_child(orphan)
	if orphan.interact(player):
		return fail(c, "a component with no villager interacted")
	if not _saw_talk_reason(&"no_npc"):
		return fail(c, "no reason for a component with no villager")
	seen[&"no_npc"] = true
	orphan.queue_free()

	# nothing_to_say: a villager with no definition behind them.
	var id := npc.data.id
	npc.data = null
	if component.interact(player):
		npc.data = NpcRegistry.get_npc(id)
		return fail(c, "a villager with no definition was talked to")
	npc.data = NpcRegistry.get_npc(id)
	if not _saw_talk_reason(&"nothing_to_say"):
		return fail(c, "no reason for a villager with nothing to say")
	seen[&"nothing_to_say"] = true

	# no_npc_service: nothing in the tree is registered to talk to.
	manager.remove_from_group(NpcManager.SERVICE_GROUP)
	await _step(1)
	if component.interact(player):
		manager.add_to_group(NpcManager.SERVICE_GROUP)
		return fail(c, "a component with no manager interacted")
	manager.add_to_group(NpcManager.SERVICE_GROUP)
	await _step(1)
	if not _saw_talk_reason(&"no_npc_service"):
		return fail(c, "no reason for a missing manager")
	seen[&"no_npc_service"] = true

	# no_player_state: no bag to read a present out of, and no standing to report.
	state.get_parent().remove_child(state)
	await _step(1)
	if component.interact(player):
		_rig.add_child(state)
		return fail(c, "a component with no player state interacted")
	if bool(manager.call("give_gift", npc, HER_LOVED, player)):
		_rig.add_child(state)
		return fail(c, "a gift was given with no player state")
	_rig.add_child(state)
	await _step(1)
	if not _saw_talk_reason(&"no_player_state") or not _saw_gift_reason(&"no_player_state"):
		return fail(c, "no reason for a missing player state (talk=%s, gift=%s)" % [
			_last_talk_reason(), _last_gift_reason(),
		])
	seen[&"no_player_state"] = true

	# no_item_held: the player's hand is empty.
	if not _hold(state, "", 0):
		return fail(c, "could not empty the player's hand")
	if bool(manager.call("give_gift", npc, HER_LOVED, player)):
		return fail(c, "gave a gift out of an empty hand")
	if not _saw_gift_reason(&"no_item_held"):
		return fail(c, "no reason for an empty hand")
	seen[&"no_item_held"] = true

	# no_item: a stack with no definition behind it.
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	var stack: Inventory.ItemStack = (bag_of(state)).get_slot(0)
	stack.id = GHOST_ITEM
	if bool(manager.call("give_gift", npc, GHOST_ITEM, player)):
		return fail(c, "gave a stack with no definition behind it")
	if not _saw_gift_reason(&"no_item"):
		return fail(c, "no reason for a stack with no definition")
	seen[&"no_item"] = true

	# nothing_to_do: the press and the hand disagree about what is being given.
	if not _hold(state, HER_LOVED, 1):
		return fail(c, "could not put %s in hand" % HER_LOVED)
	if bool(manager.call("give_gift", npc, HER_DISLIKED, player)):
		return fail(c, "gave something other than what was in hand")
	if not _saw_gift_reason(&"nothing_to_do"):
		return fail(c, "no reason for a press and a hand that disagree")
	seen[&"nothing_to_do"] = true

	# not_giftable: a tool in hand. Refused as a *gift*, and the key still says hello.
	if not _hold(state, &"axe", 1):
		return fail(c, "could not put the axe in hand")
	var axe_preview := npc.gift_preview(&"axe")
	if StringName(axe_preview.get("reason", &"")) != &"not_giftable":
		return fail(c, "an axe is refused as '%s'" % str(axe_preview.get("reason", "")))
	seen[&"not_giftable"] = true

	# already_gifted_today: her second loved gift, on the same day.
	if not _hold(state, HER_LOVED, 2):
		return fail(c, "could not put two %s in hand" % HER_LOVED)
	if not bool(manager.call("give_gift", npc, HER_LOVED, player)):
		return fail(c, "the first loved gift was refused: %s" % _last_gift_reason())
	if bool(manager.call("give_gift", npc, HER_LOVED, player)):
		return fail(c, "her second loved gift was accepted")
	if not _saw_gift_reason(&"already_gifted_today"):
		return fail(c, "no reason for a second loved gift")
	seen[&"already_gifted_today"] = true

	# gift_limit_reached: the week's budget, spent. The accepted loved gift above took the
	# first slot, so this spends the second and the *third* is the refusal.
	if not _hold(state, HER_LIKED, 1):
		return fail(c, "could not put %s in hand" % HER_LIKED)
	if not bool(manager.call("give_gift", npc, HER_LIKED, player)):
		return fail(c, "the week's second gift was refused early: %s" % _last_gift_reason())
	if not _hold(state, HER_LIKED, 1):
		return fail(c, "could not put %s in hand" % HER_LIKED)
	if bool(manager.call("give_gift", npc, HER_LIKED, player)):
		return fail(c, "a third gift of the week was accepted")
	if not _saw_gift_reason(&"gift_limit_reached"):
		return fail(c, "the third gift was refused as '%s'" % _last_gift_reason())
	seen[&"gift_limit_reached"] = true

	var missing: Array[String] = []
	for reason: StringName in REFUSAL_REASONS:
		if not seen.has(reason):
			missing.append(String(reason))
	if not missing.is_empty():
		return fail(c, "documented but never produced: %s" % ", ".join(missing))
	return succeeded(c, "all %d refusal reasons are distinct and reachable" % REFUSAL_REASONS.size())


## Every refusal reason the [EventBus] documents for talking and giving, in one list.
##
## Duplicated here rather than read out of the bus, for the same reason the other
## vocabularies are: a list that is *derived* from the code under test cannot fail.
const REFUSAL_REASONS: Array[StringName] = [
	&"no_npc", &"no_npc_service", &"no_player_state", &"nothing_to_say",
	&"no_item_held", &"no_item", &"nothing_to_do", &"not_giftable",
	&"already_gifted_today", &"gift_limit_reached",
]


# --- Fixtures -------------------------------------------------------------------


## The real valley, a real player, a real [PlayerStateService] and a real cast.
##
## Loaded by path for the manager rather than named, for the documented reason: naming
## [NpcManager] here pulls its whole dependency chain into this file's compile, which is
## the `class_name` cycle trap. `test_gathering` does the same with [GatheringService].
##
## [param schedules] turns on the authored day before the node enters the tree, which
## is the only moment [member NpcManager.apply_schedules] can be set - `_ready` reads
## it, builds the walkability grid and points everyone at their first destination.
## Off by default so every other case in this file keeps the wandering cast it was
## written against.
func _build_world(schedules: bool = false) -> Dictionary:
	_reset_rig()
	var packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	if packed == null or player_packed == null or manager_script == null:
		return {}
	_ensure_rig()
	var world: WorldRoot = packed.instantiate()
	var player: PlayerController = player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)
	player.global_position = world.get_spawn_point()
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.call("grant_starter_loadout")
	# Spawn on ready, exactly as `main.gd` does, so the cast is placed the way the game
	# places it rather than by the fixture reaching in and moving people around.
	var manager: Node = manager_script.new()
	manager.name = "NpcManager"
	if schedules:
		manager.set("apply_schedules", true)
	_rig.add_child(manager)
	await _step(4)

	var probe := _find_first(player, "InteractionProbe") as InteractionProbe
	if probe == null:
		return {}
	var bus := autoload(&"EventBus")
	if bus != null:
		if not bus.npc_talk_failed.is_connected(_record_talk_failure):
			bus.npc_talk_failed.connect(_record_talk_failure)
		if not bus.npc_gift_failed.is_connected(_record_gift_failure):
			bus.npc_gift_failed.connect(_record_gift_failure)
	return {
		"world": world,
		"player": player,
		"probe": probe,
		"state": state,
		"manager": manager,
		"bag": state.get("inventory"),
	}


## Mira, or null with the reason already logged by the caller.
func _mira(manager: Node) -> Npc:
	return manager.call("get_npc", MIRA) as Npc


func bag_of(state: Node) -> Inventory:
	return state.get("inventory") as Inventory


## Puts [param item_id] in the player's hand and nowhere else.
##
## Empties the bag first so the item lands in slot 0, which is the only slot the
## hotbar can be looking at — an item in slot 20 is in the bag and not in the player's
## hand, which is a distinction this suite would otherwise rediscover one failure at a
## time. An empty [param item_id] empties the hand instead.
func _hold(state: Node, item_id: StringName, amount: int) -> bool:
	var bag := bag_of(state)
	if bag == null:
		return false
	_empty_bag(bag)
	if not item_id.is_empty():
		if int(bag.add(item_id, amount)) != amount:
			return false
	state.call("select_slot", 0)
	return true


func _empty_bag(bag: Inventory) -> void:
	# `set_contents([])`, not a loop over the registries: a stack whose id no definition
	# resolves to — which one of these cases deliberately authors — survives a loop that
	# only removes ids the registries know, and then sits in slot 0 as whatever the next
	# case is holding.
	bag.set_contents([])


## A second villager with [param data]'s exact identity, for the determinism case.
##
## Not [method NpcManager.spawn_npc]: the manager keys its cast by id, so a second Mira
## from the same method would collide with the first and the comparison would be
## against the wrong node.
func _spawn_twin(node_name: String, data: NpcData) -> Npc:
	var npc := Npc.new()
	npc.name = node_name
	# Data before the node enters the tree: `_ready` sizes the collider from it.
	npc.data = data
	npc.wandering = true
	_ensure_rig()
	_rig.add_child(npc)
	return npc


## Puts the player next to [param npc] and aims at [param component].
##
## Returns `{"focused": bool, "why": String}`. Several offsets rather than one, because
## the village is scattered and a fixed offset regularly leaves a tree between the
## camera and the villager, which is a failure that teaches nothing.
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
			why = "ray stopped at %s instead of %s" % [probe.get_focus().name, component.name]
	return {"focused": false, "why": why}


func _space_state(built: Dictionary) -> PhysicsDirectSpaceState3D:
	var world: WorldRoot = built["world"]
	if world == null:
		return null
	var camera := _find_first(world, "Camera3D") as Camera3D
	if camera != null:
		return camera.get_world_3d().direct_space_state
	var viewport := root().get_viewport()
	if viewport == null or viewport.world_3d == null:
		return null
	return viewport.world_3d.direct_space_state


## Whether a player-sized sphere fits at [param spot].
##
## Masks the world layer only, so a villager's own body does not report itself
## unreachable — the player is meant to stand *next* to them, and the NPC layer is not
## what the player collides with when walking up to somebody to talk.
func _space_is_clear(space: PhysicsDirectSpaceState3D, probe: SphereShape3D, spot: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, spot)
	query.collision_mask = PhysicsLayers.WORLD
	return space.intersect_shape(query, 1).is_empty()


func _record_talk_failure(npc_id: StringName, reason: StringName) -> void:
	_talk_failures.append({"npc": npc_id, "reason": reason})


func _record_gift_failure(npc_id: StringName, item_id: StringName, reason: StringName) -> void:
	_gift_failures.append({"npc": npc_id, "item": item_id, "reason": reason})


func _saw_talk_reason(reason: StringName) -> bool:
	for entry: Dictionary in _talk_failures:
		if StringName(entry["reason"]) == reason:
			return true
	return false


func _saw_gift_reason(reason: StringName) -> bool:
	for entry: Dictionary in _gift_failures:
		if StringName(entry["reason"]) == reason:
			return true
	return false


func _last_talk_reason() -> String:
	if _talk_failures.is_empty():
		return "nothing at all"
	return String(_talk_failures[-1]["reason"])


## The authored day, resolved against a real clock and a real content directory.
##
## Asserts three separate things because each fails differently: nobody resolves to
## nothing (an empty answer, which the fallback would happily swallow), somebody
## resolves to a place with no [LocationData] behind it (a schedule naming a street
## that does not exist), and *nobody* left home (a day that is written but never
## applies - the season or weather gate that no day satisfies).
func _t_schedules_resolve() -> Dictionary:
	var c := &"schedules_point_every_villager_at_a_real_place"
	var built := await _build_world(true)
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var clock := TimeService.find(_rig)
	if clock == null:
		return fail(c, "no TimeService in the rig")
	# Fixed rather than left at boot time: 10:00 on a clear spring morning is inside
	# every villager's working block, so the case says what it means whatever hour the
	# suite happened to be started at.
	clock.time.season = WorldTime.Season.SPRING
	clock.time.weather = WorldTime.Weather.SUN
	clock.time.hour = 10
	clock.time.minute = 0
	manager.call("refresh_schedules")

	var bad: Array[String] = []
	var posts := 0
	for npc: Npc in manager.call("npcs"):
		var home := StringName("%s_cottage" % npc.data.id)
		if npc.scheduled_location_id.is_empty():
			bad.append("%s resolved to nothing" % npc.data.id)
			continue
		if LocationRegistry.get_location(npc.scheduled_location_id) == null:
			bad.append("%s wants '%s', which has no location" % [
				npc.data.id, npc.scheduled_location_id,
			])
			continue
		if npc.scheduled_location_id == home:
			continue
		posts += 1
		if not npc.is_walking_to_post():
			bad.append("%s was sent to %s but is not going" % [
				npc.data.id, npc.scheduled_location_id,
			])
	if not bad.is_empty():
		return fail(c, "; ".join(bad))
	if posts == 0:
		return fail(c, "all %d villagers were still at home at 10:00, so nothing was tested" % (
			manager.call("count")
		))
	return succeeded(c, "%d of %d villagers are at a post at 10:00" % [
		posts, manager.call("count"),
	])


## One villager, the whole walk: leave home, arrive, and stay.
##
## The "and stays" half is the one that would be easy to leave out. Clearing the walk
## on arrival - the obvious way to tidy up - drops the villager straight back into
## wandering, and they amble off the orchard row they were sent to within a couple of
## seconds. Nothing about *arriving* would catch that; only watching afterwards does.
func _t_scheduled_walk() -> Dictionary:
	var c := &"a_scheduled_villager_walks_to_their_post_and_holds_it"
	var built := await _build_world(true)
	if built.is_empty():
		return fail(c, "could not build scene")
	var manager: Node = built["manager"]
	var clock := TimeService.find(_rig)
	if clock == null:
		return fail(c, "no TimeService in the rig")
	clock.time.season = WorldTime.Season.SPRING
	clock.time.weather = WorldTime.Weather.SUN
	clock.time.hour = 10
	clock.time.minute = 0
	manager.call("refresh_schedules")

	var npc := manager.call("get_npc", MIRA) as Npc
	if npc == null:
		return fail(c, "Mira is not in the cast")
	var place := LocationRegistry.get_location(npc.scheduled_location_id)
	if place == null:
		return fail(c, "Mira was sent to '%s', which has no location" % npc.scheduled_location_id)
	if npc.scheduled_location_id == StringName("%s_cottage" % MIRA):
		return fail(c, "Mira was still at home at 10:00, so there is no walk to watch")
	if not npc.is_walking_to_post():
		return fail(c, "Mira was sent to %s but is not walking there" % place.display_name)

	var target := place.ground_position()
	var start := npc.global_position.distance_to(target)
	if start < 1.2:
		return fail(c, "Mira started %.2fm from %s, too close to test a walk" % [
			start, place.display_name,
		])
	# Driven directly rather than by waiting on the engine's 60 Hz.
	#
	# This is the same two lines [method Npc._physics_process] runs - `_advance` then
	# `move_and_slide` - so what is under test is unchanged; only the waiting is, and
	# at 1.7 m/s a 25 m walk is fifteen seconds of wall clock that would otherwise be
	# spent proving nothing. The frame budget is derived from the distance so a longer
	# village or a slower villager does not start failing this case for the wrong
	# reason.
	var budget := clampi(int(start * 120.0) + 600, 600, 8000)
	var closest := start
	for _tick: int in range(budget):
		npc._advance(1.0 / 60.0)
		npc.move_and_slide()
		closest = minf(closest, npc.global_position.distance_to(target))
		if closest <= 1.2:
			break
	if closest > 1.2:
		return fail(c, "Mira got within %.2fm of %s but no closer (started %.1fm away)" % [
			closest, place.display_name, start,
		])
	if not npc.is_walking_to_post():
		return fail(c, "Mira arrived and then let go of her post")

	# The hold is checked on real frames, unlike the walk: the question is whether she
	# is still there once gravity, the clock and the manager's own tick have all had a
	# go at her.
	var arrived_at := npc.global_position
	for _tick: int in range(30):
		await _step(1)
	var drift := npc.global_position.distance_to(arrived_at)
	if drift > 1.5:
		return fail(c, "Mira walked %.2fm away from %s after arriving" % [
			drift, place.display_name,
		])
	return succeeded(c, "Mira covered %.1fm to %s and held it (wandered %.2fm)" % [
		start, place.display_name, drift,
	])


## The grid, from the outside: it exists, it saw the world's obstacles, and every
## named place in the valley is reachable from a doorstep.
##
## Reachability rather than "is this cell walkable", because a location can sit
## legitimately on a blocked cell - the well's anchor is next to the well - and what
## the game needs is that a villager sent there gets as close as a person can, which
## is exactly what [method NpcNavigation.find_path] snaps to.
func _t_navigation_grid() -> Dictionary:
	var c := &"the_walkability_grid_reaches_every_named_place"
	var built := await _build_world(true)
	if built.is_empty():
		return fail(c, "could not build scene")
	var nav := _find_first(_rig, "Navigation") as NpcNavigation
	if nav == null:
		return fail(c, "no Navigation node was built")
	if nav.astar == null:
		return fail(c, "the grid was never built")
	if nav.walkable_cells <= 0:
		return fail(c, "nothing at all is walkable")
	if nav.blocked_cells <= 0:
		# A probe that finds no obstacles did not probe: it would say a villager can
		# walk through the houses, and every later assertion would pass on that.
		return fail(c, "no cell was rejected, so the probes never ran")

	var from := LocationRegistry.get_location(&"mira_cottage")
	if from == null:
		return fail(c, "Mira's cottage is missing")
	var origin := from.ground_position()
	var bad: Array[String] = []
	for place: LocationData in LocationRegistry.all_locations():
		if nav.find_path(origin, place.ground_position()).is_empty():
			bad.append(String(place.id))
	if not bad.is_empty():
		return fail(c, "unreachable from Mira's cottage: %s" % ", ".join(bad))
	return succeeded(c, "%d walkable / %d blocked cells, and all %d places reachable" % [
		nav.walkable_cells, nav.blocked_cells, LocationRegistry.all_locations().size(),
	])


func _last_gift_reason() -> String:
	if _gift_failures.is_empty():
		return "nothing at all"
	return String(_gift_failures[-1]["reason"])


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "NpcTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
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
		await tree.physics_frame
		frames += 1


## First descendant named [param want], deep enough for our trees.
func _find_first(from: Node, want: String) -> Node:
	if from == null:
		return null
	if from.name == want:
		return from
	for child: Node in from.get_children():
		var found := _find_first(child, want)
		if found != null:
			return found
	return null