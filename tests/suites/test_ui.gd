extends TestSuite
## The screens: status HUD, hotbar belt, and the shop panel.
##
## Group 25 (UI) — the part that makes the game legible.
##
## These exist because of a specific playtest report: the interact system worked,
## the trade rules worked, and the player saw *nothing*. Every number the game
## spends — gold, stamina, what is in hand, what a shop charges — was invisible,
## so a refused hoe read as a broken tool and a shop read as a broken game. A
## system nobody can see is not delivered.
##
## Each case drives the real scene against a real [PlayerStateService] and asserts
## on the label text, because "the HUD spawned" is not the same claim as "the HUD
## shows the gold".

const STATUS_SCENE := "res://scenes/ui/player_status_hud.tscn"
const HOTBAR_SCENE := "res://scenes/ui/hotbar_hud.tscn"
const SHOP_SCENE := "res://scenes/ui/shop_ui.tscn"
const INTERACTION_SCENE := "res://scenes/ui/interaction_hud.tscn"
const LOG_PANEL_SCENE := "res://scenes/ui/log_panel.tscn"
const QUEST_TRACKER_SCENE := "res://scenes/ui/quest_tracker.tscn"
const SHOP_NODE := "GeneralStore"

var _rig: Node = null


func is_async() -> bool:
	return true


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func get_cases() -> Array[StringName]:
	return [
		&"the_status_hud_shows_the_starting_gold",
		&"the_status_hud_gold_follows_a_purchase",
		&"the_status_hud_stamina_bar_tracks_spending",
		&"the_stamina_readout_turns_red_when_spent",
		&"the_hotbar_lists_the_starter_loadout",
		&"the_hotbar_highlights_the_selected_slot",
		&"opening_a_shop_builds_a_row_per_stocked_item",
		&"the_shop_panel_titles_itself_from_the_content",
		&"buying_from_the_panel_moves_gold_and_the_bag",
		"a_refused_purchase_says_why",
		&"the_shop_panel_lists_what_the_player_can_sell",
		&"the_shop_panel_starts_hidden",
		&"opening_a_shop_pauses_the_game",
		&"closing_a_shop_resumes_the_game",
		&"a_shop_freed_while_open_does_not_strand_the_pause",
		# --- the shop from the keyboard -----------------------------------
		&"the_shop_panel_moves_its_highlight_with_the_keyboard",
		&"the_keyboard_confirms_the_highlighted_row",
		&"a_sold_row_leaves_the_shop_panel",
		&"the_key_that_opened_the_shop_still_closes_it",
		&"the_shop_panel_says_which_keys_do_what",
		# --- telling the player something broke -------------------------------
		&"a_broken_tool_is_announced_on_the_hud",
		&"the_broken_tool_notice_clears_itself",
		# --- the log, on screen ---------------------------------------------
		&"the_log_panel_starts_hidden",
		&"the_log_panel_opens_on_its_key_and_shows_what_was_logged",
		&"the_log_panel_does_not_stop_the_game",
		&"the_log_panel_says_where_the_log_file_is",
		# --- the jobs the player is carrying ------------------------------------
		&"the_quest_tracker_is_empty_with_no_jobs",
		&"the_quest_tracker_lists_a_job_the_player_accepted",
		&"the_quest_tracker_counts_what_the_player_gathers",
		&"the_quest_tracker_marks_a_job_that_can_be_handed_in",
		&"the_quest_tracker_drops_a_job_that_is_finished",
	]


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"the_status_hud_shows_the_starting_gold":
			return await _t_gold_shown()
		&"the_status_hud_gold_follows_a_purchase":
			return await _t_gold_follows()
		&"the_status_hud_stamina_bar_tracks_spending":
			return await _t_stamina_tracks()
		&"the_stamina_readout_turns_red_when_spent":
			return await _t_stamina_red()
		&"the_hotbar_lists_the_starter_loadout":
			return await _t_hotbar_lists()
		&"the_hotbar_highlights_the_selected_slot":
			return await _t_hotbar_highlight()
		&"the_shop_panel_starts_hidden":
			return await _t_shop_starts_hidden()
		&"opening_a_shop_pauses_the_game":
			return await _t_shop_pauses()
		&"closing_a_shop_resumes_the_game":
			return await _t_shop_resumes()
		&"a_shop_freed_while_open_does_not_strand_the_pause":
			return await _t_shop_unpause_on_free()
		&"the_shop_panel_moves_its_highlight_with_the_keyboard":
			return await _t_shop_keyboard_moves()
		&"the_keyboard_confirms_the_highlighted_row":
			return await _t_shop_keyboard_confirms()
		&"a_sold_row_leaves_the_shop_panel":
			return await _t_shop_sell_row_goes_when_empty()
		&"the_key_that_opened_the_shop_still_closes_it":
			return await _t_shop_interact_still_closes()
		&"the_shop_panel_says_which_keys_do_what":
			return await _t_shop_hint()
		&"a_broken_tool_is_announced_on_the_hud":
			return await _t_tool_break_announced()
		&"the_broken_tool_notice_clears_itself":
			return await _t_tool_break_notice_clears()
		&"the_log_panel_starts_hidden":
			return await _t_log_panel_hidden()
		&"the_log_panel_opens_on_its_key_and_shows_what_was_logged":
			return await _t_log_panel_shows_lines()
		&"the_log_panel_does_not_stop_the_game":
			return await _t_log_panel_does_not_pause()
		&"the_log_panel_says_where_the_log_file_is":
			return await _t_log_panel_names_the_file()
		&"opening_a_shop_builds_a_row_per_stocked_item":
			return await _t_shop_rows()
		&"the_shop_panel_titles_itself_from_the_content":
			return await _t_shop_title()
		&"buying_from_the_panel_moves_gold_and_the_bag":
			return await _t_shop_buy()
		&"a_refused_purchase_says_why":
			return await _t_shop_refusal()
		&"the_shop_panel_lists_what_the_player_can_sell":
			return await _t_shop_sell_rows()
		&"the_quest_tracker_is_empty_with_no_jobs":
			return await _t_tracker_empty()
		&"the_quest_tracker_lists_a_job_the_player_accepted":
			return await _t_tracker_lists_job()
		&"the_quest_tracker_counts_what_the_player_gathers":
			return await _t_tracker_counts_gathering()
		&"the_quest_tracker_marks_a_job_that_can_be_handed_in":
			return await _t_tracker_marks_ready()
		&"the_quest_tracker_drops_a_job_that_is_finished":
			return await _t_tracker_drops_finished()
	return fail(case, "no case implementation for %s" % case)


