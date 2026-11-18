extends CanvasLayer
## A quiet crafting panel: C opens and closes it, number keys craft the listed
## recipe. It is a listener and a caller; all rules live in CraftingService.

@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows") as VBoxContainer
var _open := false
var _service: CraftingService = null
var _recipe_ids: Array[StringName] = []


func _ready() -> void:
	layer = 12
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = CraftingService.find(get_tree().get_root())
	var bus := _bus()
	if bus != null:
		bus.craft_succeeded.connect(_on_craft)
		bus.craft_failed.connect(_on_craft)


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.craft_succeeded.is_connected(_on_craft):
		bus.craft_succeeded.disconnect(_on_craft)
	if bus.craft_failed.is_connected(_on_craft):
		bus.craft_failed.disconnect(_on_craft)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.CRAFT) \
			or (event.is_action_pressed(&"pause") and _open):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	var number_keys := InputActions.hotbar_actions()
	for i: int in range(number_keys.size()):
		if event.is_action_pressed(number_keys[i]):
			if i < _recipe_ids.size():
				_service.craft(_recipe_ids[i])
			get_viewport().set_input_as_handled()
			return


func _toggle() -> void:
	_open = not _open
	visible = _open
	if _open:
		_refresh()


func _on_craft(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if _open:
		_refresh()


func _refresh() -> void:
	if _rows == null or _service == null:
		return
	for child: Node in _rows.get_children():
		child.free()
	_recipe_ids.clear()
	var recipes := CraftingService.all_recipes()
	for i: int in range(recipes.size()):
		var recipe := recipes[i]
		_recipe_ids.append(recipe.id)
		var label := Label.new()
		label.name = "Recipe%d" % i
		var ready_mark := "OK" if _service.can_craft(recipe.id) == &"" else "needs items"
		label.text = "%d  %s  →  %dx %s  [%s]" % [
			i + 1, recipe.display_name, recipe.output_count,
			String(recipe.output_id), ready_mark,
		]
		_rows.add_child(label)


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
