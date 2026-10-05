class_name QuestService
extends Node
## Tracks which jobs the player holds, how far along each is, and pays them out.
##
## ## Why this listens rather than being called
##
## A quest objective is satisfied by things that happen in other systems — a parsnip is
## harvested by the farm, a tree is felled by the gathering service, somebody is spoken to
## by the NPC manager. If this service had to be called by each of them, the quest system
## would be a dependency of every system and every feature that happened to move an item
## would have to know quests exist. Instead it subscribes to [EventBus], which is what
## [member EventBus] exists for, and every system stays ignorant of it.
##
## ## Why completion is a question and not a flag
##
## Nothing sets a quest "complete". [method _on_npc_talked] asks
## [method QuestObjective.is_satisfied_by] every time somebody is spoken to, and
## [method turn_in] asks it again before paying anything out. That means a quest cannot be
## completed without its objective being satisfied — the roadmap's one hard requirement for
## this group — and it means an objective that gets satisfied by accident (the player
## happened to have five parsnips in the bag) is noticed at the counter rather than never.

const SERVICE_GROUP := &"quest_service"

## Why an offer failed. Enumerated rather than free strings so the UI can translate each one
## and a test can assert the vocabulary is closed.
const REASON_UNKNOWN_QUEST := &"unknown_quest"
const REASON_ALREADY_ACTIVE := &"already_active"
const REASON_ALREADY_TURNED_IN := &"already_turned_in"
const REASON_ON_COOLDOWN := &"on_cooldown"
const REASON_WRONG_VILLAGER := &"wrong_villager"
const REASON_NO_PLAYER_STATE := &"no_player_state"
const REASON_BAG_TOO_FULL := &"bag_too_full"
const REASON_OBJECTIVE_INCOMPLETE := &"objective_incomplete"
const REASON_MISSING_ITEMS := &"missing_items"

## Every refusal reason, for a content test that asserts the vocabulary is closed.
const REASONS: Array[StringName] = [
	REASON_UNKNOWN_QUEST, REASON_ALREADY_ACTIVE, REASON_ALREADY_TURNED_IN,
	REASON_ON_COOLDOWN, REASON_WRONG_VILLAGER, REASON_NO_PLAYER_STATE,
	REASON_BAG_TOO_FULL, REASON_OBJECTIVE_INCOMPLETE, REASON_MISSING_ITEMS,
]

## The player. Assigned by [Main] like every other service; kept nullable so a test can hold
## a service with no player and observe refusals rather than crashing.
var player_state: PlayerStateService = null
## The NPC system, for heart rewards. Assigned by [Main]; nullable so a test can pay out a
## gold-only reward without standing up a village. See [method _manager].
var npc_manager: NpcManager = null

var _progress: Dictionary = {}
var _order: Array[StringName] = []


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	# `bind`ed rather than `connect`ed: a service that is freed and respawned by a test
	# must not leave dead connections behind, and `CONNECT_ONE_SHOT` is not the shape here.
	EventBus.item_added.connect(_on_item_added)
	EventBus.resource_collected.connect(_on_resource_collected)
	EventBus.item_purchased.connect(_on_item_purchased)
	EventBus.npc_talked.connect(_on_npc_talked)
	EventBus.day_started.connect(_on_day_started)
	Log.info("Quest", "Quest service ready")


func _exit_tree() -> void:
	if EventBus.item_added.is_connected(_on_item_added):
		EventBus.item_added.disconnect(_on_item_added)
	if EventBus.resource_collected.is_connected(_on_resource_collected):
		EventBus.resource_collected.disconnect(_on_resource_collected)
	if EventBus.item_purchased.is_connected(_on_item_purchased):
		EventBus.item_purchased.disconnect(_on_item_purchased)
	if EventBus.npc_talked.is_connected(_on_npc_talked):
		EventBus.npc_talked.disconnect(_on_npc_talked)
	if EventBus.day_started.is_connected(_on_day_started):
		EventBus.day_started.disconnect(_on_day_started)


