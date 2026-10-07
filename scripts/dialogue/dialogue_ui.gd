extends CanvasLayer
## The conversation panel: who is speaking, what they are saying, and the
## replies on offer.
##
## ## It owns no rules
##
## Same split as [ShopUI] and [QuestTrackerHud]: every line of text, every
## reply and every consequence comes from [DialogueService], and this panel
## draws what it is told. The moment the panel decided *which* line to show, the
## selection logic would exist twice and the two would disagree the first time a
## condition changed.
##
## ## It is a listener, driven by three signals
##
## [signal EventBus.dialogue_started] opens it, [signal EventBus.dialogue_line_changed]
## repaints it, [signal EventBus.dialogue_finished] closes it. Nothing here
## re-reads the tree on its own, so a headless test that drives the service
## moves the exact pixels the game moves — there is no second path.
##
## ## The typewriter, and the key that skips it
##
## Text reveals a character at a time because a wall of text appearing at once
## is a wall the player skips reading. The first press of the interact key
## finishes the line instead of advancing past it, which is the convention every
## readable dialogue box has had since the genre existed: one key to read, one
## key to move on. Holding nothing back — the full text is in the label's
## metadata from the first frame, so an accessibility read or a screen reader
## is never fed a half-finished sentence by a system that thinks it is helping.
##
## ## It holds the pause, and must never strand it
##
## The conversation is modal the same way the counter is: the clock stops, the
## player stops, the interaction probe stops consuming the key. Only this panel
## releases the pause, and [method _exit_tree] releases it too — a panel freed
## mid-conversation must not leave the whole game frozen. See
## [ShopUI._release_pause] for the same bargain.

## Characters revealed per second. Deliberately brisk: slow enough to read
## along with, fast enough that a villager is not done talking by the time the
## player looks away.
const CPS := 42.0

## The colour the villager's name is drawn in. Distinct from the body text so
## the eye finds "who" without reading "what".
const NAME_COLOR := Color(0.98, 0.85, 0.55)

## The colour a selected reply is drawn in — the keyboard's highlight, since
## replies are real buttons with engine focus off (two systems marking the same
## row is how a panel ends up with two highlights).
const CHOICE_SELECTED := Color(0.20, 0.24, 0.18, 0.92)

@onready var _panel: PanelContainer = get_node_or_null(^"Panel")
@onready var _name: Label = get_node_or_null(^"Panel/Column/NameLabel")
@onready var _text: Label = get_node_or_null(^"Panel/Column/TextLabel")
@onready var _choices: VBoxContainer = get_node_or_null(^"Panel/Column/Choices")
@onready var _continue: Label = get_node_or_null(^"Panel/Column/Continue")

## The service, re-found on every open rather than cached: tests drop their rig
## between cases, and a cached node from a dead tree is a null check that lies.
var _service: Node = null
## Whether characters are still being revealed for the current line.
var _typing := false
## Characters revealed so far.
var _revealed := 0
## The whole line, kept so the typewriter can finish it and a test can assert
## on what *will* be said rather than on a growing prefix.
var _full_text := ""
## Which reply the keyboard is pointing at.
var _selected := 0
## The reply buttons, in draw order, so selection paints a known list.
var _buttons: Array[Button] = []
## Whether *this* panel is the thing currently pausing the game.
## Not cosmetic — see [ShopUI._holds_pause].
var _holds_pause := false


func _ready() -> void:
	layer = 20
	visible = false
	# The tree is paused while a conversation runs, and this panel has to keep
	# answering input and ticking the typewriter through that pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_line_changed.connect(_on_dialogue_line_changed)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	_apply_name_color()


func _exit_tree() -> void:
	# Freed while open — a scene reload mid-sentence — must not strand the
	# pause, exactly as the shop panel's own _exit_tree.
	_release_pause()


func _process(delta: float) -> void:
	if not visible:
		return
	# The blink belongs to the *continue* hint only: a conversation waiting for
	# a reply must not hint that a keypress will carry it forward.
	if _continue != null:
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 260.0)
		_continue.modulate.a = pulse if _continue.visible else 0.0
	if not _typing:
		return
	_revealed = mini(_revealed + int(ceil(CPS * delta)), _full_text.length())
	_text.text = _full_text.substr(0, _revealed)
	if _revealed >= _full_text.length():
		_typing = false
		_refresh_continue()


# --- Signal ends -------------------------------------------------------------

func _on_dialogue_started(npc_id: StringName, _entry_id: StringName) -> void:
	_service = _find_service()
	if _service == null:
		return
	visible = true
	if _name != null:
		_name.text = _speaker_name(npc_id)
	_show_current_line()
	# Paused last, so the line is already on screen when the world stops: a
	# panel that pauses first and paints second is one frame of an empty box.
	GameState.set_paused(true)
	_holds_pause = true


func _on_dialogue_line_changed(_npc_id: StringName, _entry_id: StringName) -> void:
	if not visible:
		return
	_show_current_line()


func _on_dialogue_finished(_npc_id: StringName, _entry_id: StringName) -> void:
	close()


# --- Drawing the current line -------------------------------------------------

## Paints whatever the service is showing right now: text, typewriter restart,
## replies. Called on open and on every line change; never guesses.
func _show_current_line() -> void:
	if _service == null:
		return
	_full_text = String(_service.call("current_text"))
	_revealed = 0
	_typing = not _full_text.is_empty()
	if _text != null:
		_text.text = "" if _typing else _full_text
	_selected = 0
	_rebuild_choices()
	_refresh_continue()


