extends CanvasLayer
## The shop screen: what the counter sells, what it will pay, and the trade buttons.
##
## ## Why this is not "the UI group, later"
##
## The counter's interaction was working perfectly while being invisible. Pressing E
## opened it, `Shop.opened` fired, and a signal with no listener is not a feature a
## player can perceive — from the chair it is indistinguishable from a broken game.
## Shipping a trade with no way to trade is not a scoped feature, it is a hole.
##
## ## It owns no rules
##
## Every number here is read from [EconomyService] through [method Shop], and every
## button calls straight into the same methods. The screen formats and collects
## clicks; it never decides whether a trade is allowed. A panel that recomputed
## affordability to grey out a button would be a second implementation of the rules,
## and the two would disagree the first time a rule changed.
##
## Rebuilt wholesale on open rather than kept live. A shop screen that repaints
## itself as gold changes underneath is a screen that flickers while the player is
## trying to click a row, and nothing in the world can change gold while the panel
## holds the mouse — the counter is modal.

## ## The keyboard drives it too
##
## The first version of this panel was mouse-only: every button was `FOCUS_NONE` and
## nothing looked at `move_*`, so a player who opened a shop and pressed W/S got silence
## while the game was visibly paused. A pause with no keyboard response reads as a crash,
## and it is not one — there was simply nothing listening.
##
## So the panel keeps its own selection instead of using engine focus: one index into one
## flat list of buy and sell rows, a highlight drawn on the row, and three keys. Engine
## focus would fight the pause, the mouse and `interact`-closes-the-shop all at once, and
## a `Control.FOCUS_NONE` button tree has no "current row" to move.
##
## The keys are the ones a player already has: [constant InputActions.MOVE_FORWARD] and
## `MOVE_BACK` (W/S, left stick) move the highlight, `ui_up`/`ui_down` (arrows, d-pad) do
## the same, and `ui_accept` (Enter, Space, gamepad A) trades the highlighted row.
## [constant InputActions.INTERACT] still *closes*, unchanged: the key that opened the
## counter is the key that shuts it, and a player who taps E twice must not buy a seed
## packet on the way out.

## Rows are rebuilt on open, so this is the whole list.
const ROW_HEIGHT := 30.0

## The selection wraps. A list of seventeen rows with no wrap is a list where holding S
## does nothing at the bottom, which is the same silence as above, one row shorter.
const WRAP := true

@onready var _title: Label = get_node_or_null(^"Center/Panel/Column/Title")
@onready var _gold: Label = get_node_or_null(^"Center/Panel/Column/Gold")
@onready var _rows: VBoxContainer = get_node_or_null(^"Center/Panel/Column/Rows")
@onready var _message: Label = get_node_or_null(^"Center/Panel/Column/Message")
@onready var _close: Button = get_node_or_null(^"Center/Panel/Column/Close")

var _shop: Shop = null
## Whether *this* panel is the thing currently pausing the game.
##
## Not cosmetic: `GameState.set_paused(false)` forces the phase back to PLAYING, so
## a panel that unpaused unconditionally would silently cancel a real pause menu.
## Only the holder releases.
var _holds_pause := false
## Every tradeable row on screen, as `{"kind": &"buy"|&"sell", "item_id": StringName,
## "row": PanelContainer, "button": Button}`, in the order they are drawn.
var _entries: Array[Dictionary] = []
## Index into [member _entries], or -1 when there is nothing to select.
var _selected := -1


func _ready() -> void:
	# Above every world HUD, and above the pause overlay's usual layer, because a
	# shop screen that a pause menu can cover is a shop screen the player cannot
	# finish a trade in.
	layer = 20
	visible = false
	# The tree is paused while this is open, and this panel is the thing that has
	# to keep answering input through that pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _close != null:
		_close.pressed.connect(close)
	EventBus.shop_opened.connect(_on_shop_opened)


func _exit_tree() -> void:
	# Freed while open — a scene reload mid-trade, or a test dropping its rig —
	# would otherwise leave the tree paused forever and every later system frozen.
	_release_pause()