# --- Status HUD --------------------------------------------------------------


## A rig with a player state, a granted loadout and gold already set.
func _make_state(gold: int = 500) -> Dictionary:
	_reset_rig()
	_ensure_rig()
	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.call("grant_starter_loadout")
	state.get("wallet").set_gold(gold)
	await _step(2)
	return {"state": state}


func _instantiate(path: String) -> CanvasLayer:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as CanvasLayer


func _t_gold_shown() -> Dictionary:
	var c := &"the_status_hud_shows_the_starting_gold"
	var made := await _make_state(500)
	var hud := _instantiate(STATUS_SCENE)
	if hud == null:
		return fail(c, "the status HUD scene did not load")
	_rig.add_child(hud)
	await _step(3)
	var label := hud.get_node_or_null(^"Panel/Column/GoldLabel") as Label
	if label == null:
		return fail(c, "no GoldLabel in the HUD")
	if not label.text.contains("500"):
		return fail(c, "gold label reads '%s'" % label.text)
	return succeeded(c, "'%s'" % label.text)


func _t_gold_follows() -> Dictionary:
	var c := &"the_status_hud_gold_follows_a_purchase"
	var made := await _make_state(500)
	var state: Node = made["state"]
	var hud := _instantiate(STATUS_SCENE)
	_rig.add_child(hud)
	await _step(3)
	var label := hud.get_node_or_null(^"Panel/Column/GoldLabel") as Label
	state.get("wallet").set_gold(275)
	await _step(2)
	if not label.text.contains("275"):
		return fail(c, "after spending, the label still reads '%s'" % label.text)
	return succeeded(c, "'%s'" % label.text)


func _t_stamina_tracks() -> Dictionary:
	var c := &"the_status_hud_stamina_bar_tracks_spending"
	var made := await _make_state()
	var state: Node = made["state"]
	var hud := _instantiate(STATUS_SCENE)
	_rig.add_child(hud)
	await _step(3)
	var bar := hud.get_node_or_null(^"Panel/Column/StaminaRow/StaminaBar") as ProgressBar
	if bar == null:
		return fail(c, "no StaminaBar in the HUD")
	var pool: Stamina = state.get("stamina")
	pool.spend(30)
	await _step(2)
	if bar.value != pool.current:
		return fail(c, "bar shows %s, stamina is %d" % [bar.value, pool.current])
	if bar.max_value != pool.maximum:
		return fail(c, "bar ceiling is %s, should be %d" % [bar.max_value, pool.maximum])
	return succeeded(c, "bar at %d/%d" % [int(bar.value), pool.maximum])


func _t_stamina_red() -> Dictionary:
	var c := &"the_stamina_readout_turns_red_when_spent"
	var made := await _make_state()
	var state: Node = made["state"]
	var hud := _instantiate(STATUS_SCENE)
	_rig.add_child(hud)
	await _step(3)
	var label := hud.get_node_or_null(^"Panel/Column/StaminaRow/StaminaLabel") as Label
	if label == null:
		return fail(c, "no StaminaLabel in the HUD")
	var pool: Stamina = state.get("stamina")
	pool.spend(pool.maximum)
	await _step(2)
	var spent := label.get_theme_color(&"font_color")
	if spent.g >= spent.r:
		return fail(c, "the readout stayed pale (%s) at zero stamina" % spent)
	return succeeded(c, "turns red at 0/%d" % pool.maximum)


# --- Hotbar ------------------------------------------------------------------


func _t_hotbar_lists() -> Dictionary:
	var c := &"the_hotbar_lists_the_starter_loadout"
	var made := await _make_state()
	var hud := _instantiate(HOTBAR_SCENE)
	_rig.add_child(hud)
	await _step(3)
	var root := hud.get_node_or_null(^"Slots") as HBoxContainer
	if root == null:
		return fail(c, "no Slots container in the hotbar HUD")
	if root.get_child_count() != 9:
		return fail(c, "%d slots, expected 9" % root.get_child_count())
	var filled := 0
	for i: int in range(root.get_child_count()):
		var label := root.get_child(i).get_node_or_null(^"Column/SlotLabel") as Label
		if label != null and label.text.strip_edges() != "":
			filled += 1
	if filled == 0:
		return fail(c, "every slot is blank despite a starter loadout")
	return succeeded(c, "%d of 9 slots filled" % filled)