## The reply buttons for the current line, built fresh.
##
## Built rather than kept: the number of replies is content, and a scene that
## shipped a fixed row of buttons would show blanks for a villager who offers
## one and hide the fourth reply from one who offers four.
func _rebuild_choices() -> void:
	if _choices == null:
		return
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_buttons.clear()
	var offers: Array = _service.call("current_choices") if _service != null else []
	for i: int in offers.size():
		var offer: Resource = offers[i]
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, String(offer.get("text"))]
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 30)
		var index := i
		button.pressed.connect(func() -> void: _take_choice(index))
		_choices.add_child(button)
		_buttons.append(button)
	_paint_choices()


func _paint_choices() -> void:
	for i: int in _buttons.size():
		var style := StyleBoxFlat.new()
		if i == _selected:
			style.bg_color = CHOICE_SELECTED
		else:
			style.bg_color = Color(0, 0, 0, 0)
		style.set_corner_radius_all(4)
		_buttons[i].add_theme_stylebox_override("normal", style)
		_buttons[i].add_theme_stylebox_override("hover", style)


func _refresh_continue() -> void:
	if _continue == null:
		return
	var awaiting := bool(_service.call("is_awaiting_choice")) if _service != null else false
	# No hint while typing (the key would finish the line, not continue it) and
	# none while replies are up (the key would do nothing, and a hint that lies
	# about what a key does is how a player concludes the game is broken).
	_continue.visible = visible and not _typing and not awaiting
	if _continue.visible:
		_continue.text = "▼  %s  Continue" % _interact_label()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		# Walk away mid-sentence. Ends the conversation without applying the
		# line the player never finished; the finished signal closes us.
		if _service != null:
			_service.call("cancel")
		get_viewport().set_input_as_handled()
		return
	var awaiting := bool(_service.call("is_awaiting_choice")) if _service != null else false
	if awaiting:
		if _consume_step(event, -1) or _consume_step(event, 1):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_accept"):
			_take_choice(_selected)
			get_viewport().set_input_as_handled()
			return
		# A reply row is up: the interact key has nothing to advance to, and
		# claiming the press keeps it from re-firing the villager behind us.
		if event.is_action_pressed(InputActions.INTERACT):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.INTERACT) \
			or event.is_action_pressed(&"ui_accept"):
		if _typing:
			# First press finishes the line, second moves on.
			_finish_typing()
		elif _service != null:
			_service.call("advance")
		get_viewport().set_input_as_handled()


## One reply up or down, from movement, arrows, or the number keys.
##
## Number keys jump straight to a reply: three replies is a menu, and a menu
## whose rows are labelled 1–3 should answer 1–3. Returns whether the event was
## one of these, so the caller can mark it handled.
func _consume_step(event: InputEvent, step: int) -> bool:
	if _buttons.is_empty():
		return false
	var walking := InputActions.MOVE_FORWARD if step < 0 else InputActions.MOVE_BACK
	var arrows := &"ui_up" if step < 0 else &"ui_down"
	if event.is_action_pressed(walking) or event.is_action_pressed(arrows):
		_selected = wrapi(_selected + step, 0, _buttons.size())
		_paint_choices()
		return true
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var code := (event as InputEventKey).physical_keycode
		var as_text := OS.get_keycode_string(code)
		if as_text.length() == 1 and as_text.is_valid_int():
			var index := int(as_text) - 1
			if index >= 0 and index < _buttons.size():
				_selected = index
				_paint_choices()
				return true
	return false


func _take_choice(index: int) -> void:
	if _service == null:
		return
	# True means another line is showing and [signal EventBus.dialogue_line_changed]
	# has already repainted us; false means the conversation ended and
	# [signal EventBus.dialogue_finished] has already closed us.
	_service.call("choose", index)


func _finish_typing() -> void:
	_typing = false
	_revealed = _full_text.length()
	if _text != null:
		_text.text = _full_text
	_refresh_continue()


func close() -> void:
	visible = false
	_full_text = ""
	_typing = false
	if _text != null:
		_text.text = ""
	_release_pause()


func _release_pause() -> void:
	if not _holds_pause:
		return
	_holds_pause = false
	GameState.set_paused(false)


# --- Helpers -----------------------------------------------------------------

func _find_service() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search(scene_root, DialogueService.SERVICE_GROUP)


static func _search(node: Node, group: StringName) -> Node:
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _search(child, group)
		if found != null:
			return found
	return null


## The villager's display name, from the content rather than from the id —
## "mira" on screen is a database key leaking into the conversation.
func _speaker_name(npc_id: StringName) -> String:
	var data := NpcRegistry.get_npc(npc_id)
	if data != null:
		return data.display_name
	return String(npc_id)


## The interact key's current binding, read from the InputMap so a remap shows
## up here without any code change. Same read as
## [method InteractionProbe.get_action_label].
func _interact_label() -> String:
	if InputMap.has_action(InputActions.INTERACT):
		for event: InputEvent in InputMap.action_get_events(InputActions.INTERACT):
			if event is InputEventKey:
				var code := (event as InputEventKey).physical_keycode
				if code == 0:
					code = (event as InputEventKey).keycode
				if code != 0:
					return OS.get_keycode_string(code)
	return "E"


func _apply_name_color() -> void:
	if _name != null:
		_name.add_theme_color_override("font_color", NAME_COLOR)
