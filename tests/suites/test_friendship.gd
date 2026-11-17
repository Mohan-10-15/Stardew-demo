extends TestSuite
## M6, the relationship half: gifts that mean different things, a value the player
## can read, and a romance that ends with somebody living on the farm.
##
## ## Why this is its own suite
##
## Group 14 already owns "a gift leaves the bag and the score moves". This suite
## owns what was added after it: the *meaning* of the reaction, the birthday
## multiplier, the heart gates, the two romance transactions, the spouse's new
## home and day, and the panel that makes all of it visible. Keeping the two
## suites apart means a regression in one has a short list of suspects.
##
## ## Both halves or it is not a test
##
## Courtship asserts the success event *and* the stage; marriage asserts the event
## *and* the new address; the HUD asserts the label a player reads, not the
## friendship resource behind it. Every refusal is reached through the same rule
## the prompt asks, so a refusal cannot be worded one way on screen and another
## on the bus.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"
const NPC_MANAGER_SCRIPT := "res://scripts/npc/npc_manager.gd"
const DIALOGUE_SERVICE_SCRIPT := "res://scripts/dialogue/dialogue_service.gd"
const FRIENDSHIP_HUD_SCENE := "res://scenes/ui/friendship_hud.tscn"
const INTERACTION_HUD_SCENE := "res://scenes/ui/interaction_hud.tscn"
const RECORDER_SCRIPT := "res://tests/helpers/event_recorder.gd"

const MIRA := &"mira"
const HER_LOVED := &"wild_berry"
const HER_LIKED := &"spring_onion"
const HER_DISLIKED := &"stone"
const FARM_HOME := &"farm_home"
const GATED_JOB := &"q_odette_first_frost"

## Every refusal the courtship rule can publish, from the EventBus contract.
const COURT_REASONS: Array[StringName] = [
	&"no_npc", &"no_friendship", &"not_romanceable", &"not_enough_hearts",
	&"already_involved",
]
const PROPOSE_REASONS: Array[StringName] = [
	&"no_npc", &"no_friendship", &"not_romanceable", &"not_courting",
	&"not_enough_hearts", &"already_married",
]

var _rig: Node3D = null
var _watchers: Array[Dictionary] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		# --- content --------------------------------------------------------------
		&"every_villager_can_be_courted",
		&"the_farm_home_is_a_real_place_on_the_farm",
		&"every_candidate_has_a_spouse_day",
		&"a_friendship_gate_is_authored_and_reachable",
		# --- the score -------------------------------------------------------------
		&"a_new_relationship_has_no_romance",
		&"liked_and_disliked_gifts_pull_in_opposite_directions",
		&"courting_needs_six_hearts",
		&"proposing_needs_a_date_and_the_whole_meter",
		&"a_birthday_doubles_only_the_good_news",
		&"a_romance_save_round_trips_and_clamps",
		# --- the transactions -----------------------------------------------------
		&"courting_publishes_one_success_and_no_failure",
		&"every_court_refusal_has_its_own_reason",
		&"proposing_publishes_one_success_and_no_failure",
		&"every_proposal_refusal_has_its_own_reason",
		&"marriage_moves_a_villager_to_the_farm",
		&"marriage_survives_a_save_and_reload",
		&"a_birthday_gift_lands_twice_the_points",
		# --- conversation ---------------------------------------------------------
		&"every_tree_has_a_line_for_each_stage",
		&"a_romance_line_only_speaks_at_its_stage",
		&"the_conversation_context_carries_the_stage",
		# --- the readout ----------------------------------------------------------
		&"the_relationship_panel_shows_hearts_and_stage",
		# --- through the real game -----------------------------------------------
		&"the_prompt_offers_courtship_at_six_hearts",
		&"the_prompt_offers_marriage_at_ten_hearts",
		&"a_married_villager_is_talkable_again",
		&"the_prompt_label_follows_a_courtship",
	]


func setup() -> void:
	_rig = null