func _t_hotbar_highlight() -> Dictionary:
	var c := &"the_hotbar_highlights_the_selected_slot"
	var made := await _make_state()
	var state: Node = made["state"]
	var hud := _instantiate(HOTBAR_SCENE)
	_rig.add_child(hud)
	await _step(3)
	var root := hud.get_node_or_null(^"Slots") as HBoxContainer

	# The held colour, taken from the slot that starts selected rather than
	# hard-coded. Comparing slot 0's colour against slot 3's after a move would
	# compare held-with-held and pass or fail on a coincidence.
	var held := _slot_bg(root, 0)
	if held == _slot_bg(root, 1):
		return fail(c, "slot 0 and slot 1 look identical before any move")

	state.get("hotbar").select(3)
	await _step(2)
	if _slot_bg(root, 3) != held:
		return fail(c, "slot 3 (%s) did not take the held style (%s)"
			% [_slot_bg(root, 3), held])
	# The one that actually regressed: the old slot keeping its highlight.
	if _slot_bg(root, 0) == held:
		return fail(c, "slot 0 kept the highlight after selecting slot 3")
	return succeeded(c, "highlight moved from slot 0 to slot 3")


func _slot_bg(root: HBoxContainer, index: int) -> Color:
	var panel := root.get_child(index) as Panel
	var style := panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	return style.bg_color


# --- Shop panel --------------------------------------------------------------


## The real world, a real player state and economy service, and the real panel.
func _make_shop_rig() -> Dictionary:
	_reset_rig()
	var packed := load("res://scenes/world/world.tscn") as PackedScene
	if packed == null:
		return {}
	_ensure_rig()
	var world := packed.instantiate()
	_rig.add_child(world)

	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.call("grant_starter_loadout")
	state.get("wallet").set_gold(500)

	var economy_script: GDScript = load("res://scripts/economy/economy_service.gd")
	var economy: Node = economy_script.new()
	economy.name = "EconomyService"
	_rig.add_child(economy)

	var panel := _instantiate(SHOP_SCENE)
	if panel == null:
		return {}
	_rig.add_child(panel)
	await _step(4)
	return {
		"state": state,
		"panel": panel,
		"shop": world.find_child(SHOP_NODE, true, false),
		"rows": panel.get_node_or_null(^"Center/Panel/Column/Rows"),
	}


func _t_shop_starts_hidden() -> Dictionary:
	var c := &"the_shop_panel_starts_hidden"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var panel: CanvasLayer = made["panel"]
	if panel.visible:
		return fail(c, "the shop panel is visible with no shop open")
	return succeeded(c)


func _t_shop_pauses() -> Dictionary:
	var c := &"opening_a_shop_pauses_the_game"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	EventBus.shop_opened.emit(shop)
	await _step(2)
	# The player must not keep walking around behind a panel they are trading in.
	if not tree.paused:
		return fail(c, "the game is still running while the shop is open")
	return succeeded(c)


func _t_shop_resumes() -> Dictionary:
	var c := &"closing_a_shop_resumes_the_game"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	EventBus.shop_opened.emit(shop)
	await _step(2)
	panel.call("close")
	await _step(2)
	if tree.paused:
		return fail(c, "the game stayed paused after the shop closed")
	return succeeded(c)


func _t_shop_unpause_on_free() -> Dictionary:
	var c := &"a_shop_freed_while_open_does_not_strand_the_pause"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	EventBus.shop_opened.emit(shop)
	await _step(2)
	if not tree.paused:
		return fail(c, "precondition failed: opening the shop did not pause")
	# A scene reload mid-trade frees the panel without ever calling `close()`.
	panel.free()
	await _step(2)
	if tree.paused:
		return fail(c, "the panel was freed while open and left the game paused")
	return succeeded(c)


func _t_shop_rows() -> Dictionary:
	var c := &"opening_a_shop_builds_a_row_per_stocked_item"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var rows: VBoxContainer = made["rows"]
	if shop == null or rows == null:
		return fail(c, "shop=%s rows=%s" % [shop, rows])
	# Opened the way the game opens it: the counter's signal on the bus.
	EventBus.shop_opened.emit(shop)
	await _step(2)

	var expected := EconomyService.buyable_stock(shop.shop)
	if expected.is_empty():
		return fail(c, "the content itself stocks nothing buyable")
	var buy_rows := 0
	for child: Node in rows.get_children():
		if String(child.name).begins_with("Buy_"):
			buy_rows += 1
	if buy_rows != expected.size():
		return fail(c, "%d buy rows for %d stocked items"
			% [buy_rows, expected.size()])
	return succeeded(c, "%d buy rows" % buy_rows)


func _t_shop_title() -> Dictionary:
	var c := &"the_shop_panel_titles_itself_from_the_content"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	var title := panel.get_node_or_null(^"Center/Panel/Column/Title") as Label
	EventBus.shop_opened.emit(shop)
	await _step(2)
	if title.text != shop.shop.display_name:
		return fail(c, "title '%s' but the definition says '%s'"
			% [title.text, shop.shop.display_name])
	return succeeded(c, "'%s'" % title.text)


