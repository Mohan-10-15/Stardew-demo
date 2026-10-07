extends Node
## Autoload: `EventBus`
##
## Global, engine-wide signal hub. Systems publish here and subscribe here so
## they never need a direct reference to one another.
##
## Naming convention: `<domain>_<noun>_<verb>` (past tense for events that
## already happened), e.g. `farming_tile_tilled`.

# --- Core lifecycle -------------------------------------------------------
signal game_ready()
signal game_paused(paused: bool)
signal game_quitting()

# --- Presentation / settings ---------------------------------------------
signal config_changed(section: StringName)
signal camera_mode_changed(mode: int)
signal settings_applied()

# --- World ----------------------------------------------------------------
signal world_loaded()
signal time_minute_changed(minute_of_day: int)
signal time_hour_changed(hour: int)
signal day_started(day: int)
signal day_ended(day: int)
signal season_changed(season: int)
signal year_changed(year: int)
signal weather_changed(weather: int)

# --- Farming --------------------------------------------------------------
signal soil_tilled(tile_index: Vector2i)
## A whole plot was wetted at once (rain). `tile_index.x` is -1 and `y` is the
## count, because rain has no single tile to point at.
signal soil_watered(tile_index: Vector2i, count: int)
signal crop_planted(tile_index: Vector2i, crop_id: StringName)
signal crop_harvested(tile_index: Vector2i, crop_id: StringName, amount: int)
signal crop_grew(tile_index: Vector2i)
## The mandatory counterpart to every farming success signal above. `verb` is
## what was attempted (`till`, `plant`, `water`, `harvest`, `tool`) and `reason`
## is a machine-readable string, so a HUD can say "that needs tilling first"
## without any farming code knowing what a HUD is.
signal farming_failed(tile_index: Vector2i, verb: StringName, reason: StringName)

# --- Inventory / items ----------------------------------------------------
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal inventory_changed()
signal hotbar_selection_changed(slot: int)
## A tool ran out of uses. Distinct from `item_removed` so a HUD can warn the
## player before they are left holding nothing.
signal tool_broken(item_id: StringName)

# --- Interaction ----------------------------------------------------------
signal interactable_focused(target: Node)
signal interactable_unfocused(target: Node)
signal interaction_performed(target: Node)

# --- Economy --------------------------------------------------------------
signal currency_changed(new_amount: int)
signal item_purchased(item_id: StringName, quantity: int, total_price: int)
signal item_sold(item_id: StringName, quantity: int, total_price: int)
## The mandatory counterpart to `item_purchased` and `item_sold`, as `AGENTS.md`
## requires for every trade. `kind` is `buy` or `sell`; `reason` is the player's
## explanation (`poor`, `bag_full`, `not_stocked`, `no_item`, `not_sellable`,
## `unknown_item`). A trade that failed must not look or sound like one that
## succeeded, and the audio for handing over money and for being handed money are
## not the same sound.
signal trade_failed(kind: StringName, item_id: StringName, reason: StringName)
## A shop counter was opened. Carries the shop node rather than an id, because the
## listener is the panel itself and re-looking the definition up by id would be a
## lookup to reach data the caller already held.
signal shop_opened(shop: Node)

# --- Gathering ------------------------------------------------------------
## A swing landed on a resource node but did not break it. Both counts, so a HUD can
## show `2 of 4` without asking the node anything.
signal resource_hit(node_id: StringName, hits_left: int, hits_max: int)
## The node gave out and its drops are now on the ground. Carries the world position
## because a sound or a particle burst wants to happen *there*, and the node is not
## the only thing listening.
signal resource_depleted(node_id: StringName, position: Vector3)
## A depleted node came back on its own timer.
signal resource_respawned(node_id: StringName)
## Drops went into the bag. Distinct from [signal item_added] because it answers
## "did that log reach my bag", which is a different question from "did anything
## change", and a full bag means the log is still lying on the ground.
signal resource_collected(item_id: StringName, amount: int)
## The mandatory counterpart to every gathering success signal above. `verb` is what
## was attempted (`chop`, `mine`, `forage`, `pickup`) and `reason` is a
## machine-readable string. The full set, which is what makes it useful: there is no
## way to enumerate them from a single place at runtime, so this comment is the
## list, and `every_gathering_refusal_has_its_own_reason` in the gathering suite is
## the test that fails when a new arm is added without updating it.
##
## - `no_target` — nothing aimable, or a node with no definition.
## - `respawning` — aimed at a stump or an empty patch that is coming back.
## - `no_player_state` — no [PlayerStateService] in the tree, so nothing can be paid.
## - `no_tool` — a tool is required and nothing is held.
## - `wrong_tool` — a tool is held and it is not the one this node needs.
## - `needs_better_tool` — the right tool, below the node's tier.
## - `out_of_reach` — standing too far away.
## - `exhausted` — not enough stamina left for the swing.
## - `nothing_to_do` — the node changed between the check and the press.
## - `no_gathering_service` — no [GatheringService] registered under its group.
## - `bag_full` — a drop that would not fit is left on the ground.
##
## No two of these may sound or read alike, and no two may share a reason: a reason
## shared between "wrong tool" and "too weak a tool" is two different sentences
## sharing one machine-readable value, which means any listener keyed on it has to
## guess.
##
## Refusing loudly is the point. A player who swings a hoe at a pine must be told
## why, in words, rather than watching a keypress do nothing at all.
signal gathering_failed(node_id: StringName, verb: StringName, reason: StringName)

# --- NPCs -----------------------------------------------------------------
## The player said hello and was answered. Distinct from [signal npc_gifted]: talking
## to someone costs nothing and is never the same event as handing them a parsnip,
## which costs the player the parsnip.
signal npc_talked(npc_id: StringName)

## The mandatory counterpart to [signal npc_talked]. `reason` is machine-readable;
## the full set is this comment and `every_npc_refusal_has_its_own_reason` in the NPC
## suite.
##
## - `no_npc` — aimed at something with no villager behind it.
## - `no_npc_service` — no [NpcManager] registered under its group, so there is
##   nothing to be talked to.
## - `no_player_state` — the player has no bag, so a greeting has nothing to read
##   the player's standing out of.
## - `nothing_to_say` — the villager is real but has no definition behind them, so
##   there is nobody to say hello to. A *success-shaped* interaction returning this is
##   still a refusal, and it is why this signal exists rather than a silent no-op.
##
## No two of these may share a value, for the same reason as [signal gathering_failed]:
## a shared reason is two different sentences a listener cannot tell apart.
signal npc_talk_failed(npc_id: StringName, reason: StringName)

## The player handed over a gift and the villager took it. `reaction` is one of
## [constant NpcData.REACTION_LOVED], `REACTION_LIKED`, `REACTION_NEUTRAL` or
## `REACTION_DISLIKED`. Separate from [signal npc_gift_failed] by a wide margin: this
## one *loses friendship* when `reaction` is `disliked`, and a success that costs the
## player friendship must not be drawn or sounded like a success.
signal npc_gifted(npc_id: StringName, item_id: StringName, reaction: StringName)

## The mandatory counterpart to [signal npc_gifted]. `reason` is machine-readable;
## the full set is this comment and `every_npc_refusal_has_its_own_reason` in the NPC
## suite.
##
## - `no_npc` — aimed at something with no villager behind it.
## - `no_npc_service` — no [NpcManager] registered under its group.
## - `no_player_state` — no [PlayerStateService] in the tree, so nothing can be given.
## - `no_item_held` — the selected hotbar slot is empty.
## - `no_item` — something is held but its id resolves to no [ItemDefinition], so it
##   cannot be named in a message.
## - `not_giftable` — the held item is a tool. Nobody wants to be handed a rake.
## - `already_gifted_today` — a loved gift already went to this villager today. The
##   only per-day refusal that is about the *reaction* rather than the budget.
## - `gift_limit_reached` — the weekly gift budget is spent, on any reaction.
## - `nothing_to_do` — the villager's state changed between the prompt and the press.
##
## Also published when the press *fell back* to a greeting: one key both talks and gives,
## so holding a berry for a villager who is already full says hello — and says why the
## berry was not taken. See [constant NpcInteractable.FULL_REASONS]. `not_giftable` is
## the one reason in this list that never arrives this way, because a hoe was never a
## refused present.
##
## `no_item` and `not_giftable` are deliberately separate even though both mean "you
## cannot give this": one is content that failed to load and the other is a rule the
## game is enforcing on purpose, and a bug that produced the first would otherwise be
## heard as the second.
signal npc_gift_failed(npc_id: StringName, item_id: StringName, reason: StringName)

## The player's standing with one villager reached a new tier name.
##
## Not "moved": [signal npc_gifted] already fires for every gift, including the ones
## that do not carry a heart, and a heart bar listens to that. This one exists because a
## tier change is worth a different sound and a different line from an ordinary gift,
## and a listener watching only the gift signal cannot tell the two apart — it is told
## `hearts` and the new `tier_name` so it never has to ask the villager.
signal npc_friendship_changed(npc_id: StringName, hearts: int, tier_name: String)

# --- Quests ----------------------------------------------------------------
## The player took a job on. Carries the quest and the villager who offered it, so a
## journal can say who to go back to without loading the definition itself.
signal quest_accepted(quest_id: StringName, giver_id: StringName)

## The mandatory counterpart to [signal quest_accepted]. `reason` is machine-readable; the
## full set is `QuestService.REASONS` and `every_quest_refusal_has_its_own_reason` in the
## quest suite.
signal quest_accepted_failed(quest_id: StringName, reason: StringName)

## A job was handed in and paid. Separate from [signal quest_progress_changed] by a wide
## margin: progress is the quiet counter in the corner, and this is the moment the gold
## arrives, the parsnips leave the bag and the reward fanfare belongs.
signal quest_turned_in(quest_id: StringName, giver_id: StringName)

## The mandatory counterpart to [signal quest_turned_in]. `reason` is machine-readable; the
## full set is `QuestService.REASONS`.
##
## This one fires on "not yet" refusals as well as hard errors, which is deliberate: a
## player who walks up to a villager holding four of five parsnips must be told something,
## and a prompt that goes quiet is indistinguishable from a dropped frame.
signal quest_turned_in_failed(quest_id: StringName, giver_id: StringName, reason: StringName)

## One objective moved. Both amounts because a listener draws a bar and cannot cache the
## ceiling — an objective's target is content and the next quest may ask for more.
signal quest_progress_changed(quest_id: StringName, current: int, required: int)

# --- Dialogue ---------------------------------------------------------------
## A conversation opened on one villager and one line is on screen. Separate from
## [signal npc_talked] by a wide margin: talking is the greeting that always
## happens, and this is the moment a panel appears, the clock should stop and the
## player is reading rather than playing. A listener that wants to fade the music
## down for a conversation watches this one, not the greeting.
signal dialogue_started(npc_id: StringName, entry_id: StringName)

## The conversation moved from one line to the next — a chain link followed or
## a reply taken, either way the panel repaints. Separate from
## [signal dialogue_started] so the pairing stays honest: one `started` opens a
## conversation, any number of `line_changed` walk through it, and one
## `finished` closes it. A page-turn sound listens here; a music fade listens to
## the pair.
signal dialogue_line_changed(npc_id: StringName, entry_id: StringName)

## The conversation reached its end and every effect along the way has been
## applied. `entry_id` is the line it ended on, which is not necessarily the one
## it started on — a chain of `next` links lands somewhere else, and a sound cue
## that wants to play a closing line needs to know which one that was.
signal dialogue_finished(npc_id: StringName, entry_id: StringName)

## The player picked a reply. Carries the entry the choices were offered on and
## which reply was taken, so a quest or a story flag keyed on *what was said* can
## listen here without re-reading the tree.
signal dialogue_choice_taken(npc_id: StringName, entry_id: StringName, choice_index: int)

## The mandatory counterpart to every dialogue success above. `reason` is
## machine-readable; the full set is this comment and
## `every_dialogue_refusal_has_its_own_reason` in the dialogue suite.
##
## - `no_service` — no [DialogueService] registered under its group, so there is
##   nothing to open a conversation with. Emitted by the component that wanted
##   one, because a missing service cannot emit its own failure.
## - `no_tree` — the villager is real but no dialogue tree names them, which in
##   a shipped build is a content gap rather than a runtime accident: every
##   villager is validated to have one at test time.
## - `no_matching_entry` — the tree exists but every line was ruled out by its
##   own conditions (season, weather, time, hearts, flags, `once`). Content bug:
##   a tree must always keep at least one unconditional fallback.
## - `nothing_active` — `advance` or `choose` was called with no conversation
##   open, which in a real game means a stray keypress and in a test means the
##   caller lost track of its own state.
## - `awaiting_choice` — `advance` was called while replies are on screen.
##   Advancing would pick for the player, so it refuses instead.
## - `bad_choice` — a reply index outside the replies actually offered.
## - `bad_reference` — a `next` link or a reply points at an entry id that does
##   not exist. Refused at load by the registry; this arm is the runtime belt
##   for a tree that was mutated after loading. A conversation that hits one
##   still finishes, so a dead link cannot strand the panel open.
##
## No two of these may share a value, for the same reason as every other failure
## signal in this file: a shared reason is two different sentences a listener
## cannot tell apart.
signal dialogue_failed(npc_id: StringName, reason: StringName)

# --- Stamina --------------------------------------------------------------
## The player's stamina moved. Both values, because a HUD needs the ceiling to
## draw the bar and cannot cache it — a potion or an upgrade will change it.
signal stamina_changed(current: int, maximum: int)
## The player ran out of stamina mid-task. Separate from `farming_failed` even
## though a tool swing raises both: this one is about the player, and a shop or a
## mine raising it later should not sound like a hoe.
signal stamina_exhausted()


## Clears every listener of a signal. Used by tests to guarantee isolation.
func clear_all() -> void:
	for s: Signal in _get_all_signals():
		var connections: Array[Dictionary] = s.get_connections()
		for c: Dictionary in connections:
			s.disconnect(c.get("callable"))


func _get_all_signals() -> Array[Signal]:
	var out: Array[Signal] = []
	for k: Dictionary in get_signal_list():
		out.append(get(k["name"]))
	return out