func teardown() -> void:
	Input.action_release(&"interact")
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	_stop_recorders()
	match case:
		&"every_villager_can_be_courted":
			return _t_candidates()
		&"the_farm_home_is_a_real_place_on_the_farm":
			return _t_farm_home()
		&"every_candidate_has_a_spouse_day":
			return _t_spouse_days()
		&"a_friendship_gate_is_authored_and_reachable":
			return _t_gate_content()
		&"a_new_relationship_has_no_romance":
			return _t_stages()
		&"liked_and_disliked_gifts_pull_in_opposite_directions":
			return _t_reactions()
		&"courting_needs_six_hearts":
			return _t_court_rule()
		&"proposing_needs_a_date_and_the_whole_meter":
			return _t_propose_rule()
		&"a_birthday_doubles_only_the_good_news":
			return _t_birthday_rule()
		&"a_romance_save_round_trips_and_clamps":
			return _t_romance_save()
		&"courting_publishes_one_success_and_no_failure":
			return await _t_court_events()
		&"every_court_refusal_has_its_own_reason":
			return await _t_court_reasons()
		&"proposing_publishes_one_success_and_no_failure":
			return await _t_propose_events()
		&"every_proposal_refusal_has_its_own_reason":
			return await _t_propose_reasons()
		&"marriage_moves_a_villager_to_the_farm":
			return await _t_marriage_world()
		&"marriage_survives_a_save_and_reload":
			return await _t_marriage_save()
		&"a_birthday_gift_lands_twice_the_points":
			return await _t_birthday_gift()
		&"every_tree_has_a_line_for_each_stage":
			return _t_tree_content()
		&"a_romance_line_only_speaks_at_its_stage":
			return _t_stage_selection()
		&"the_conversation_context_carries_the_stage":
			return await _t_context()
		&"the_relationship_panel_shows_hearts_and_stage":
			return await _t_hud()
		&"the_prompt_offers_courtship_at_six_hearts":
			return await _t_court_through_input()
		&"the_prompt_offers_marriage_at_ten_hearts":
			return await _t_propose_through_input()
		&"a_married_villager_is_talkable_again":
			return await _t_talk_after_marriage()
		&"the_prompt_label_follows_a_courtship":
			return await _t_prompt_follows_courtship()
	return fail(case, "no case implementation for %s" % case)


# --- Content --------------------------------------------------------------------


func _t_candidates() -> Dictionary:
	var c := &"every_villager_can_be_courted"
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if not data.romanceable:
			bad.append(String(data.id))
	return check_equals(c, bad, [] as Array[String],
		"romance is a casting decision, but a valley where nobody can be courted has no M6 path")


func _t_farm_home() -> Dictionary:
	var c := &"the_farm_home_is_a_real_place_on_the_farm"
	var place := LocationRegistry.get_location(FARM_HOME)
	if place == null:
		return fail(c, "no '%s' location was authored" % FARM_HOME)
	if not place.is_valid():
		return fail(c, "'%s' is not a valid location: %s" % [FARM_HOME, place.describe()])
	if place.kind != LocationData.KIND_HOME:
		return fail(c, "'%s' is a '%s', not a home" % [FARM_HOME, str(place.kind)])
	# Inside the fence (0,-20 ± 11/8), outside the 14x10 plot (±7/5).
	var inside_fence := absf(place.position.x) < 11.0 \
		and absf(place.position.y + 20.0) < 8.0
	var outside_plot := absf(place.position.x) > 7.0 \
		or absf(place.position.y + 20.0) > 5.0
	if not inside_fence or not outside_plot:
		return fail(c, "'%s' at %s is in a wall or in the cabbages" % [
			FARM_HOME, str(place.position),
		])
	return succeeded(c, "%s at %s" % [FARM_HOME, str(place.position)])


func _t_spouse_days() -> Dictionary:
	var c := &"every_candidate_has_a_spouse_day"
	var bad: Array[String] = []
	for data: NpcData in NpcRegistry.all_npcs():
		if not data.romanceable:
			continue
		var id := StringName("%s_spouse" % data.id)
		var schedule := ScheduleRegistry.schedule_for(id)
		if schedule == null:
			bad.append("%s has no spouse day" % data.id)
			continue
		if not schedule.is_valid():
			bad.append("%s spouse day is invalid" % data.id)
			continue
		var single := ScheduleRegistry.schedule_for(data.id)
		if single != null and schedule.describe() == single.describe():
			bad.append("%s spouse day is just their single day" % data.id)
		var first := schedule.entries[0].location
		var last := schedule.entries[schedule.entries.size() - 1].location
		if first != FARM_HOME or last != FARM_HOME:
			bad.append("%s spouse day starts at %s and ends at %s" % [
				data.id, str(first), str(last),
			])
	return check_equals(c, bad, [] as Array[String])


func _t_gate_content() -> Dictionary:
	var c := &"a_friendship_gate_is_authored_and_reachable"
	var gated: Array[StringName] = []
	for data: QuestData in QuestRegistry.all_quests():
		if not data.gates_on_hearts():
			continue
		gated.append(data.id)
		if data.min_hearts < 1 or data.min_hearts > Friendship.MAX_HEARTS:
			return fail(c, "%s needs %d hearts, which nobody can have" % [
				data.id, data.min_hearts,
			])
	if gated.is_empty():
		return fail(c, "no quest is gated, so friendship gates nothing the player wants")
	return succeeded(c, "%d gated job(s), all reachable" % gated.size())


# --- The score -------------------------------------------------------------------


func _t_stages() -> Dictionary:
	var c := &"a_new_relationship_has_no_romance"
	var f := Friendship.new()
	if f.romance != Friendship.STAGE_NONE or f.is_dating() or f.is_married():
		return fail(c, "a new friendship is already involved")
	if f.romance_stage_name() != "":
		return fail(c, "a stranger has stage '%s'" % f.romance_stage_name())
	return succeeded(c, "new friendships start at stage none")