func _t_shop_buy() -> Dictionary:
	var c := &"buying_from_the_panel_moves_gold_and_the_bag"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var rows: VBoxContainer = made["rows"]
	var state: Node = made["state"]
	EventBus.shop_opened.emit(shop)
	await _step(2)

	# Click the real button in a real row, rather than calling `Shop.buy`. The
	# button is the only thing the player can press, and a panel whose buttons are
	# wired to nothing passes every other case here.
	var button := _find_buy_button(rows, &"parsnip_seeds")
	if button == null:
		return fail(c, "no Buy button for parsnip_seeds")
	var wallet: Wallet = state.get("wallet")
	var before_gold: int = wallet.gold
	var before_held: int = state.get("inventory").count(&"parsnip_seeds")
	button.emit_signal(&"pressed")
	await _step(2)

	if wallet.gold >= before_gold:
		return fail(c, "gold did not fall (%d -> %d)" % [before_gold, wallet.gold])
	var after_held: int = state.get("inventory").count(&"parsnip_seeds")
	if after_held != before_held + 1:
		return fail(c, "bag holds %d seeds, was %d" % [after_held, before_held])
	# And the panel told the player what happened, rather than changing silently.
	var message := _message_text(made["panel"])
	if not message.to_lower().contains("bought"):
		return fail(c, "the message line reads '%s'" % message)
	return succeeded(c, "1 seed for %dg, message: %s"
		% [before_gold - wallet.gold, message])


func _t_shop_refusal() -> Dictionary:
	var c := &"a_refused_purchase_says_why"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var rows: VBoxContainer = made["rows"]
	var state: Node = made["state"]
	EventBus.shop_opened.emit(shop)
	await _step(2)

	state.get("wallet").set_gold(1)
	var button := _find_buy_button(rows, &"parsnip_seeds")
	if button == null:
		return fail(c, "no Buy button for parsnip_seeds")
	button.emit_signal(&"pressed")
	await _step(2)

	var message := _message_text(made["panel"])
	if message.strip_edges() == "":
		return fail(c, "an unaffordable purchase produced no message at all")
	if not message.to_lower().contains("gold"):
		return fail(c, "the refusal does not mention gold: '%s'" % message)
	return succeeded(c, "'%s'" % message)


func _t_shop_sell_rows() -> Dictionary:
	var c := &"the_shop_panel_lists_what_the_player_can_sell"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var rows: VBoxContainer = made["rows"]
	var state: Node = made["state"]
	# Something the counter will actually pay for. Seed packets are stocked, so
	# they are deliberately *not* sellable, and a panel that offered to buy them
	# would be the exact bug the rules forbid.
	state.get("inventory").add(&"parsnip", 2)
	EventBus.shop_opened.emit(shop)
	await _step(2)

	var sell_rows := 0
	var sells_parsnip := false
	var sells_seeds := false
	for child: Node in rows.get_children():
		var row_name := String(child.name)
		if row_name.begins_with("Sell_"):
			sell_rows += 1
			if row_name == "Sell_parsnip":
				sells_parsnip = true
			if row_name == "Sell_parsnip_seeds":
				sells_seeds = true
	if not sells_parsnip:
		return fail(c, "no sell row for the parsnips the player is carrying")
	if sells_seeds:
		return fail(c, "offered to buy back seed packets, which are stocked")
	return succeeded(c, "%d sell rows" % sell_rows)


## The keyboard moves the highlight, and the highlight is drawn.
##
## Real key events through `Input.parse_input_event`, not `Input.action_press`. The panel
## reads `_unhandled_input`, and `Input.action_press` only moves the action *state* — it
## never delivers an event, so a test written that way would assert against a code path
## the player cannot reach.
##
## Asserted in both spellings on purpose. W/S is the pair that opened the counter and must
## work here; the arrows are what a player expects from any menu, and a panel that only
## answers W/S is a panel that looks broken to anyone whose hand is already on them.
func _t_shop_keyboard_moves() -> Dictionary:
	var c := &"the_shop_panel_moves_its_highlight_with_the_keyboard"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	EventBus.shop_opened.emit(shop)
	await _step(2)

	var first: Dictionary = panel.call("selected_entry")
	if first.is_empty():
		return fail(c, "the panel opened with no row selected")
	if not StringName(first.get("kind", &"")) == &"buy":
		return fail(c, "the first row is a '%s', not a buy" % str(first.get("kind", "")))

	# W is up the list, so from the top row it wraps to the bottom.
	await _tap_key(KEY_W)
	await _step(2)
	var wrapped: Dictionary = panel.call("selected_entry")
	if StringName(wrapped.get("item_id", &"")) == StringName(first.get("item_id", &"")):
		return fail(c, "W at the top row left the highlight on '%s'" % str(wrapped.get("item_id", "")))

	# One S back down lands on the top row again, which also proves the wrap was a
	# wrap and not a clamp.
	await _tap_key(KEY_S)
	await _step(2)
	var back: Dictionary = panel.call("selected_entry")
	if StringName(back.get("item_id", &"")) != StringName(first.get("item_id", &"")):
		return fail(c, "S did not step back to '%s', highlight is on '%s'"
			% [str(first.get("item_id", "")), str(back.get("item_id", ""))])

	# And the arrow keys move it too.
	await _tap_key(KEY_DOWN)
	await _step(2)
	var arrowed: Dictionary = panel.call("selected_entry")
	if StringName(arrowed.get("item_id", &"")) == StringName(back.get("item_id", &"")):
		return fail(c, "the down arrow did nothing")

	# The highlight has to be *visible*, or the keyboard is driving something the player
	# cannot see. One row styled, all the others not.
	var styled := 0
	for child: Node in (made["rows"] as VBoxContainer).get_children():
		var row := child as PanelContainer
		if row == null or not String(row.name).begins_with("Buy_"):
			continue
		if row.has_theme_stylebox_override("panel"):
			styled += 1
	if styled != 1:
		return fail(c, "%d buy rows are highlighted, expected exactly 1" % styled)
	return succeeded(c, "W/S and the arrows move one visible highlight over %d rows"
		% EconomyService.buyable_stock(shop.shop).size())


