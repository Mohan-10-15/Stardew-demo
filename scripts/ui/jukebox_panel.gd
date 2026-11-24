extends CanvasLayer
## W6.6: replays cues the player has actually heard. No unlock cheating —
## only ids in GameConfig.jukebox_unlocked are offered.

@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows") as VBoxContainer

var _open := false
var _ids: Array[StringName] = []


func _ready() -> void:
	layer = 16
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(InputActions.JUKEBOX):
		if _open:
			_close()
		else:
			_open_panel()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_down"):
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		if _ids.size() > 0:
			var director := MusicDirector.find(get_tree().root)
			if director != null:
				director.call("play_cue", _ids[_selected()])
				_close()
		get_viewport().set_input_as_handled()


func _open_panel() -> void:
	_open = true
	visible = true
	_refresh()


func _close() -> void:
	_open = false
	visible = false


func _selected() -> int:
	if _rows == null:
		return 0
	for i: int in range(_rows.get_child_count()):
		var label := _rows.get_child(i) as Label
		if label != null and label.text.begins_with("> "):
			return i
	return 0


func _move(delta: int) -> void:
	if _rows == null or _rows.get_child_count() == 0:
		return
	var current := _selected()
	var next := wrapi(current + delta, 0, _rows.get_child_count())
	for i: int in range(_rows.get_child_count()):
		var label := _rows.get_child(i) as Label
		if label == null:
			continue
		label.text = ("%s" % label.text).substr(2) if i == current and label.text.begins_with("> ") else label.text
		if i == next:
			label.text = "> " + label.text


func _refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.free()
	_ids.clear()
	var director := MusicDirector.find(get_tree().root)
	if director == null:
		return
	_ids = director.call("unlocked_cues")
	if _ids.is_empty():
		var empty := Label.new()
		empty.text = "No cues heard yet — play the valley first."
		_rows.add_child(empty)
		return
	for i: int in range(_ids.size()):
		var label := Label.new()
		label.text = ("%s " % ">") if i == 0 else "  "
		label.text += String(_ids[i]).capitalize()
		_rows.add_child(label)