func _t_reactions() -> Dictionary:
	var c := &"liked_and_disliked_gifts_pull_in_opposite_directions"
	var liked := Friendship.new().award(NpcData.REACTION_LIKED)
	var disliked_f := Friendship.new()
	# Start above zero: a disliked gift from a stranger clamps at zero and its
	# real cost is invisible, which would say nothing about the reaction's sign.
	disliked_f.points = Friendship.POINTS_PER_HEART
	var disliked := disliked_f.award(NpcData.REACTION_DISLIKED)
	var neutral := Friendship.new().award(NpcData.REACTION_NEUTRAL)
	if liked <= neutral or neutral <= 0 or disliked >= 0:
		return fail(c, "liked %d, neutral %d, disliked %d" % [liked, neutral, disliked])
	return succeeded(c, "liked +%d, neutral +%d, disliked %d" % [liked, neutral, disliked])


func _t_court_rule() -> Dictionary:
	var c := &"courting_needs_six_hearts"
	var f := Friendship.new()
	if f.court_refusal() != &"not_enough_hearts" or f.court():
		return fail(c, "a stranger was courted")
	f.add_hearts(Friendship.COURT_HEARTS)
	if not f.court_refusal().is_empty() or not f.court() or not f.is_dating():
		return fail(c, "six hearts did not open courtship")
	if f.court():
		return fail(c, "a dating villager was courted twice")
	return succeeded(c, "courtship opened at %d hearts" % Friendship.COURT_HEARTS)


func _t_propose_rule() -> Dictionary:
	var c := &"proposing_needs_a_date_and_the_whole_meter"
	var f := Friendship.new()
	if f.propose_refusal() != &"not_courting" or f.propose():
		return fail(c, "a stranger was proposed to")
	f.add_hearts(Friendship.PROPOSE_HEARTS)
	if f.propose_refusal() != &"not_courting" or f.propose():
		return fail(c, "ten hearts without a date was enough")
	# Date at ten, then drop below the cap: the not_enough_hearts arm needs both
	# the dating stage and a heart count that has fallen short of the proposal.
	f.points = Friendship.POINTS_PER_HEART * (Friendship.PROPOSE_HEARTS - 1)
	f.court()
	if f.propose_refusal() != &"not_enough_hearts":
		return fail(c, "a date below ten hearts has no reason")
	f.add_hearts(Friendship.MAX_HEARTS)
	if not f.propose() or not f.is_married():
		return fail(c, "ten hearts while dating did not marry")
	return succeeded(c, "marriage needs a date and %d hearts" % Friendship.PROPOSE_HEARTS)


func _t_birthday_rule() -> Dictionary:
	var c := &"a_birthday_doubles_only_the_good_news"
	var good := Friendship.new()
	var good_plain := Friendship.new()
	var bad := Friendship.new()
	var bad_plain := Friendship.new()
	var liked_day := good.award(NpcData.REACTION_LIKED, true)
	var liked_plain := good_plain.award(NpcData.REACTION_LIKED)
	var disliked_day := bad.award(NpcData.REACTION_DISLIKED, true)
	var disliked_plain := bad_plain.award(NpcData.REACTION_DISLIKED)
	if liked_day != liked_plain * Friendship.BIRTHDAY_MULTIPLIER:
		return fail(c, "birthday liked %d vs plain %d" % [liked_day, liked_plain])
	if disliked_day != disliked_plain:
		return fail(c, "a birthday made a disliked gift hurt twice as much")
	if good.gifts_today != 1 or bad.gifts_today != 1:
		return fail(c, "the birthday changed the gift counters")
	return succeeded(c, "+%d liked on a birthday, %d disliked" % [liked_day, disliked_day])


func _t_romance_save() -> Dictionary:
	var c := &"a_romance_save_round_trips_and_clamps"
	var f := Friendship.new()
	f.add_hearts(Friendship.PROPOSE_HEARTS)
	f.court()
	f.propose()
	var restored := Friendship.new()
	restored.from_dict(f.to_dict())
	if not restored.is_married() or restored.romance_stage_name() != "married":
		return fail(c, "marriage did not survive the round trip")
	restored.from_dict({"romance": 9})
	if restored.romance != Friendship.STAGE_MARRIED:
		return fail(c, "a hand-edited stage 9 was trusted")
	restored.from_dict({"romance": -4})
	if restored.romance != Friendship.STAGE_NONE:
		return fail(c, "a negative stage was trusted")
	return succeeded(c, "marriage round-tripped and an edited save was clamped")


# --- The transactions -------------------------------------------------------------


func _t_court_events() -> Dictionary:
	var c := &"courting_publishes_one_success_and_no_failure"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npcs"][MIRA]
	npc.friendship.add_hearts(Friendship.COURT_HEARTS)
	var ok := _recorder(&"romance_started")
	var refused := _recorder(&"romance_started_failed")
	if not manager.court(npc, built["player"]):
		return fail(c, "courtship was refused at %d hearts" % Friendship.COURT_HEARTS)
	if ok.count != 1 or refused.count != 0:
		return fail(c, "%d successes and %d failures from one courtship" % [
			ok.count, refused.count,
		])
	if StringName(ok.arg(0)) != MIRA:
		return fail(c, "published for '%s'" % str(ok.arg(0)))
	_stop_recorders()
	return succeeded(c, "one romance_started, no failure, stage now '%s'" % \
		npc.friendship.romance_stage_name())


