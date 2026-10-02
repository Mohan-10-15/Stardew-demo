extends CanvasLayer
## The nine tool-belt slots along the bottom of the screen.
##
## ## Why the player cannot fly blind
##
## The number keys were bound and working long before anything drew a slot, and the
## result was a game where pressing 4 might select a hoe, a seed packet, or nothing
## at all, with no way to find out which. Every farming action is gated on what is
## held — `use_tool` resolves the held tool, planting resolves the held seed — so
## an invisible hotbar makes an entire game system unusable rather than merely
## unclear.
##
## Reads through [PlayerStateService] rather than subscribing to the inventory, for
## the same reason the status HUD does: the bag changes on nearly every swing, and
## nine labels rebuilt per swing is layout work producing identical strings.

const SLOT_COUNT := 9

@onready var _slots_root: HBoxContainer = get_node_or_null(^"Slots")

var _state: PlayerStateService = null
var _slot_labels: Array[Label] = []
var _slot_panels: Array[Panel] = []
## What each slot last rendered, so a repaint only redraws what changed.
var _last_texts: Array[String] = []
var _last_selected := -1


func _ready() -> void:
	# Above the clock and status panels, below the interaction HUD at 10.
	layer = 7
	_collect_slots()
	_state = _find_state(get_tree().get_root())
	if _state == null:
		Log.warn("HotbarHUD", "No PlayerStateService; the belt stays empty")
		return
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.hotbar_selection_changed.connect(_on_selection_changed)
	_refresh()


func _collect_slots() -> void:
	_slot_labels.clear()
	_slot_panels.clear()
	_last_texts.clear()
	if _slots_root == null:
		return
	for i: int in range(min(SLOT_COUNT, _slots_root.get_child_count())):
		var slot := _slots_root.get_child(i) as Panel
		if slot == null:
			continue
		_slot_panels.append(slot)
		_slot_labels.append(slot.get_node_or_null(^"SlotLabel") as Label)
		_last_texts.append("")


func _on_inventory_changed() -> void:
	_refresh()


func _on_selection_changed(_slot: int) -> void:
	_refresh()


func _refresh() -> void:
	if _state == null:
		return
	var bar: Hotbar = _state.hotbar
	if bar == null:
		return
	var selected := bar.get_selected()
	for i: int in range(_slot_labels.size()):
		var label := _slot_labels[i]
		if label != null:
			var text := bar.describe_slot(i)
			if text != _last_texts[i]:
				_last_texts[i] = text
				label.text = text
		# Highlight the held slot. Repainted separately from the text so that
		# switching slots costs one colour change rather than nine label rebuilds.
		if i != _last_selected or i == selected:
			_set_highlight(i, i == selected)
	_last_selected = selected


func _set_highlight(index: int, held: bool) -> void:
	if index < 0 or index >= _slot_panels.size():
		return
	_slot_panels[index].add_theme_stylebox_override("panel", _slot_style(held))


func _slot_style(held: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.30, 0.16, 0.88) if held else Color(0.10, 0.11, 0.14, 0.62)
	style.border_color = Color(0.95, 0.82, 0.45, 0.95) if held else Color(0.32, 0.30, 0.26, 0.85)
	# A held slot is called out with a border as well as a fill: colour alone does
	# not survive a bright sky behind it, and neither does this panel's own
	# translucency.
	style.set_border_width_all(2 if held else 1)
	style.set_corner_radius_all(5)
	return style


func _find_state(start: Node) -> PlayerStateService:
	if start == null:
		return null
	if start is PlayerStateService:
		return start
	for child: Node in start.get_children():
		var found := _find_state(child)
		if found != null:
			return found
	return null