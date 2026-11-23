extends CanvasLayer
## The journal: Quests, Collections, Villagers and Story in one generated
## panel. Opens on J (or with a pad through the menu), never traps input.

const DIR_TABS := ["Quests", "Collections", "Villagers", "Story"]

@onready var _tabs: TabContainer = get_node_or_null(^"Panel/Tabs") as TabContainer
var _open := false


func _ready() -> void:
	layer = 15
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := _bus()
	if bus != null and not bus.input_device_changed.is_connected(_on_device):
		bus.input_device_changed.connect(_on_device)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(InputActions.JOURNAL):
		if _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	visible = true
	_refresh()


func close() -> void:
	_open = false
	visible = false


func _on_device(_device: int) -> void:
	if _open:
		_refresh()


func _clear(tab: Control) -> void:
	var list := tab.get_node_or_null(^"List") as Control
	if list == null:
		return
	for child: Node in list.get_children():
		child.free()


func _label(parent: Node, text: String, size: int = 14) -> void:
	var target: Node = parent.get_node_or_null(^"List") if parent is ScrollContainer else parent
	if target == null:
		target = parent
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	target.add_child(label)


func _refresh() -> void:
	if _tabs == null:
		return
	var tabs: Array[Control] = []
	for i: int in range(_tabs.get_tab_count()):
		var tab := _tabs.get_tab_control(i)
		_clear(tab)
		tabs.append(tab)
	if tabs.size() >= 4:
		_fill_quests(tabs[0])
		_fill_collections(tabs[1])
		_fill_villagers(tabs[2])
		_fill_story(tabs[3])


func _fill_quests(tab: Control) -> void:
	if tab == null:
		return
	var service := _find_group(get_tree().root, &"quest_service")
	if service == null:
		_label(tab, "No quest journal available.", 15)
		return
	var quests: Array[QuestData] = service.call("active_quests")
	if quests.is_empty():
		_label(tab, "No active jobs. Talk to a villager.", 15)
	else:
		for quest: QuestData in quests:
			_label(tab, "%s — %s" % [quest.title, String(quest.id)], 15)


func _fill_collections(tab: Control) -> void:
	if tab == null:
		return
	var service := _find_group(get_tree().root, &"collection_service")
	if service == null:
		_label(tab, "No collections available.", 15)
		return
	for data: CollectionData in service.collections:
		var pct: float = float(service.call("progress", data.id))
		_label(tab, "%s — %d%%  %s" % [
			data.display_name, roundi(pct * 100.0),
			"Ember home" if pct >= 0.999 else "",
		], 15)


func _fill_villagers(tab: Control) -> void:
	if tab == null:
		return
	var manager := _find_group(get_tree().root, &"npc_manager")
	if manager == null:
		_label(tab, "No villagers available.", 15)
		return
	for npc: Node in manager.call("npcs"):
		if npc == null or npc.get("data") == null:
			continue
		var data: NpcData = npc.get("data")
		var friendship: Friendship = npc.get("friendship")
		_label(tab, "%s — %s" % [
			data.display_name,
			friendship.tier_name() if friendship != null else "Stranger",
		], 14)


func _fill_story(tab: Control) -> void:
	if tab == null:
		return
	var service := _find_group(get_tree().root, &"story_service")
	if service != null:
		_label(tab, "Chapter: %s" % str(service.get("current_stage")), 16)
	var heart := _find_heartstone(get_tree().root)
	if heart != null:
		_label(tab, "Embers: %d / 6" % heart.count(), 15)
	_label(tab, "Cutscenes you have seen can be replayed from the story log.", 13)


func _find_heartstone(node: Node) -> HeartstoneState:
	if node == null:
		return null
	if node.get("heartstone") != null:
		return node.get("heartstone") as HeartstoneState
	for child: Node in node.get_children():
		var found := _find_heartstone(child)
		if found != null:
			return found
	return null


func _find_group(node: Node, group: StringName) -> Node:
	if node == null:
		return null
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _find_group(child, group)
		if found != null:
			return found
	return null


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
