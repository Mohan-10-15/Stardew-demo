extends CanvasLayer
## The front door: new game or continue.
##
## The world is already built behind this screen — building a second world just
## for a menu would mean two valleys, two clocks and two sets of listeners. The
## title owns no game state; it asks `main.gd` to start or continue through two
## signals, like every other UI element in this project.

signal new_game_requested()
signal continue_requested()

const SAVE_SERVICE_GROUP := &"save_service"

@onready var _continue: Button = get_node_or_null(^"Panel/Column/Continue") as Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var new_game := get_node_or_null(^"Panel/Column/NewGame") as Button
	if new_game != null and not new_game.pressed.is_connected(_on_new_game):
		new_game.pressed.connect(_on_new_game)
	if _continue != null and not _continue.pressed.is_connected(_on_continue):
		_continue.pressed.connect(_on_continue)
	refresh()


## Enables Continue only when a save actually exists. A permanently live button
## that silently does nothing when clicked is the sort of menu defect a player
## reports as a broken game.
func refresh() -> void:
	if _continue == null:
		return
	var save := _find_service()
	_continue.disabled = save == null or not bool(save.call("has_save"))


func _on_new_game() -> void:
	new_game_requested.emit()


func _on_continue() -> void:
	continue_requested.emit()


func _find_service() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return _search((loop as SceneTree).root)


func _search(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group(SAVE_SERVICE_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null
