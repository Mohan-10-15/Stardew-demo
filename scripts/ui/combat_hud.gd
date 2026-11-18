extends CanvasLayer
## Health and mine status. A listener only; all state lives in CombatService.

@onready var _bar: ProgressBar = get_node_or_null(^"Panel/Column/Health") as ProgressBar
@onready var _label: Label = get_node_or_null(^"Panel/Column/Status") as Label
var _service: Node = null


func _ready() -> void:
	layer = 9
	_service = _find_service()
	if _service == null:
		return
	EventBus.player_damaged.connect(_on_changed)
	EventBus.player_respawned.connect(_on_changed)
	EventBus.mine_entered.connect(_on_changed)
	EventBus.mine_cleared.connect(_on_changed)
	EventBus.mine_boss_spawned.connect(_on_changed)
	EventBus.mine_floor_changed.connect(_on_changed)
	_refresh()


func _exit_tree() -> void:
	if EventBus.player_damaged.is_connected(_on_changed):
		EventBus.player_damaged.disconnect(_on_changed)
	if EventBus.player_respawned.is_connected(_on_changed):
		EventBus.player_respawned.disconnect(_on_changed)
	if EventBus.mine_entered.is_connected(_on_changed):
		EventBus.mine_entered.disconnect(_on_changed)
	if EventBus.mine_cleared.is_connected(_on_changed):
		EventBus.mine_cleared.disconnect(_on_changed)
	if EventBus.mine_boss_spawned.is_connected(_on_changed):
		EventBus.mine_boss_spawned.disconnect(_on_changed)
	if EventBus.mine_floor_changed.is_connected(_on_changed):
		EventBus.mine_floor_changed.disconnect(_on_changed)


func _on_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	if _service == null or _bar == null or _label == null:
		return
	_bar.max_value = CombatService.MAX_HEALTH
	_bar.value = int(_service.get("health"))
	_bar.visible = int(_service.get("health")) < CombatService.MAX_HEALTH \
		or bool(_service.get("in_mine"))
	var text := ""
	if bool(_service.get("in_mine")):
		text = "MINE F%d — %s" % [
			int(_service.get("floor")),
			"CLEARED" if bool(_service.get("cleared")) \
				else "Warden awake" if bool(_service.get("boss_spawned")) \
				else "%d left" % int(_service.get("enemies_remaining")),
		]
	_label.text = text
	_label.visible = not text.is_empty()


func _find_service() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return _search((loop as SceneTree).root)


func _search(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group(CombatService.SERVICE_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null