## Enter trades the highlighted row.
##
## Both halves again: gold leaves and the item arrives, and the panel stays open so a
## player can buy two packets without reopening the world.
func _t_shop_keyboard_confirms() -> Dictionary:
	var c := &"the_keyboard_confirms_the_highlighted_row"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	var state: Node = made["state"]
	EventBus.shop_opened.emit(shop)
	await _step(2)

	var row: Dictionary = panel.call("selected_entry")
	var item_id := StringName(row.get("item_id", &""))
	if item_id.is_empty():
		return fail(c, "no row to confirm")
	var gold_before: int = state.get("wallet").gold
	await _tap_key(KEY_ENTER)
	await _step(3)

	if not panel.visible:
		return fail(c, "confirming a row closed the panel")
	var gold_after: int = state.get("wallet").gold
	if gold_after >= gold_before:
		return fail(c, "Enter on '%s' left the gold at %d" % [item_id, gold_after])
	if state.get("inventory").count(item_id) < 1:
		return fail(c, "Enter on '%s' charged %dg and delivered nothing"
			% [item_id, gold_before - gold_after])
	# Still on the same row afterwards. A keyboard player buying three packets presses
	# Enter three times, and a rebuild that resets the highlight to the top makes the
	# second and third press buy whatever happens to be first.
	var again: Dictionary = panel.call("selected_entry")
	if StringName(again.get("item_id", &"")) != item_id:
		return fail(c, "the highlight moved off '%s' to '%s' after buying it"
			% [item_id, str(again.get("item_id", ""))])
	return succeeded(c, "Enter bought %s for %dg and kept it selected"
		% [item_id, gold_before - gold_after])


## A sell row disappears once the last one is sold.
##
## The keyboard makes this bug obvious in a way the mouse hid: the row is rebuilt after
## every trade, so a Sell row that outlived its item leaves Enter aimed at a trade that
## can no longer happen, and the panel keeps offering it.
func _t_shop_sell_row_goes_when_empty() -> Dictionary:
	var c := &"a_sold_row_leaves_the_shop_panel"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	var rows: VBoxContainer = made["rows"]
	var state: Node = made["state"]
	state.get("inventory").add(&"parsnip", 1)
	EventBus.shop_opened.emit(shop)
	await _step(2)

	var sell_row := rows.get_node_or_null(^"Sell_parsnip")
	if sell_row == null:
		return fail(c, "no sell row for the one parsnip the player carries")
	# Walk down to it and sell it from the keyboard. The row count is bounded because
	# the rows are finite; the failure case is "reached the bottom without finding it".
	var reached := false
	for _i: int in range(64):
		var entry: Dictionary = panel.call("selected_entry")
		if StringName(entry.get("kind", &"")) == &"sell" \
				and StringName(entry.get("item_id", &"")) == &"parsnip":
			reached = true
			break
		await _tap_key(KEY_S)
		await _step(1)
	if not reached:
		return fail(c, "could not reach the parsnip sell row with the keyboard")
	var gold_before: int = state.get("wallet").gold
	await _tap_key(KEY_ENTER)
	await _step(3)

	if state.get("inventory").count(&"parsnip") != 0:
		return fail(c, "the parsnip was not sold")
	if int(state.get("wallet").gold) <= gold_before:
		return fail(c, "selling the parsnip paid nothing")
	if rows.get_node_or_null(^"Sell_parsnip") != null:
		return fail(c, "the sell row is still on screen with no parsnips left")
	return succeeded(c, "sold the last parsnip and its row went with it")


## The key that opened the counter is still the key that shuts it.
##
## The trap this guards: one key both confirms and closes, so the obvious wiring makes E
## buy the highlighted row, or makes the second E of a player's life charge them for a
## seed packet they did not mean to buy.
func _t_shop_interact_still_closes() -> Dictionary:
	var c := &"the_key_that_opened_the_shop_still_closes_it"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	var state: Node = made["state"]
	EventBus.shop_opened.emit(shop)
	await _step(2)
	if not panel.visible:
		return fail(c, "the panel did not open")
	var gold_before: int = state.get("wallet").gold

	await _tap_key(KEY_E)
	await _step(3)
	if panel.visible:
		return fail(c, "E left the shop open")
	if int(state.get("wallet").gold) != gold_before:
		return fail(c, "closing the shop with E also charged the player")
	return succeeded(c, "E closed it and bought nothing")


