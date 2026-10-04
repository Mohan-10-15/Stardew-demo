extends CanvasLayer
## The log, on screen, while the game is running.
##
## ## Why this exists
##
## `Log` writes to `user://hollowbrook.log` and to stdout. Neither is anywhere a player
## — or the person debugging a playtest — is looking: quitting the game, leaving the
## window and opening a file is the only way to read it, which in practice means nobody
## reads it. Every question of the form "did that actually happen?" during a playtest
## was unanswerable at the time it was asked.
##
## ## It does not pause the game
##
## The tempting design is a modal screen, because everything else in this game's UI is
## modal. That is wrong here: the whole point is to watch what is happening *while*
## playing, so pressing a key to hide it must not also stop the world. It draws over the
## top, takes no input except its own toggle, and the tree keeps running.
##
## ## It stays until you close it
##
## An earlier version faded itself out after three seconds, on the theory that a panel
## over the game is in the way. That is wrong for a log: the moment you open it is the
## moment something is happening that you want to watch for another twenty seconds, and
## a panel that vanishes mid-read is worse than no panel. It takes no input but its own
## toggle, so it obstructs nothing.

const MAX_VISIBLE_LINES := 200

@onready var _header: Label = get_node_or_null(^"Panel/Column/Header")
@onready var _text: RichTextLabel = get_node_or_null(^"Panel/Column/Scroll/Text")

var _log: Node = null


func _ready() -> void:
	# Above the HUDs and below the shop panel, so a trade in progress is never
	# half-covered by the log that is describing it.
	layer = 15
	visible = false
	_log = _find_log(get_tree().get_root())
	if _log == null:
		# Named rather than ignored: a panel that can never appear is a bug, and the
		# log is the one place a bug about logging would otherwise hide.
		Log.error("LogPanel", "no Log autoload in the tree; the panel will stay empty")
		return
	_log.connect(&"line_logged", Callable(self, "_on_line_logged"))


func _find_log(from: Node) -> Node:
	if from == null:
		return null
	if from.name == "Log":
		return from
	for child in from.get_children():
		var hit := _find_log(child)
		if hit != null:
			return hit
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(InputActions.TOGGLE_LOG_PANEL):
		toggle()
		get_viewport().set_input_as_handled()
		return
	# Escape closes it too, since that is what every other panel in the game answers.
	if visible and event.is_action_pressed(&"ui_cancel"):
		hide_panel()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	if _log == null:
		return
	visible = true
	_rebuild()


func hide_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


## F3 again, or click, to keep it up.
func _on_line_logged(_entry: Dictionary) -> void:
	if not visible or _text == null:
		return
	_text.append_text(_format(_entry))
	# `scroll_following` does the scrolling. It is only set when rebuilding, so a
	# player who has scrolled up to read something keeps their place.
	_text.scroll_following = true


func _rebuild() -> void:
	if _text == null or _log == null:
		return
	_text.clear()
	var lines: Array = _log.call("recent", MAX_VISIBLE_LINES)
	for entry: Dictionary in lines:
		_text.append_text(_format(entry))
	_text.scroll_following = true
	if _header != null:
		_header.text = "Log — %s — %d lines — F3 to close" % [
			str(_log.call("log_file_path")), lines.size(),
		]


## One line, coloured by level, as BBCode.
##
## The level is a colour and not a word because the shape of a log is: you scan it for
## the one red line. Spelling out every level in four letters triples the width of every
## row to say what the colour already said.
func _format(entry: Dictionary) -> String:
	var level := int(entry.get("level", 1))
	return "[color=%s]%s  %-12s %s[/color]\n" % [
		_colour(level), str(entry.get("time", "")),
		str(entry.get("category", "")), str(entry.get("message", "")),
	]


func _colour(level: int) -> String:
	match level:
		0:
			return "#8a8a86"
		2:
			return "#e0b24a"
		3:
			return "#e2605a"
		_:
			return "#cfd6c8"