func _t_court_reasons() -> Dictionary:
	var c := &"every_court_refusal_has_its_own_reason"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npcs"][MIRA]
	var refused := _recorder(&"romance_started_failed")
	var seen: Array[StringName] = []
	manager.court(null, built["player"])
	seen.append(_reason(refused))
	var no_friend := Npc.new()
	no_friend.data = npc.data
	# In the tree so its collider RIDs are freed with the rig, not leaked at exit.
	_rig.add_child(no_friend)
	# `_ready` creates a fresh friendship; remove it so the no_friendship arm is
	# actually reached rather than the no-heart gate on a brand-new resource.
	no_friend.friendship = null
	manager.court(no_friend, built["player"])
	seen.append(_reason(refused))
	var not_candidate := Npc.new()
	not_candidate.data = npc.data.duplicate() as NpcData
	not_candidate.data.romanceable = false
	not_candidate.friendship = Friendship.new()
	_rig.add_child(not_candidate)
	manager.court(not_candidate, built["player"])
	seen.append(_reason(refused))
	manager.court(npc, built["player"])
	seen.append(_reason(refused))
	npc.friendship.add_hearts(Friendship.COURT_HEARTS)
	manager.court(npc, built["player"])
	seen.append(_reason(refused))
	manager.court(npc, built["player"])
	seen.append(_reason(refused))
	_stop_recorders()
	var unique: Array[StringName] = []
	for reason: StringName in seen:
		if not unique.has(reason):
			unique.append(reason)
	if unique.size() != COURT_REASONS.size():
		return fail(c, "courtship yielded %d distinct reasons: %s" % [
			unique.size(), str(unique),
		])
	for reason: StringName in COURT_REASONS:
		if not unique.has(reason):
			return fail(c, "courtship never published '%s'" % reason)
	return succeeded(c, "%d courtship refusals, none shared" % unique.size())


func _t_propose_events() -> Dictionary:
	var c := &"proposing_publishes_one_success_and_no_failure"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npcs"][MIRA]
	npc.friendship.add_hearts(Friendship.PROPOSE_HEARTS)
	npc.friendship.court()
	var ok := _recorder(&"npc_married")
	var refused := _recorder(&"npc_propose_failed")
	if not manager.propose(npc, built["player"]):
		return fail(c, "marriage was refused at ten hearts while dating")
	if ok.count != 1 or refused.count != 0:
		return fail(c, "%d marriages and %d failures from one proposal" % [
			ok.count, refused.count,
		])
	_stop_recorders()
	return succeeded(c, "one npc_married, no failure, stage now '%s'" % \
		npc.friendship.romance_stage_name())


func _t_propose_reasons() -> Dictionary:
	var c := &"every_proposal_refusal_has_its_own_reason"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npcs"][MIRA]
	var refused := _recorder(&"npc_propose_failed")
	var seen: Array[StringName] = []
	manager.propose(null, built["player"])
	seen.append(_reason(refused, 1))
	var no_friend := Npc.new()
	no_friend.data = npc.data
	# In the tree so its collider RIDs are freed with the rig, not leaked at exit.
	_rig.add_child(no_friend)
	# `_ready` creates a fresh friendship; remove it so the no_friendship arm is
	# actually reached rather than the no-heart gate on a brand-new resource.
	no_friend.friendship = null
	manager.propose(no_friend, built["player"])
	seen.append(_reason(refused, 1))
	var not_candidate := Npc.new()
	not_candidate.data = npc.data.duplicate() as NpcData
	not_candidate.data.romanceable = false
	not_candidate.friendship = Friendship.new()
	_rig.add_child(not_candidate)
	manager.propose(not_candidate, built["player"])
	seen.append(_reason(refused, 1))
	manager.propose(npc, built["player"])
	seen.append(_reason(refused, 1))
	npc.friendship.add_hearts(Friendship.PROPOSE_HEARTS)
	manager.propose(npc, built["player"])
	seen.append(_reason(refused, 1))
	# A date at ten hearts, then a fall back below the cap: this is the one arm
	# that needs the *dating* stage as well as a heart count.
	npc.friendship.court()
	npc.friendship.points = Friendship.POINTS_PER_HEART * (Friendship.PROPOSE_HEARTS - 1)
	manager.propose(npc, built["player"])
	seen.append(_reason(refused, 1))
	npc.friendship.add_hearts(Friendship.MAX_HEARTS)
	manager.propose(npc, built["player"])
	seen.append(_reason(refused, 1))
	manager.propose(npc, built["player"])
	seen.append(_reason(refused, 1))
	_stop_recorders()
	var unique: Array[StringName] = []
	for reason: StringName in seen:
		if not unique.has(reason):
			unique.append(reason)
	for reason: StringName in PROPOSE_REASONS:
		if not unique.has(reason):
			return fail(c, "a proposal never published '%s'; got %s" % [
				reason, str(unique),
			])
	if unique.size() != PROPOSE_REASONS.size():
		return fail(c, "%d proposal reasons instead of %d: %s" % [
			unique.size(), PROPOSE_REASONS.size(), str(unique),
		])
	return succeeded(c, "%d proposal refusals, none shared" % unique.size())