## The controls are written on the panel.
##
## A panel that can be driven entirely from the keyboard and never says so is a panel
## most players will assume is mouse-only: the mouse still works, so nothing looks
## broken, and the first person to press W gets silence.
func _t_shop_hint() -> Dictionary:
	var c := &"the_shop_panel_says_which_keys_do_what"
	var made := await _make_shop_rig()
	if made.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = made["shop"]
	var panel: CanvasLayer = made["panel"]
	EventBus.shop_opened.emit(shop)
	await _step(2)
	var hint := panel.get_node_or_null(^"Center/Panel/Column/Hint") as Label
	if hint == null:
		return fail(c, "the generated panel has no Hint label")
	if not hint.visible:
		return fail(c, "the controls line is hidden while the shop is open")
	for needed: String in ["W/S", "Enter", "close"]:
		if not hint.text.contains(needed):
			return fail(c, "the controls line never mentions '%s': '%s'" % [needed, hint.text])
	return succeeded(c, "'%s'" % hint.text)


## A tool breaking is *said*, not just done.
##
## [signal EventBus.tool_broken] had no subscriber anywhere in the project. The stack was
## removed from the bag, the held slot went empty, and the player got no word at all —
## which is why this drives the real HUD scene and asserts on the rendered label rather
## than on a return value: the claim is that the player is told.
func _t_tool_break_announced() -> Dictionary:
	var c := &"a_broken_tool_is_announced_on_the_hud"
	_reset_rig()
	_ensure_rig()
	var hud := _instantiate(INTERACTION_SCENE)
	if hud == null:
		return fail(c, "the interaction HUD scene did not load")
	_rig.add_child(hud)
	await _step(3)
	var notice := hud.get_node_or_null(^"PromptContainer/NoticeLabel") as Label
	if notice == null:
		return fail(c, "the generated HUD has no NoticeLabel")
	if notice.visible:
		return fail(c, "a notice is on screen with nothing having happened")

	EventBus.tool_broken.emit(&"axe")
	await _step(3)
	if not notice.visible:
		return fail(c, "the tool broke and the HUD said nothing")
	if not notice.text.contains("Axe"):
		return fail(c, "the notice never names the tool: '%s'" % notice.text)
	if not notice.text.to_lower().contains("broke"):
		return fail(c, "the notice never says it broke: '%s'" % notice.text)
	return succeeded(c, "'%s'" % notice.text)


## The notice does not stay up forever.
##
## A permanent message is a permanent thing to look past. Timed out on the HUD's own
## clock rather than a scene-tree timer, so the countdown follows the same pause rules as
## everything else on the HUD.
func _t_tool_break_notice_clears() -> Dictionary:
	var c := &"the_broken_tool_notice_clears_itself"
	_reset_rig()
	_ensure_rig()
	var hud := _instantiate(INTERACTION_SCENE)
	if hud == null:
		return fail(c, "the interaction HUD scene did not load")
	_rig.add_child(hud)
	await _step(3)
	var notice := hud.get_node_or_null(^"PromptContainer/NoticeLabel") as Label
	if notice == null:
		return fail(c, "the generated HUD has no NoticeLabel")

	EventBus.tool_broken.emit(&"axe")
	await _step(3)
	if not notice.visible:
		return fail(c, "the notice never appeared, so there is nothing to clear")
	# On the clock, not on a frame count. Headless runs unthrottled, so 150 frames can be
	# a fraction of a second of real time and the countdown would not be near its end —
	# which is how this test passed a HUD that never expired the notice at all.
	await tree.create_timer(3.4).timeout
	await _step(3)
	if notice.visible:
		return fail(c, "the notice is still up after 3.4s: '%s'" % notice.text)
	return succeeded(c, "gone within its three seconds")


## The log panel is not on screen at boot.
func _t_log_panel_hidden() -> Dictionary:
	var c := &"the_log_panel_starts_hidden"
	var panel := await _make_log_panel()
	if panel == null:
		return fail(c, "could not build the scene")
	if panel.visible:
		return fail(c, "the log panel is visible at boot")
	return succeeded(c)


## F3 shows the log, and the log is really in there.
##
## Real key events, not `Input.action_press` — the same reason as the shop panel: the
## panel reads `_unhandled_input`, and `action_press` never delivers an event.
##
## The assertion is on rendered text, because the claim being made is "the player can
## read the log", not "the panel called `recent`".
func _t_log_panel_shows_lines() -> Dictionary:
	var c := &"the_log_panel_opens_on_its_key_and_shows_what_was_logged"
	var panel := await _make_log_panel()
	if panel == null:
		return fail(c, "could not build the scene")
	var text := panel.get_node_or_null(^"Panel/Column/Scroll/Text") as RichTextLabel
	if text == null:
		return fail(c, "the generated panel has no RichTextLabel")

	# Something the log has genuinely said, written through the real logger.
	var marker := "panel probe %d" % Time.get_ticks_msec()
	Log.info("TestSuite", marker)

	await _tap_key(KEY_F3)
	await _step(3)
	if not panel.visible:
		return fail(c, "F3 did not open the log panel")
	if not text.get_parsed_text().contains(marker):
		return fail(c, "the panel opened without the line that was just logged")

	# And a line logged *while it is open* arrives without reopening anything.
	var later := "live probe %d" % Time.get_ticks_msec()
	Log.info("TestSuite", later)
	await _step(3)
	if not text.get_parsed_text().contains(later):
		return fail(c, "a line logged while the panel was open never appeared")

	await _tap_key(KEY_F3)
	await _step(3)
	if panel.visible:
		return fail(c, "F3 did not close the log panel")
	return succeeded(c, "opened, showed both lines, closed")


