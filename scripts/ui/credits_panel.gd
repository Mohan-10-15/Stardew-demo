extends CanvasLayer
## Generated credits screen, reachable from the title and the pause menu.

const DATA := "res://resources/ui/credits.tres"

@onready var _list: RichTextLabel = get_node_or_null(^"Panel/Column/List") as RichTextLabel

var _data: CreditsData = null


func _ready() -> void:
	layer = 32
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_data = ResourceLoader.load(DATA) as CreditsData


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	if _list == null or _data == null:
		return
	var text := "[center][b]%s[/b][/center]\n\n" % _data.title
	for entry: CreditEntry in _data.entries:
		text += "[b]%s[/b]\n%s\n\n" % [entry.label, entry.detail]
	_list.text = text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