# -- Queries ----------------------------------------------------------------------------------

## Every job in the world, or only the ones [param npc_id] could offer.
func all_quests(npc_id: StringName = &"") -> Array[QuestData]:
	if npc_id.is_empty():
		return QuestRegistry.all_quests()
	return QuestRegistry.quests_from(npc_id)


## What [param npc_id] would say if spoken to right now.
##
## Every refusal on this path publishes [signal EventBus.quest_turned_in_failed] with a
## reason and returns false, for the reason [method NpcManager.talk] documents: a keypress
## that does nothing and says nothing is a crash report.
##
## Offered rather than both offered and handed-in on one press. One key talking to one
## person should not also complete a two-week delivery, and folding "hand it back" into
## "talk" would make it impossible to ask somebody how they are without ending their job.
## The first job [param npc_id] would hand the player right now, or an empty [StringName].
##
## "Would offer", as opposed to "is on offer": this is the one a prompt wants, so a
## villager carrying three jobs names the first rather than asking the player to choose
## from a menu nobody designed.
func next_offer_from(npc_id: StringName) -> StringName:
	for data: QuestData in QuestRegistry.quests_from(npc_id):
		var progress: QuestProgress = _progress.get(data.id)
		if progress != null and progress.is_active():
			continue
		if progress != null and progress.is_turned_in():
			# A finished job is not offered again until it is actually available again. A
			# one-off never is; a weekly comes back when its cooldown has run out, and
			# asking a villager about work next Tuesday should not silently skip it.
			if progress.can_be_offered(data.repeats):
				return data.id
			continue
		return data.id
	return &""


## The first finished job [param npc_id] could be paid out for, or an empty [StringName].
##
## Ordered by [method _turn_in_rank] so a villager offering three finished jobs pays the
## delivery first — the one whose objective the player has visibly satisfied by standing
## there holding the thing.
func ready_to_turn_in_from(npc_id: StringName) -> StringName:
	var finished := finished_quests_from(npc_id)
	return finished[0].id if not finished.is_empty() else &""


## What a job is called, for a prompt. An unknown id answers "" rather than null so a
## caller can print it straight into a string.
func title_of(quest_id: StringName) -> String:
	var data := QuestRegistry.get_quest(quest_id)
	return data.title if data != null else ""


## Pays out [param quest_id], which must be finished.
##
## [param npc_id] is who the player is standing in front of, passed in by
## [NpcInteractable] so a quest cannot be handed in to a bystander. Empty means "don't
## care", which is what a test and the service's own callers use.
##
## Offered and performed as separate steps on purpose. One keypress talking to one person
## should not also complete a two-week delivery, and folding a hand-in into a greeting would
## make it impossible to ask somebody how they are without ending their job.
func turn_in(quest_id: StringName, actor: Node = null, npc_id: StringName = &"") -> bool:
	var data := QuestRegistry.get_quest(quest_id)
	if data == null:
		EventBus.quest_turned_in_failed.emit(quest_id, npc_id, REASON_UNKNOWN_QUEST)
		return false
	if not npc_id.is_empty() and npc_id != data.giver:
		# Refused rather than paid: the whole point of a hand-in is that the person who
		# asked for the thing is the person who takes it.
		EventBus.quest_turned_in_failed.emit(quest_id, npc_id, REASON_WRONG_VILLAGER)
		return false
	var progress: QuestProgress = _progress.get(quest_id)
	if progress == null or not progress.is_active():
		EventBus.quest_turned_in_failed.emit(quest_id, npc_id, REASON_ALREADY_TURNED_IN)
		return false
	var held := _held_count(data.objective)
	if not data.objective.is_satisfied_by(progress, held):
		# Two different refusals, because a player needs to be told which one happened.
		# "Bring me five parsnips" when you gathered five and spent them is not the same
		# sentence as "bring me five parsnips" when you have gathered none.
		var reason := REASON_OBJECTIVE_INCOMPLETE
		if data.objective.needs_an_item() and progress.collected >= data.objective.count:
			reason = REASON_MISSING_ITEMS
		EventBus.quest_turned_in_failed.emit(quest_id, npc_id, reason)
		return false
	_pay(data, actor)
	progress.note_turned_in()
	EventBus.quest_turned_in.emit(quest_id, data.giver)
	Log.info("Quest", "Turned in '%s' for %s" % [quest_id, data.reward.describe()])
	return true