func _t_marriage_world() -> Dictionary:
	var c := &"marriage_moves_a_villager_to_the_farm"
	var built := await _build_game(true)
	if built.is_empty():
		return fail(c, "could not build the world with schedules")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npcs"][MIRA]
	npc.friendship.add_hearts(Friendship.PROPOSE_HEARTS)
	npc.friendship.court()
	if not manager.propose(npc, built["player"]):
		return fail(c, "the proposal was refused")
	var place := LocationRegistry.get_location(FARM_HOME)
	if npc.home_location_id() != FARM_HOME:
		return fail(c, "home id is '%s', not '%s'" % [str(npc.home_location_id()), FARM_HOME])
	if npc.home_position().distance_to(place.position) > 0.001:
		return fail(c, "home is %s, farm is %s" % [
			str(npc.home_position()), str(place.position),
		])
	var schedule := npc.get_schedule()
	if schedule == null or schedule.npc_id != StringName("%s_spouse" % MIRA):
		return fail(c, "a married Mira follows '%s'" % (
			str(schedule.npc_id) if schedule != null else "no schedule"
		))
	return succeeded(c, "%s now lives at %s and keeps the spouse day" % [MIRA, FARM_HOME])


func _t_marriage_save() -> Dictionary:
	var c := &"marriage_survives_a_save_and_reload"
	var built := await _build_game(true)
	if built.is_empty():
		return fail(c, "could not build the world with schedules")
	var manager: NpcManager = built["manager"]
	var npc: Npc = built["npcs"][MIRA]
	npc.friendship.add_hearts(Friendship.PROPOSE_HEARTS)
	npc.friendship.court()
	manager.propose(npc, built["player"])
	var saved: Dictionary = manager.call("to_dict")
	# Wipe the runtime consequences; only the save knows the marriage now.
	npc.friendship.romance = Friendship.STAGE_NONE
	npc.clear_home_override()
	manager.call("from_dict", saved)
	if not npc.friendship.is_married():
		return fail(c, "marriage was lost on load")
	if npc.home_location_id() != FARM_HOME:
		return fail(c, "the restored spouse has no farm address")
	var schedule := npc.get_schedule()
	if schedule == null or schedule.npc_id != StringName("%s_spouse" % MIRA):
		return fail(c, "the restored spouse lost their day")
	return succeeded(c, "marriage, address and spouse day all came back from the save")


func _t_birthday_gift() -> Dictionary:
	var c := &"a_birthday_gift_lands_twice_the_points"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var clock := TimeService.new()
	clock.name = "Clock"
	clock.running = false
	_rig.add_child(clock)
	var npc: Npc = built["npcs"][MIRA]
	var data: NpcData = npc.data
	clock.time.season = data.birthday_season
	clock.time.day_of_month = data.birthday_day
	if not data.is_birthday_on(clock.time.season, clock.time.day_of_month):
		return fail(c, "setup: the clock is not on Mira's birthday")
	if not _hold(built["state"], HER_LIKED, 1):
		return fail(c, "could not put %s in hand" % HER_LIKED)
	var manager: NpcManager = built["manager"]
	var before := npc.friendship.points
	if not manager.give_gift(npc, HER_LIKED, built["player"]):
		return fail(c, "the birthday gift was refused")
	var gained := npc.friendship.points - before
	if gained != Friendship.POINTS_LIKED * Friendship.BIRTHDAY_MULTIPLIER:
		return fail(c, "a birthday liked gift gained %d, not %d" % [
			gained, Friendship.POINTS_LIKED * Friendship.BIRTHDAY_MULTIPLIER,
		])
	return succeeded(c, "on her birthday Mira gained %d points from a liked gift" % gained)


# --- Conversation -----------------------------------------------------------------


func _t_tree_content() -> Dictionary:
	var c := &"every_tree_has_a_line_for_each_stage"
	var bad: Array[String] = []
	for tree: DialogueTree in DialogueRegistry.all_trees():
		var dating := false
		var married := false
		for entry: DialogueEntry in tree.entries:
			if entry.min_romance == Friendship.STAGE_DATING:
				dating = true
			elif entry.min_romance == Friendship.STAGE_MARRIED:
				married = true
		if not dating or not married:
			bad.append("%s has dating=%s married=%s" % [
				tree.npc_id, dating, married,
			])
	return check_equals(c, bad, [] as Array[String])


