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