## Reading the log must not stop the world.
##
## Every other panel in this game is modal, so the reflex here is to pause. That would
## defeat the panel: the whole point is watching the log *while* playing, and a log you
## have to close to see what your last action did is no use.
func _t_log_panel_does_not_pause() -> Dictionary:
	var c := &"the_log_panel_does_not_stop_the_game"
	var panel := await _make_log_panel()
	if panel == null:
		return fail(c, "could not build the scene")
	var before_paused: bool = GameState.paused
	await _tap_key(KEY_F3)
	await _step(3)
	if not panel.visible:
		return fail(c, "the panel did not open")
	if GameState.paused != before_paused:
		GameState.set_paused(before_paused)
		return fail(c, "the log panel paused the game")
	await _tap_key(KEY_F3)
	await _step(2)
	return succeeded(c, "the tree kept running")


## The header says where the log file is.
##
## The whole reason this panel exists is that `user://hollowbrook.log` is somewhere the
## player is not looking. A panel that shows the lines but not the path sends you back
## to where you started.
func _t_log_panel_names_the_file() -> Dictionary:
	var c := &"the_log_panel_says_where_the_log_file_is"
	var panel := await _make_log_panel()
	if panel == null:
		return fail(c, "could not build the scene")
	var header := panel.get_node_or_null(^"Panel/Column/Header") as Label
	if header == null:
		return fail(c, "the generated panel has no Header label")
	await _tap_key(KEY_F3)
	await _step(3)
	if not header.text.contains("user://"):
		return fail(c, "the header never mentions a user:// path: '%s'" % header.text)
	if not header.text.contains(".log"):
		return fail(c, "the header names no log file: '%s'" % header.text)
	await _tap_key(KEY_F3)
	await _step(2)
	return succeeded(c, "'%s'" % header.text)


## The generated log panel in a rig.
func _make_log_panel() -> CanvasLayer:
	_reset_rig()
	_ensure_rig()
	var panel := _instantiate(LOG_PANEL_SCENE)
	if panel == null:
		return null
	_rig.add_child(panel)
	await _step(3)
	return panel


## A real key press and release, delivered as an event.
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


## The Buy button in the row for [param item_id], or null.
func _find_buy_button(rows: VBoxContainer, item_id: StringName) -> Button:
	var row := rows.get_node_or_null(NodePath("Buy_%s" % item_id))
	if row == null:
		return null
	for child: Node in row.get_children():
		for button: Node in _find_buttons(child):
			if (button as Button).text == "Buy":
				return button as Button
	return null


func _find_buttons(from: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in from.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_find_buttons(child))
	return found


func _message_text(panel: CanvasLayer) -> String:
	var label := panel.get_node_or_null(
		^"Center/Panel/Column/Message"
	) as Label
	return "" if label == null else label.text


# --- Quest tracker ------------------------------------------------------------


## A real [QuestService] over a real bag, and the real tracker, and nothing else.
##
## The three together and no shortcuts: a tracker wired to a stub would pass while the
## one the game spawns found no service, which is the failure this suite exists to catch.
func _make_tracker() -> Dictionary:
	_reset_rig()
	_ensure_rig()
	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.set("bag_slots", 24)
	await _step(2)
	var quests: Node = load("res://scripts/quest/quest_service.gd").new()
	quests.name = "QuestService"
	quests.set("player_state", state)
	_rig.add_child(quests)
	await _step(2)
	var panel := _instantiate(QUEST_TRACKER_SCENE)
	if panel == null:
		return {}
	_rig.add_child(panel)
	await _step(3)
	return {"state": state, "quests": quests, "panel": panel}


## The rows the tracker is currently drawing, as text.
func _tracker_rows(panel: CanvasLayer) -> Array[String]:
	var rows := panel.get_node_or_null(^"Panel/Column/Rows") as VBoxContainer
	var out: Array[String] = []
	if rows == null:
		return out
	for row: Node in rows.get_children():
		var label := row.get_node_or_null(^"Label") as Label
		out.append("" if label == null else label.text)
	return out


func _tracker_visible(panel: CanvasLayer) -> bool:
	var box := panel.get_node_or_null(^"Panel") as Control
	return box != null and box.visible


## Puts [param amount] of [param item_id] in the bag and announces it the way the
## harvesting and gathering systems do.
func _gather(bag: Inventory, item_id: StringName, amount: int) -> void:
	if bag.add(item_id, amount) != amount:
		return
	root().get_node(^"EventBus").emit_signal(&"item_added", item_id, amount)