## Whether [param data] could be paid out right now: in hand, objective met.
func _can_pay(data: QuestData) -> bool:
	var progress: QuestProgress = _progress.get(data.id)
	if progress == null or not progress.is_active():
		return false
	return data.objective.is_satisfied_by(progress, _held_count(data.objective))


## Takes [param quest_id] on, if it is on offer.
##
## The same check-then-act order as [method NpcManager.give_gift]: every refusal is checked
## before anything changes, so a refused acceptance leaves no trace.
func accept(quest_id: StringName, _actor: Node = null) -> bool:
	var data := QuestRegistry.get_quest(quest_id)
	if data == null:
		EventBus.quest_accepted_failed.emit(quest_id, REASON_UNKNOWN_QUEST)
		return false
	var progress: QuestProgress = _progress.get(quest_id)
	if progress != null and progress.is_active():
		EventBus.quest_accepted_failed.emit(quest_id, REASON_ALREADY_ACTIVE)
		return false
	# Whether a repeatable is available again is decided before anything is written, and the
	# answer is remembered rather than acted on. Resetting here and checking the player
	# afterwards would reopen a paid weekly job and then refuse it for a full bag, leaving
	# the player holding a job they had already finished.
	var reopening := false
	if progress != null and progress.is_turned_in():
		# A one-off is finished for good, which is a different sentence from "not until
		# next week" and the player will read the wrong one if they are merged.
		if data.repeats == QuestData.REPEATS_ONCE:
			EventBus.quest_accepted_failed.emit(quest_id, REASON_ALREADY_TURNED_IN)
			return false
		if not progress.can_be_offered(data.repeats):
			EventBus.quest_accepted_failed.emit(quest_id, REASON_ON_COOLDOWN)
			return false
		reopening = true
	var state := _player_state()
	if state == null or state.inventory == null:
		EventBus.quest_accepted_failed.emit(quest_id, REASON_NO_PLAYER_STATE)
		return false
	if data.objective.needs_an_item():
		# Refused here rather than at the counter. A quest the player can accept and then
		# never finish because their bag filled up in the meantime is a bug they report;
		# this is the one moment it is still the author's job to say no. `can_fit` rather
		# than a free-slot count, because a partly filled stack is room.
		if not state.inventory.can_fit(data.objective.item_id, data.objective.count):
			EventBus.quest_accepted_failed.emit(quest_id, REASON_BAG_TOO_FULL)
			return false
	if reopening:
		progress.reset_for_repeat()
	elif progress == null:
		progress = QuestProgress.create(quest_id)
		_progress[quest_id] = progress
		_order.append(quest_id)
	EventBus.quest_accepted.emit(quest_id, data.giver)
	Log.info("Quest", "Accepted '%s': %s" % [quest_id, data.describe_objective()])
	return true


## How far [param quest_id] has got, or null when the player has never heard of it.
func get_progress(quest_id: StringName) -> QuestProgress:
	return _progress.get(quest_id)


## Whether the player is currently holding [param quest_id].
func is_active(quest_id: StringName) -> bool:
	var progress: QuestProgress = _progress.get(quest_id)
	return progress != null and progress.is_active()


## Whether [param quest_id]'s objective is satisfied right now.
##
## The same question [method turn_in] asks before it pays out, exposed so a prompt can say
## "bring me five parsnips (you have three)" without the UI reaching into the objective.
func is_ready_to_turn_in(quest_id: StringName) -> bool:
	var data := QuestRegistry.get_quest(quest_id)
	if data == null:
		return false
	var progress: QuestProgress = _progress.get(quest_id)
	if progress == null or not progress.is_active():
		return false
	return data.objective.is_satisfied_by(progress, _held_count(data.objective))


## Everything in hand, in the order it was accepted.
func active_quests() -> Array[QuestData]:
	var out: Array[QuestData] = []
	for id: StringName in _order:
		var progress: QuestProgress = _progress.get(id)
		if progress == null or not progress.is_active():
			continue
		var data := QuestRegistry.get_quest(id)
		if data != null:
			out.append(data)
	return out


## How many of [param objective]'s item the player is holding.
func _held_count(objective: QuestObjective) -> int:
	if objective == null or not objective.needs_an_item():
		return 0
	var state := _player_state()
	if state == null or state.inventory == null:
		return 0
	return state.inventory.count(objective.item_id)


# -- Objective progress -----------------------------------------------------------------------

func _on_item_added(item_id: StringName, amount: int) -> void:
	_note_gathered(item_id, amount)


## Wood from a tree and stone from a boulder are gathered, not harvested, and the gathering
## system publishes [signal EventBus.resource_collected] because "did that log reach my bag"
## is a different question from "did anything change" — a full bag leaves the log lying on
## the ground. Listening to only [signal EventBus.item_added] would therefore leave the
## firewood and foundations jobs permanently unfinishable: the two quests the valley's
## gathering economy exists to serve, counting nothing.
func _on_resource_collected(item_id: StringName, amount: int) -> void:
	_note_gathered(item_id, amount)


## Buying is arriving. The shop pays straight into the bag and publishes
## [signal EventBus.item_purchased], so a player who buys the parsnips Mira asked for rather
## than growing them has still done what she asked. Refusing to count it would make the
## objective a statement about where an item came from, which no quest in the valley says.
func _on_item_purchased(item_id: StringName, quantity: int, _total: int) -> void:
	_note_gathered(item_id, quantity)


## The one place a `collect` objective moves, whatever put the item in the bag.
func _note_gathered(item_id: StringName, amount: int) -> void:
	for quest_id: StringName in _order:
		var progress: QuestProgress = _progress.get(quest_id)
		if progress == null or not progress.is_active():
			continue
		var data := QuestRegistry.get_quest(quest_id)
		if data == null or data.objective.kind != QuestObjective.KIND_COLLECT:
			continue
		if data.objective.item_id != item_id:
			continue
		if progress.collected >= data.objective.count:
			# Already enough. Not recorded, so a job paid twice cannot be inflated by
			# harvesting more of the same thing afterwards.
			continue
		# Capped rather than merely guarded above. The guard stops the *next* delivery
		# counting, but one gathering of five when four were needed still has to leave the
		# tally at the ask: a journal reading "29 of 20" is a visible bug, and 29 is what
		# gets written to the save.
		progress.note_item_added(mini(amount, data.objective.count - progress.collected))
		_emit_progress(quest_id, data, progress)


func _on_npc_talked(npc_id: StringName) -> void:
	for quest_id: StringName in _order:
		var progress: QuestProgress = _progress.get(quest_id)
		if progress == null or not progress.is_active():
			continue
		var data := QuestRegistry.get_quest(quest_id)
		if data == null:
			continue
		var objective := data.objective
		if objective == null or not objective.is_completed_by_talking():
			continue
		if objective.target_npc != npc_id:
			continue
		# Recorded for both kinds. A `talk` is done the moment it is spoken, and a
		# `deliver` needs this *and* the item in the bag — which is why
		# [method QuestObjective.is_satisfied_by] asks for both on a delivery. Without
		# this, iron ore in the bag is enough and the player never has to find Bram.
		if progress.spoke_to_target:
			# Already spoken to. Re-announcing would make a second conversation look
			# like new progress on a journal the player has not changed.
			continue
		progress.spoke_to_target = true
		_emit_progress(quest_id, data, progress)


func _on_day_started(_day: int) -> void:
	for quest_id: StringName in _order:
		var progress: QuestProgress = _progress.get(quest_id)
		if progress != null:
			progress.new_day()


func _emit_progress(quest_id: StringName, data: QuestData, progress: QuestProgress) -> void:
	var objective := data.objective
	if objective == null:
		return
	EventBus.quest_progress_changed.emit(
		quest_id, objective.current_amount(progress), objective.required_amount(),
	)


# -- Payout -----------------------------------------------------------------------------------

## The order here is the design, inherited from [method NpcManager.give_gift]: **check,
## take, then score**. The items leave the bag before any reward is paid, so a bag that
## would not actually release them never pays out, and a half-paid quest is at least a quest
## whose objective is already recorded as met.
func _pay(data: QuestData, _actor: Node) -> void:
	var state := _player_state()
	if state == null:
		return
	var objective := data.objective
	if objective != null and objective.needs_an_item():
		state.inventory.remove(objective.item_id, objective.count)
	for id: StringName in data.reward.distinct_items():
		state.inventory.add(id, data.reward.item_amount)
	if data.reward.gold > 0 and state.wallet != null:
		state.wallet.add(data.reward.gold)
	for heart: QuestHeartReward in data.reward.hearts:
		if heart == null:
			continue
		# Through the NPC system rather than by editing a Friendship: it owns the
		# friendship_changed event and the per-villager state, and a quest that awarded
		# hearts behind its back would leave a tier change unannounced.
		var manager := _manager()
		if manager != null:
			manager.grant_hearts(heart.npc, heart.amount)


# -- Save -------------------------------------------------------------------------------------

## The whole quest log, as one dictionary.
##
## Keyed by quest id rather than an array, for the same reason [method NpcManager.to_dict] is:
## the next group adds jobs, and a positional list would silently reassign progress to the
## wrong quest on load.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _order:
		var progress: QuestProgress = _progress.get(id)
		if progress != null:
			out[id] = progress.to_dict()
	return out


## Restores the quest log. Unknown ids are kept rather than dropped, so a quest removed from
## content mid-save does not take the player's history with it.
func from_dict(data: Dictionary) -> void:
	_progress.clear()
	_order.clear()
	for id: Variant in data.keys():
		var entry: Variant = data.get(id)
		if not entry is Dictionary:
			continue
		var progress := QuestProgress.new()
		progress.from_dict(entry)
		var key := progress.quest_id if not progress.quest_id.is_empty() else StringName(id)
		progress.quest_id = key
		_progress[key] = progress
		_order.append(key)
	Log.info("Quest", "Restored %d quest entries" % _progress.size())


# -- Internals -------------------------------------------------------------------------------

## The jobs [param npc_id] could be handed back right now, most obvious first.
##
## Kept as a list rather than folded into [method ready_to_turn_in_from] because a test
## wants to see how many finished jobs a villager is holding, and because the ranking is a
## statement about the game rather than an implementation detail of the prompt.
func finished_quests_from(npc_id: StringName) -> Array[QuestData]:
	var out: Array[QuestData] = []
	for data: QuestData in active_quests():
		if npc_id == data.giver and _can_pay(data):
			out.append(data)
	out.sort_custom(func(a: QuestData, b: QuestData) -> bool:
		return _turn_in_rank(a.objective) < _turn_in_rank(b.objective)
	)
	return out


func _turn_in_rank(objective: QuestObjective) -> int:
	if objective == null:
		return 3
	match objective.kind:
		QuestObjective.KIND_DELIVER:
			return 0
		QuestObjective.KIND_COLLECT:
			return 1
		QuestObjective.KIND_TALK:
			return 2
	return 3


func _player_state() -> PlayerStateService:
	if player_state != null:
		return player_state
	return PlayerStateService.find()


## The NPC manager, whether it was handed over or is already in the tree.
##
## Found by group as the fallback, the way [method NpcManager.talk] finds
## [PlayerStateService], so the quest service works when it is spawned before the village
## rather than only when [Main] happened to wire it in first.
func _manager() -> NpcManager:
	if npc_manager != null:
		return npc_manager
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(NpcManager.SERVICE_GROUP) as NpcManager