## Shows [param shop]'s stock.
func open(shop: Shop) -> void:
	_shop = shop
	visible = true
	# The counter is modal, and pausing the tree is how that is enforced here.
	# It is the one gate that stops *everything* at once: the player keeps walking
	# with the panel up, and the interaction probe — which consumes `interact` in
	# `_unhandled_input` before this panel's own close handler can claim it — will
	# re-fire the counter behind the panel. Pausing stops both, and the clock with
	# them, which is also correct: the day should not advance while you shop.
	GameState.set_paused(true)
	_holds_pause = true
	# The message belongs to the *session*, not to the row list: cleared on open so a
	# stale "Not enough gold." never greets the next shop, and left alone by the rebuild
	# that follows a trade so the player can still read what just happened.
	_message.text = ""
	_rebuild()


func close() -> void:
	visible = false
	_shop = null
	_release_pause()


func _release_pause() -> void:
	if not _holds_pause:
		return
	_holds_pause = false
	GameState.set_paused(false)


func _on_shop_opened(shop: Shop) -> void:
	open(shop)


func _rebuild() -> void:
	# `is_instance_valid`, not `== null`: the counter lives in the world, and a
	# panel left open across a scene change holds a freed node that a null check
	# happily accepts. See `_refresh_gold`.
	if _shop == null or not is_instance_valid(_shop) or _shop.shop == null:
		_shop = null
		return
	var service := _shop.economy()
	if service == null:
		return

	# Remembered *by identity* across the rebuild, not by index. A keyboard player who
	# bought one packet of parsnip seeds and wants a second must be left on the
	# parsnip seed row, not thrown back to the top of the list to find it again — and an
	# index would be wrong anyway, because selling the last of something removes rows
	# above it.
	var keep: Dictionary = selected_entry()
	var kind := StringName(keep.get("kind", &""))
	var item_id := StringName(keep.get("item_id", &""))

	if _title != null:
		_title.text = _shop.shop.display_name
	_refresh_gold()

	for child: Node in _rows.get_children():
		child.queue_free()
	_entries.clear()
	_selected = -1

	# Buyable rows only. A stocked item with no price is a content mistake; showing
	# it as an unclickable row tells the player nothing and hides the mistake from
	# the author, so `invalid_stock` is what reports it (and a content test asserts
	# it is empty).
	for stocked: StringName in EconomyService.buyable_stock(_shop.shop):
		_add_buy_row(stocked, service)
	_add_sell_rows(service)

	var restored := _index_of_trade(kind, item_id)
	if restored >= 0:
		_select(restored)
	else:
		_select(0 if not _entries.is_empty() else -1)


## Index of the row trading [param kind] of [param item_id], or -1 if that row is gone.
func _index_of_trade(kind: StringName, item_id: StringName) -> int:
	for i: int in range(_entries.size()):
		var entry := _entries[i]
		if StringName(entry.get("kind", &"")) == kind \
				and StringName(entry.get("item_id", &"")) == item_id:
			return i
	return -1


func _add_buy_row(item_id: StringName, service: EconomyService) -> void:
	var panel := PanelContainer.new()
	panel.name = "Buy_%s" % item_id
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var name_label := _make_label("Name", ItemRegistry.display_name_of(item_id), 15)
	name_label.custom_minimum_size.x = 220
	row.add_child(name_label)
	row.add_child(_make_label("Price", "%dg" % EconomyService.price_of(_shop.shop, item_id), 15))

	var buy := _make_button("Buy", 64)
	buy.pressed.connect(_on_buy_pressed.bind(item_id))
	row.add_child(buy)

	_rows.add_child(panel)
	_register_entry(&"buy", item_id, panel, buy)


func _add_sell_rows(service: EconomyService) -> void:
	var totals: Dictionary = _shop.sellable_totals()
	if totals.is_empty():
		return
	var heading := _make_label("SellHeading", "You carry", 13)
	heading.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62))
	_rows.add_child(heading)
	for key: StringName in totals.keys():
		_add_sell_row(key, service)


