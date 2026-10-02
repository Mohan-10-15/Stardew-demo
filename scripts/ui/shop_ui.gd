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

## Rows are rebuilt on open, so this is the whole list.
const ROW_HEIGHT := 30.0

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

	if _title != null:
		_title.text = _shop.shop.display_name
	_refresh_gold()

	for child: Node in _rows.get_children():
		child.queue_free()
	_message.text = ""

	# Buyable rows only. A stocked item with no price is a content mistake; showing
	# it as an unclickable row tells the player nothing and hides the mistake from
	# the author, so `invalid_stock` is what reports it (and a content test asserts
	# it is empty).
	for item_id: StringName in EconomyService.buyable_stock(_shop.shop):
		_add_buy_row(item_id, service)
	_add_sell_rows(service)


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
	_refresh_gold()


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
	if event.is_action_pressed(&"interact"):
		# The same key that opened the shop closes it. This is unhandled input, so
		# the viewport must be told the press is spent or it also reaches the
		# interaction probe behind the panel.
		close()
		get_viewport().set_input_as_handled()