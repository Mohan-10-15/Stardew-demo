extends CanvasLayer
## Data-driven "What is this game?" pages, reachable from the title and Help.
## Keyboard, mouse and pad navigable; Escape/B closes.

const DIR := "res://resources/ui/about/"

@onready var _title: Label = get_node_or_null(^"Panel/Column/Title") as Label
@onready var _body: RichTextLabel = get_node_or_null(^"Panel/Column/Body") as RichTextLabel
@onready var _counter: Label = get_node_or_null(^"Panel/Column/Counter") as Label

var _pages: Array[AboutPage] = []
var _index := 0
var _return_to_title := true


func _ready() -> void:
	layer = 31
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_pages()


func _load_pages() -> void:
	_pages.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for entry: String in dir.get_files():
		if not entry.ends_with(".tres"):
			continue
		var page := ResourceLoader.load(DIR + entry) as AboutPage
		if page != null and page.is_valid():
			_pages.append(page)
	_pages.sort_custom(func(a: AboutPage, b: AboutPage) -> bool: return a.order < b.order)


func open(from_title: bool = true, at_id: StringName = &"") -> void:
	_return_to_title = from_title
	_index = 0
	if at_id != &"":
		for i: int in range(_pages.size()):
			if _pages[i].id == at_id:
				_index = i
				break
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	if _pages.is_empty() or _title == null or _body == null:
		return
	var page := _pages[_index]
	_title.text = page.title
	_body.text = page.body
	_counter.text = "Page %d / %d   —   %s prev / %s next / %s back" % [
		_index + 1, _pages.size(),
		InputGlyphs.label_for(InputActions.HOTBAR_SLOT_PREV),
		InputGlyphs.label_for(InputActions.HOTBAR_SLOT_NEXT),
		InputGlyphs.label_for(InputActions.PAUSE),
	]


func next_page() -> void:
	if _pages.is_empty():
		return
	_index = (_index + 1) % _pages.size()
	_refresh()


func prev_page() -> void:
	if _pages.is_empty():
		return
	_index = (_index - 1 + _pages.size()) % _pages.size()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.HOTBAR_SLOT_NEXT) \
			or event.is_action_pressed(&"ui_right"):
		next_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.HOTBAR_SLOT_PREV) \
			or event.is_action_pressed(&"ui_left"):
		prev_page()
		get_viewport().set_input_as_handled()