func _add_sell_row(item_id: StringName, service: EconomyService) -> void:
	var panel := PanelContainer.new()
	panel.name = "Sell_%s" % item_id
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var name_label := _make_label("Name", ItemRegistry.display_name_of(item_id), 15)
	name_label.custom_minimum_size.x = 220
	row.add_child(name_label)
	row.add_child(_make_label("Price", "%dg" % EconomyService.pays_for(_shop.shop, item_id), 15))

	var sell := _make_button("Sell", 64)
	sell.pressed.connect(_on_sell_pressed.bind(item_id))
	row.add_child(sell)

	_rows.add_child(panel)
	_register_entry(&"sell", item_id, panel, sell)


## Records one tradeable row so the keyboard can find it.
##
## Hover moves the highlight as well, because a player who has the mouse on a row and
## then presses Enter means *that* row — not the one the keyboard last left selected.
func _register_entry(kind: StringName, item_id: StringName, row: PanelContainer,
		button: Button) -> void:
	var index := _entries.size()
	_entries.append({"kind": kind, "item_id": item_id, "row": row, "button": button})
	button.mouse_entered.connect(func() -> void: _select(index))


## Moves the highlight to [param index], wrapping when [constant WRAP].
func _select(index: int) -> void:
	if _entries.is_empty():
		_selected = -1
		return
	_selected = index if WRAP else clampi(index, 0, _entries.size() - 1)
	if WRAP:
		_selected = posmod(_selected, _entries.size())
	for i: int in range(_entries.size()):
		_paint_row(_entries[i], i == _selected)


func _move_selection(step: int) -> void:
	if _entries.is_empty():
		return
	# From "nothing selected", any direction starts at an end rather than jumping to
	# the middle: S from a fresh panel lands on the second row, which is what a player
	# pressing S expects.
	var from := _selected if _selected >= 0 else (0 if step > 0 else _entries.size() - 1)
	_select(from + step)


## Draws or clears the highlight on one row.
##
## A stylebox rather than `modulate`: dimming the row also dims the price, and the price
## is the number the player is comparing.
func _paint_row(entry: Dictionary, selected: bool) -> void:
	var row: PanelContainer = entry.get("row")
	if row == null or not is_instance_valid(row):
		return
	if selected:
		row.add_theme_stylebox_override("panel", _selection_style())
	else:
		row.remove_theme_stylebox_override("panel")


func _selection_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.31, 0.18, 0.55)
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.border_color = Color(0.86, 0.74, 0.42, 0.95)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


## Trades the highlighted row, if there is one.
func _confirm_selection() -> bool:
	if _selected < 0 or _selected >= _entries.size():
		return false
	var entry := _entries[_selected]
	var item_id := StringName(entry.get("item_id", &""))
	if StringName(entry.get("kind", &"")) == &"buy":
		_on_buy_pressed(item_id)
	else:
		_on_sell_pressed(item_id)
	return true


## The highlighted row, as `{"kind", "item_id"}`, for tests and for the hint line.
func selected_entry() -> Dictionary:
	if _selected < 0 or _selected >= _entries.size():
		return {}
	return _entries[_selected]


func _on_buy_pressed(item_id: StringName) -> void:
	if _shop == null or not is_instance_valid(_shop):
		_shop = null
		return
	var result: Dictionary = _shop.buy(item_id, 1)
	_report(result, "Bought")


func _on_sell_pressed(item_id: StringName) -> void:
	if _shop == null or not is_instance_valid(_shop):
		_shop = null
		return
	var result: Dictionary = _shop.sell(item_id, 1)
	_report(result, "Sold")


## Turns a trade result into one line of text, then rebuilds.
##
## Every refusal gets a message. A shop that silently ignores an unaffordable
## purchase is indistinguishable from one that has crashed, and the refusal reason
## travels all the way from `EconomyService` precisely so it can be shown here.
##
## The rebuild is what keeps the list honest. Without it the "You carry" rows are a
## snapshot: sell your last parsnip and its Sell row stays on screen, so a player who
## was told the row is still there mashes Enter on a trade that can no longer happen.
## The message is written first so it survives the rebuild.
func _report(result: Dictionary, verb: String) -> void:
	if bool(result.get("ok", false)):
		_message.add_theme_color_override("font_color", Color(0.70, 0.88, 0.62))
		_message.text = "%s %s for %dg." % [
			verb, ItemRegistry.display_name_of(result.get("item_id", &"")),
			int(result.get("total", 0)),
		]
	else:
		_message.add_theme_color_override("font_color", Color(0.92, 0.62, 0.58))
		_message.text = _explain(String(result.get("reason", "")))
	_rebuild()


## Human wording for a refusal code.
##
## Falls back to the raw reason so an unrecognised code is visible rather than
## silently swallowed — a new refusal reason added without a line here should look
## wrong, not invisible.
func _explain(reason: String) -> String:
	match reason:
		"poor":
			return "Not enough gold."
		"bag_full":
			return "Your bag is full."
		"not_stocked":
			return "This shop does not sell that."
		"unpriced":
			return "That cannot be bought here."
		"not_sellable":
			return "This shop will not buy that."
		"no_item":
			return "You do not have any."
		"no_shop", "no_economy_service":
			return "This counter cannot trade."
		_:
			return "Cannot trade: %s" % reason


func _refresh_gold() -> void:
	if _gold == null or _shop == null:
		return
	# `is_instance_valid` before `== null`: a shop freed with the scene that
	# spawned it leaves `_shop` a dead reference that passes a null check and then
	# throws on the next access.
	if not is_instance_valid(_shop):
		_shop = null
		return
	var state := PlayerStateService.find()
	if state == null or state.wallet == null:
		return
	_gold.text = "Your gold: %dg" % state.wallet.gold


func _make_label(label_name: String, text: String, size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.88))
	return label


func _make_button(caption: String, width: float) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(width, 26)
	# Focus is off because this panel draws its own highlight; two systems marking the
	# same row is how a panel ends up showing two highlights, or the engine's on a row
	# the keyboard never moved to.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# `Escape` is checked first and on its own. `ui_cancel` and `interact` are
	# separate actions, but a player pressing Escape while a gamepad focus sits on
	# a Buy button produces the confirm press too, and handling both from one branch
	# would close the shop and then immediately re-buy whatever was focused.
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	# Movement before `interact`, and checked with `echo` filtered by
	# `is_action_pressed`: holding W down must not run the highlight off the end of
	# the list one row per frame.
	if _consume_step(event, -1):
		get_viewport().set_input_as_handled()
		return
	if _consume_step(event, 1):
		get_viewport().set_input_as_handled()
		return
	# Confirm, then close. Both claim the press so it cannot also reach the world
	# behind the panel — the tree is paused, but the interaction probe is not
	# necessarily, and a purchase that also re-opened the counter would look like a
	# very strange bug.
	if event.is_action_pressed(&"ui_accept"):
		if _confirm_selection():
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(InputActions.INTERACT):
		# The same key that opened the shop closes it. This is unhandled input, so
		# the viewport must be told the press is spent or it also reaches the
		# interaction probe behind the panel.
		close()
		get_viewport().set_input_as_handled()


## One row up or down, from either the movement keys or the arrow keys.
##
## Both spellings are read because this is a 3D game: the player who pressed W to walk
## into the counter will press W again to move the highlight, and the player who has
## their hand on the arrow keys expects those to work in a menu too. Returns whether the
## event was one of them, so the caller can mark it handled.
##
## W is *up the list*, which is the whole reason this reads the movement actions at all.
## `move_forward` is the key the player pressed to arrive at the counter, so treating it
## as "down" would move the highlight the opposite way from the key they are pressing —
## a menu that scrolls away from your thumb.
func _consume_step(event: InputEvent, step: int) -> bool:
	var walking := InputActions.MOVE_FORWARD if step < 0 else InputActions.MOVE_BACK
	var arrows := &"ui_up" if step < 0 else &"ui_down"
	if event.is_action_pressed(walking) or event.is_action_pressed(arrows):
		_move_selection(step)
		return true
	return false