func _t_tracker_empty() -> Dictionary:
	var c := &"the_quest_tracker_is_empty_with_no_jobs"
	var made := await _make_tracker()
	if made.is_empty():
		return fail(c, "could not build the tracker")
	var panel: CanvasLayer = made["panel"]
	if not _tracker_rows(panel).is_empty():
		return fail(c, "a tracker with no jobs is drawing %s" % str(_tracker_rows(panel)))
	# Hidden rather than an empty box. An always-visible empty panel in the corner is a
	# piece of UI every player learns to look straight past.
	if _tracker_visible(panel):
		return fail(c, "an empty tracker is on screen")
	return succeeded(c, "no jobs, no panel")


func _t_tracker_lists_job() -> Dictionary:
	var c := &"the_quest_tracker_lists_a_job_the_player_accepted"
	var made := await _make_tracker()
	if made.is_empty():
		return fail(c, "could not build the tracker")
	var quests: QuestService = made["quests"]
	var state: PlayerStateService = made["state"]
	var panel: CanvasLayer = made["panel"]
	var job := QuestRegistry.quests_from(&"mira")[0]
	if not quests.accept(job.id, state):
		return fail(c, "could not accept %s" % job.id)
	await _step(2)
	var rows := _tracker_rows(panel)
	if rows.size() != 1:
		return fail(c, "one accepted job drew %d rows: %s" % [rows.size(), str(rows)])
	var text: String = rows[0]
	if not text.contains(job.title):
		return fail(c, "the row does not name the job: '%s'" % text)
	if not text.contains("Parsnip"):
		return fail(c, "the row does not say what is wanted: '%s'" % text)
	if not text.contains("0/%d" % job.objective.count):
		return fail(c, "a fresh job does not read 0 of %d: '%s'" % [job.objective.count, text])
	if not _tracker_visible(panel):
		return fail(c, "the tracker stayed hidden with a job in hand")
	return succeeded(c, "'%s'" % text)


func _t_tracker_counts_gathering() -> Dictionary:
	var c := &"the_quest_tracker_counts_what_the_player_gathers"
	var made := await _make_tracker()
	if made.is_empty():
		return fail(c, "could not build the tracker")
	var quests: QuestService = made["quests"]
	var state: PlayerStateService = made["state"]
	var panel: CanvasLayer = made["panel"]
	var job := QuestRegistry.quests_from(&"mira")[0]
	if not quests.accept(job.id, state):
		return fail(c, "could not accept %s" % job.id)
	await _step(2)
	# Through the bag and the bus, because that is the path the harvesting and gathering
	# systems take. A tracker driven by a private call would read the right number for
	# the wrong reason.
	_gather(state.inventory, job.objective.item_id, 2)
	await _step(2)
	var rows := _tracker_rows(panel)
	if rows.size() != 1 or not rows[0].contains("2/%d" % job.objective.count):
		return fail(c, "two gathered did not move the row: %s" % str(rows))
	return succeeded(c, "'%s'" % rows[0])


func _t_tracker_marks_ready() -> Dictionary:
	var c := &"the_quest_tracker_marks_a_job_that_can_be_handed_in"
	var made := await _make_tracker()
	if made.is_empty():
		return fail(c, "could not build the tracker")
	var quests: QuestService = made["quests"]
	var state: PlayerStateService = made["state"]
	var panel: CanvasLayer = made["panel"]
	var job := QuestRegistry.quests_from(&"mira")[0]
	if not quests.accept(job.id, state):
		return fail(c, "could not accept %s" % job.id)
	await _step(2)
	_gather(state.inventory, job.objective.item_id, job.objective.count)
	await _step(2)
	var rows := _tracker_rows(panel)
	if rows.size() != 1 or not rows[0].contains("ready"):
		return fail(c, "a job the player can hand in is not marked: %s" % str(rows))
	# And still counted, because "ready" is an addition and not a replacement.
	if not rows[0].contains("%d/%d" % [job.objective.count, job.objective.count]):
		return fail(c, "the ready row lost its tally: '%s'" % rows[0])
	return succeeded(c, "'%s'" % rows[0])


func _t_tracker_drops_finished() -> Dictionary:
	var c := &"the_quest_tracker_drops_a_job_that_is_finished"
	var made := await _make_tracker()
	if made.is_empty():
		return fail(c, "could not build the tracker")
	var quests: QuestService = made["quests"]
	var state: PlayerStateService = made["state"]
	var panel: CanvasLayer = made["panel"]
	var job := QuestRegistry.quests_from(&"mira")[0]
	if not quests.accept(job.id, state):
		return fail(c, "could not accept %s" % job.id)
	_gather(state.inventory, job.objective.item_id, job.objective.count)
	await _step(2)
	if not quests.turn_in(job.id, state, job.giver):
		return fail(c, "could not hand the finished job in")
	await _step(2)
	# A finished job leaves the list the moment it pays. Keeping it until the next day
	# fills the corner with rows the player has already dismissed.
	if not _tracker_rows(panel).is_empty():
		return fail(c, "a paid job is still listed: %s" % str(_tracker_rows(panel)))
	if _tracker_visible(panel):
		return fail(c, "the tracker is still on screen with nothing to show")
	return succeeded(c, "the row went away when the job was paid")


# --- Fixtures ----------------------------------------------------------------


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node.new()
	_rig.name = "UITestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null
	# The shop panel pauses the game, and a case that fails while the shop is open
	# never gets to close it. Without this the pause outlives the suite and the
	# next one fails for a reason that has nothing to do with itself.
	if tree.paused:
		tree.paused = false


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame