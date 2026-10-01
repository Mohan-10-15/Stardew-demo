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

# --- Farming --------------------------------------------------------------
signal soil_tilled(tile_index: Vector2i)
signal crop_planted(tile_index: Vector2i, crop_id: StringName)
signal crop_harvested(tile_index: Vector2i, crop_id: StringName, amount: int)
signal crop_grew(tile_index: Vector2i)

# --- Inventory / items ----------------------------------------------------
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal inventory_changed()
signal hotbar_selection_changed(slot: int)

# --- Interaction ----------------------------------------------------------
signal interactable_focused(target: Node)
signal interactable_unfocused(target: Node)
signal interaction_performed(target: Node)

# --- Economy --------------------------------------------------------------
signal currency_changed(new_amount: int)
signal item_purchased(item_id: StringName, quantity: int, total_price: int)
signal item_sold(item_id: StringName, quantity: int, total_price: int)


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