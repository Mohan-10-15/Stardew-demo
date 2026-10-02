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