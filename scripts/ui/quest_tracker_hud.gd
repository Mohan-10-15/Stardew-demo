extends CanvasLayer
## The jobs the player is carrying, and how far along each one is.
##
## ## Why this exists
##
## Quest progress existed before this file: the service counted it, the prompt named it,
## and a hand-in paid it. None of that is visible. A player who accepted "Bring 5 Parsnips
## to Mira" had no way to learn that they were holding two, and the only number they could
## ever see was the refusal reason at the counter — after walking back to the farm. The
## prompt only appears when the crosshair is on a person, which is the one moment the
## player does not need the objective.
##
## ## It shows active jobs, not finished ones
##
## A turned-in quest leaves the list the moment it pays. Keeping it visible until the next
## day would fill the corner of the screen with rows the player already dismissed, and the
## list is small on purpose: three rows is the most anyone carries, so the panel can state
## the whole thing rather than scroll.
##
## ## It reads the service, it does not keep its own copy
##
## The lines are rebuilt from [method QuestService.active_quests] and
## [method QuestService.get_progress] on each repaint. A tracker holding its own tally
## would be a second answer to "how many parsnips does this player still need", and two
## answers drift the moment one of them is fixed.
##
## ## It never pauses the game
##
## Same reasoning as [LogPanel]: this is a readout, not a screen. It takes no input and no
## toggle, and the tree keeps running while it is up.

@onready var _panel: PanelContainer = get_node_or_null(^"Panel")
@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows")

## Most lines shown. Beyond this the panel would reach the middle of the screen, and a
## quest list that covers the crosshair is worse than a truncated one.
const MAX_ROWS := 4

var _service: QuestService = null
## The lines as last drawn, so a repaint that would produce identical text touches
## nothing. The bag and every gathering event can move a row's numbers.
var _last_lines: PackedStringArray = PackedStringArray()
## What the rows currently say, so a repaint that changes nothing skips the rebuild that
## would otherwise re-create a label per row on every event the bus publishes.
var _dirty := true


func _ready() -> void:
	# Above the status HUD's gold-and-stamina panel (layer 6) and below the interaction
	# prompt (layer 10), so a crosshair prompt always draws over the tracker.
	layer = 7
	_service = _find_service(get_tree().get_root())
	if _service == null:
		Log.warn("QuestTrackerHUD", "No QuestService; the quest tracker stays empty")
		return
	EventBus.quest_accepted.connect(_on_quest_changed)
	EventBus.quest_turned_in.connect(_on_quest_changed)
	EventBus.quest_progress_changed.connect(_on_progress_changed)
	# A refusal does not change a tally, but it is the moment the player most wants to
	# read the line they were just refused on, so the panel repaints on it too.
	EventBus.quest_accepted_failed.connect(_on_refused_accept)
	EventBus.quest_turned_in_failed.connect(_on_refused)
	# Services announce their starting state during `_ready`, which may have been before
	# this node existed, so paint once immediately as well.
	_refresh()


func _exit_tree() -> void:
	for pair: Array in [[&"quest_accepted", _on_quest_changed],
			[&"quest_turned_in", _on_quest_changed],
			[&"quest_progress_changed", _on_progress_changed],
			[&"quest_accepted_failed", _on_refused_accept],
			[&"quest_turned_in_failed", _on_refused]]:
		var name: StringName = pair[0]
		if EventBus.is_connected(name, pair[1]):
			EventBus.disconnect(name, pair[1])


func _on_quest_changed(_quest_id: StringName, _other: StringName) -> void:
	_dirty = true
	_refresh()


func _on_progress_changed(_quest_id: StringName, _current: int, _required: int) -> void:
	_dirty = true
	_refresh()


func _on_refused(_quest_id: StringName, _npc_id: StringName, _reason: StringName) -> void:
	_dirty = true
	_refresh()


func _on_refused_accept(_quest_id: StringName, _reason: StringName) -> void:
	_dirty = true
	_refresh()


## Repaints if anything it would draw has changed.
func _refresh() -> void:
	if _rows == null or _panel == null:
		return
	var service := _live_service()
	if service == null:
		if _last_lines.size() > 0:
			_last_lines = PackedStringArray()
			_panel.visible = false
		return
	var lines := _lines_for(service)
	if not _dirty and lines == _last_lines:
		return
	_dirty = false
	_last_lines = lines
	_draw(lines)
	# Hidden rather than an empty box: an empty tracker in the corner of the screen is a
	# piece of UI a player learns to look straight past.
	_panel.visible = not lines.is_empty()


## One line per active job: the title, what it wants, and how far along it is.
func _lines_for(service: QuestService) -> PackedStringArray:
	var out := PackedStringArray()
	var quests: Array[QuestData] = service.active_quests()
	for data: QuestData in quests:
		if out.size() >= MAX_ROWS:
			break
		out.append(_line_for(service, data))
	return out


## "Bring 5 Parsnips to Mira  3/5"
##
## Ready rows are marked with a word rather than a glyph. The default font is not
## guaranteed to carry a checkmark, and a row of tofu boxes next to the crosshair is
## worse than a row of English. A job the player can hand in right now is the one they
## least want to lose track of, so it stays in the list and says so.
func _line_for(service: QuestService, data: QuestData) -> String:
	var objective := data.objective
	if objective == null:
		return data.title
	var progress: QuestProgress = service.get_progress(data.id)
	var current := objective.current_amount(progress)
	var required := objective.required_amount()
	var mark := "  ready" if service.is_ready_to_turn_in(data.id) else ""
	return "%s  %s  %d/%d%s" % [
		data.title,
		objective.describe(QuestReward.item_name(objective.item_id), data.describe_giver()),
		current, required, mark,
	]


## Rebuilds the rows from scratch, reusing label nodes where it can.
##
## Cleared and re-added rather than mutated in place because the number of rows changes
## with the quest log, and a tracker that only ever adds rows leaves a row of blanks
## behind when the player finishes a job.
func _draw(lines: PackedStringArray) -> void:
	if _rows.get_child_count() != lines.size():
		for child: Node in _rows.get_children():
			child.queue_free()
		for _i in lines.size():
			_rows.add_child(_make_row())
	for index in lines.size():
		var row := _rows.get_node_or_null(NodePath("Row%d" % index)) as HBoxContainer
		if row == null:
			continue
		var label := row.get_node_or_null(^"Label") as Label
		if label != null:
			label.text = lines[index]


func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row%d" % _rows.get_child_count()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.name = "Label"
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.88))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 2)
	row.add_child(label)
	return row


## Re-locates the quest service if the one we cached is gone.
##
## Same reason as [PlayerStatusHUD._live_state]: a hard reference to a freed node is not
## `null`, so the only way to survive a scene change this HUD did not initiate is to
## re-resolve. A tracker that throws on the first world rebuild is a tracker nobody sees.
func _live_service() -> QuestService:
	if _service != null and is_instance_valid(_service):
		return _service
	_service = _find_service(get_tree().get_root())
	return _service


func _find_service(from: Node) -> QuestService:
	if from == null:
		return null
	if from is QuestService:
		return from
	for child: Node in from.get_children():
		var found := _find_service(child)
		if found != null:
			return found
	return null