func _t_stage_selection() -> Dictionary:
	var c := &"a_romance_line_only_speaks_at_its_stage"
	var tree := DialogueTree.new()
	tree.npc_id = MIRA
	var fallback := DialogueEntry.new()
	fallback.id = &"greeting"
	fallback.text = "Hello."
	var dating := DialogueEntry.new()
	dating.id = &"dating"
	dating.text = "We are courting."
	dating.min_romance = Friendship.STAGE_DATING
	var married := DialogueEntry.new()
	married.id = &"married"
	married.text = "We are married."
	married.min_romance = Friendship.STAGE_MARRIED
	tree.entries = [fallback, dating, married]
	var single := DialogueService.select(tree, {"romance": Friendship.STAGE_NONE, "hearts": 0}, {})
	var dating_line := DialogueService.select(tree, {"romance": Friendship.STAGE_DATING, "hearts": 0}, {})
	var married_line := DialogueService.select(tree, {"romance": Friendship.STAGE_MARRIED, "hearts": 0}, {})
	if single == null or single.id != &"greeting":
		return fail(c, "a stranger heard '%s'" % (single.id if single != null else "nothing"))
	if dating_line == null or dating_line.id != &"dating":
		return fail(c, "a dating villager heard '%s'" % (
			str(dating_line.id) if dating_line != null else "nothing"
		))
	if married_line == null or married_line.id != &"married":
		return fail(c, "a married villager heard '%s'" % (
			str(married_line.id) if married_line != null else "nothing"
		))
	var missing := DialogueService.select(tree, {"hearts": 0}, {})
	if missing == null or missing.id != &"greeting":
		return fail(c, "a context with no stage matched a stage-gated line")
	return succeeded(c, "each stage spoke its own line, and no stage spoke early")


func _t_context() -> Dictionary:
	var c := &"the_conversation_context_carries_the_stage"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var script := load(DIALOGUE_SERVICE_SCRIPT) as GDScript
	var service: Node = script.new()
	service.name = "DialogueService"
	_rig.add_child(service)
	var npc: Npc = built["npcs"][MIRA]
	npc.friendship.add_hearts(Friendship.COURT_HEARTS)
	npc.friendship.court()
	var ctx: Dictionary = service.call("build_context", MIRA)
	if int(ctx.get("romance", -999)) != Friendship.STAGE_DATING:
		return fail(c, "context says stage %s, friendship says dating" % str(ctx.get("romance")))
	if int(ctx.get("hearts", -1)) < Friendship.COURT_HEARTS:
		return fail(c, "the context lost the heart count")
	return succeeded(c, "the conversation can ask what stage the relationship is at")


# --- The readout -------------------------------------------------------------------


func _t_hud() -> Dictionary:
	var c := &"the_relationship_panel_shows_hearts_and_stage"
	var built := await _build_cast()
	if built.is_empty():
		return fail(c, "could not stand up the cast")
	var packed := load(FRIENDSHIP_HUD_SCENE) as PackedScene
	if packed == null:
		return fail(c, "the generated panel does not load")
	var hud: CanvasLayer = packed.instantiate() as CanvasLayer
	_rig.add_child(hud)
	await _step(2)
	var lines := hud.call("row_texts") as PackedStringArray
	if lines.size() != built["npcs"].size():
		return fail(c, "%d rows for %d villagers" % [lines.size(), built["npcs"].size()])
	var row := _row_for(lines, MIRA)
	if row.is_empty() or not row.contains("0/10"):
		return fail(c, "Mira's row reads '%s'" % row)
	var npc: Npc = built["npcs"][MIRA]
	var manager: NpcManager = built["manager"]
	manager.grant_hearts(MIRA, 2)
	await _step(2)
	row = _row_for(hud.call("row_texts") as PackedStringArray, MIRA)
	if not row.contains("2/10"):
		return fail(c, "after two hearts Mira's row still reads '%s'" % row)
	npc.friendship.add_hearts(Friendship.COURT_HEARTS - 2)
	manager.court(npc, built["player"])
	await _step(2)
	row = _row_for(hud.call("row_texts") as PackedStringArray, MIRA)
	if not row.contains("dating"):
		return fail(c, "after courtship Mira's row still reads '%s'" % row)
	return succeeded(c, "the panel followed hearts and the courtship without being asked twice")


# --- Through the real game ---------------------------------------------------------


func _t_court_through_input() -> Dictionary:
	var c := &"the_prompt_offers_courtship_at_six_hearts"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the world")
	var npc: Npc = built["npcs"][MIRA]
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	var focused := await _focus(built, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at Mira: %s" % str(focused["why"]))
	npc.friendship.add_hearts(Friendship.COURT_HEARTS)
	var prompt := component.get_prompt(built["player"])
	if not prompt.contains("Court Mira"):
		return fail(c, "at %d hearts the prompt says '%s'" % [
			npc.friendship.hearts(), prompt,
		])
	var heard := _recorder(&"romance_started")
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	# Read before stopping: `stop()` clears the recorder so a later case cannot
	# inherit this one's events, which also wipes the count we are asserting on.
	if heard.count != 1 or not npc.friendship.is_dating():
		_stop_recorders()
		return fail(c, "%d courtships, dating=%s" % [heard.count, npc.friendship.is_dating()])
	_stop_recorders()
	return succeeded(c, "'%s' + one press = dating" % prompt)


func _t_propose_through_input() -> Dictionary:
	var c := &"the_prompt_offers_marriage_at_ten_hearts"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the world")
	var npc: Npc = built["npcs"][MIRA]
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	var focused := await _focus(built, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at Mira: %s" % str(focused["why"]))
	npc.friendship.add_hearts(Friendship.PROPOSE_HEARTS)
	npc.friendship.court()
	var prompt := component.get_prompt(built["player"])
	if not prompt.contains("Propose to Mira"):
		return fail(c, "at ten hearts while dating the prompt says '%s'" % prompt)
	var heard := _recorder(&"npc_married")
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	if heard.count != 1 or not npc.friendship.is_married():
		_stop_recorders()
		return fail(c, "%d marriages, married=%s" % [heard.count, npc.friendship.is_married()])
	_stop_recorders()
	return succeeded(c, "'%s' + one press = married" % prompt)


func _t_talk_after_marriage() -> Dictionary:
	var c := &"a_married_villager_is_talkable_again"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the world")
	var npc: Npc = built["npcs"][MIRA]
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	var focused := await _focus(built, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at Mira: %s" % str(focused["why"]))
	npc.friendship.add_hearts(Friendship.PROPOSE_HEARTS)
	npc.friendship.court()
	npc.friendship.propose()
	var prompt := component.get_prompt(built["player"])
	if not prompt.contains("Talk to Mira"):
		return fail(c, "a married villager's prompt says '%s'" % prompt)
	return succeeded(c, "'%s' — the wedding did not delete the conversation" % prompt)


## The label must change when the relationship does, without the crosshair moving.
##
## The regression `tools/playtest_friendship.gd` found: a courtship moves no hearts,
## so `npc_friendship_changed` never fires, and the prompt kept promising an action
## the key had already stopped performing. This drives the generated HUD scene and
## reads its real Label at each stage.
func _t_prompt_follows_courtship() -> Dictionary:
	var c := &"the_prompt_label_follows_a_courtship"
	var built := await _build_game()
	if built.is_empty():
		return fail(c, "could not build the world")
	var packed := load(INTERACTION_HUD_SCENE) as PackedScene
	if packed == null:
		return fail(c, "the interaction HUD does not load")
	var hud: Node = packed.instantiate()
	_rig.add_child(hud)
	await _step(4)
	var label := hud.get_node_or_null(^"PromptContainer/PromptLabel") as Label
	if label == null:
		return fail(c, "the HUD has no prompt label")
	var npc: Npc = built["npcs"][MIRA]
	var component := npc.get_node_or_null(^"AimVolume/Interactable") as NpcInteractable
	var focused := await _focus(built, npc, component)
	if not bool(focused["focused"]):
		return fail(c, "could not aim at Mira: %s" % str(focused["why"]))
	# Through the manager so the HUD hears the heart change the way it does in the
	# game: a bare write to the friendship resource would leave the label stale for
	# a reason that has nothing to do with the romance bug under test.
	built["manager"].grant_hearts(MIRA, Friendship.COURT_HEARTS)
	await _step(2)
	# A job outranks a courtship on the same key; take it as a player would.
	var taken := 0
	while (label.text.contains("Ask ") or label.text.contains("Hand in")) and taken < 3:
		Input.action_press(&"interact")
		await _wait(0.3)
		Input.action_release(&"interact")
		await _step(3)
		taken += 1
	if not label.text.contains("Court Mira"):
		return fail(c, "before courtship the label says '%s'" % label.text)
	var talked := _recorder(&"npc_talked")
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	if not npc.friendship.is_dating():
		_stop_recorders()
		return fail(c, "the press did not start a courtship")
	# Mira turns to face the player, which makes her aim volume leave the ray for a
	# frame. One press must still be one interaction: a second fire hit "Talk to
	# Mira" and opened a paused dialogue on top of the courtship. Found by playing.
	if talked.count != 0:
		_stop_recorders()
		return fail(c, "one court press also published %d greetings" % talked.count)
	_stop_recorders()
	if label.text.contains("Court Mira"):
		return fail(c, "after courtship the label still says '%s'" % label.text)
	built["manager"].grant_hearts(MIRA, Friendship.PROPOSE_HEARTS - Friendship.COURT_HEARTS)
	await _step(2)
	if not label.text.contains("Propose to Mira"):
		return fail(c, "at ten hearts the label still says '%s'" % label.text)
	Input.action_press(&"interact")
	await _wait(0.3)
	Input.action_release(&"interact")
	await _step(3)
	if not npc.friendship.is_married():
		return fail(c, "the press did not marry Mira")
	if not label.text.contains("Talk to Mira"):
		return fail(c, "after marriage the label still says '%s'" % label.text)
	return succeeded(c, "the label followed courtship, ten hearts and the wedding")


# --- Fixtures and helpers ----------------------------------------------------------


## A cast and a player, no world: enough for the rules, which never look at the
## terrain. Schedules are off, so no navigation grid is built for these cases.
func _build_cast() -> Dictionary:
	_reset_rig()
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	if state_script == null or manager_script == null:
		return {}
	_ensure_rig()
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var player := Node3D.new()
	player.name = "Player"
	_rig.add_child(player)
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	_rig.add_child(manager)
	await _step(3)
	var npcs: Dictionary = {}
	for data: NpcData in NpcRegistry.all_npcs():
		var npc := manager.get_npc(data.id)
		if npc == null:
			return {}
		npcs[data.id] = npc
	return {
		"state": state, "player": player, "manager": manager, "npcs": npcs,
	}


## The real valley and the real interaction probe, for the cases that press a key.
func _build_game(schedules: bool = false) -> Dictionary:
	_reset_rig()
	var world_packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	var state_script := load(PLAYER_STATE_SCRIPT) as GDScript
	var manager_script := load(NPC_MANAGER_SCRIPT) as GDScript
	if world_packed == null or player_packed == null or state_script == null \
			or manager_script == null:
		return {}
	_ensure_rig()
	var world: WorldRoot = world_packed.instantiate()
	var player: PlayerController = player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)
	player.global_position = world.get_spawn_point()
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.call("grant_starter_loadout")
	var manager: NpcManager = manager_script.new()
	manager.name = "NpcManager"
	manager.apply_schedules = schedules
	_rig.add_child(manager)
	await _step(5)
	var probe := _find_first(player, "InteractionProbe") as InteractionProbe
	var npcs: Dictionary = {}
	for data: NpcData in NpcRegistry.all_npcs():
		var npc := manager.get_npc(data.id)
		if npc == null:
			return {}
		npcs[data.id] = npc
	if probe == null or state.get("inventory") == null:
		return {}
	return {
		"world": world, "player": player, "probe": probe, "state": state,
		"manager": manager, "npcs": npcs, "bag": state.get("inventory"),
	}


## Stands the player in front of a villager and aims, trying four sides because
## a tree between the camera and the person is a harness failure, not a game one.
func _focus(built: Dictionary, npc: Npc, component: NpcInteractable) -> Dictionary:
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	if component == null:
		return {"focused": false, "why": "no interaction component"}
	var aim := component.get_aim_point()
	var why := "no direction worked"
	for offset: Vector3 in [
		Vector3(0, 0, 2.2), Vector3(0, 0, -2.2), Vector3(2.2, 0, 0), Vector3(-2.2, 0, 0),
	]:
		player.global_position = Vector3(aim.x + offset.x, 0.2, aim.z + offset.z)
		await _step(4)
		var camera := probe.get_camera()
		if camera == null:
			return {"focused": false, "why": "no active camera"}
		var dir := (aim - camera.global_position).normalized()
		player.set_yaw(atan2(-dir.x, -dir.z))
		player.camera_rig.set_pitch(atan2(dir.y, Vector2(dir.x, dir.z).length()))
		await _step(3)
		probe.update_focus()
		if probe.get_focus() == component:
			return {"focused": true, "why": ""}
		why = "ray stopped at %s" % (
			probe.get_focus().name if probe.get_focus() != null else "nothing"
		)
	return {"focused": false, "why": why}


func _hold(state: Node, item_id: StringName, amount: int) -> bool:
	var bag: Inventory = state.get("inventory") as Inventory
	if bag == null:
		return false
	bag.set_contents([])
	if int(bag.add(item_id, amount)) != amount:
		return false
	state.call("select_slot", 0)
	return true


func _recorder(signal_name: StringName) -> Object:
	var script := load(RECORDER_SCRIPT) as GDScript
	if script == null:
		return null
	var recorder: Object = script.new()
	var bus := autoload(&"EventBus")
	recorder.watch(bus, signal_name)
	_watchers.append({"bus": bus, "signal": signal_name, "rec": recorder})
	return recorder


func _stop_recorders() -> void:
	for watcher: Dictionary in _watchers:
		watcher["rec"].call("stop", watcher["bus"], watcher["signal"])
	_watchers = []


## The row whose text names [param npc_id], or "" when the panel omitted them.
func _row_for(lines: PackedStringArray, npc_id: StringName) -> String:
	for line: String in lines:
		# The row uses the display name ("Mira"), the id is lower case.
		if line.findn(npc_id) >= 0:
			return line
	return ""


func _reason(recorder: Object, index: int = 1) -> StringName:
	if recorder == null:
		return &""
	return StringName(recorder.arg(index))


func _find_first(node: Node, node_name: String) -> Node:
	if node == null:
		return null
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := _find_first(child, node_name)
		if found != null:
			return found
	return null


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "FriendshipTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	_stop_recorders()
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


func _wait(seconds: float, frame_ceiling: int = 900) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline and frames < frame_ceiling:
		await tree.process_frame
		frames += 1
