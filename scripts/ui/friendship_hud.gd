extends CanvasLayer
## The relationship values the player has built, readable at a glance.
##
## ## Why it exists
##
## Group 14 put friendship in the save and in the events, and the prompt named a
## villager's tier when you aimed at them. Neither answers the question a player
## asks after a week of gifts: "how is everyone doing?" This panel is that answer —
## six rows, one per villager, each with a tier, a heart count and, once the
## relationship changes kind, a stage word.
##
## ## It reads the manager, it does not keep a second copy
##
## Every repaint asks [method NpcManager.npcs] for the current names and scores. A
## HUD holding its own tally would be a second answer to "how many hearts does
## Mira have", and the two would drift the moment one of them was fixed. The
## signals only say *when* to repaint; they carry no state worth caching.
##
## ## It never pauses the game
##
## Same bargain as [QuestTrackerHUD]: this is a readout, not a screen. It takes no
## input, so the valley keeps running while the player reads it.

## Group [NpcManager] registers under. A literal for the same reason the quest
## tracker and the interaction component use one: naming the manager here would
## close a `class_name` cycle the moment it wanted to find this HUD.
const NPC_SERVICE_GROUP := &"npc_service"

@onready var _rows: VBoxContainer = get_node_or_null(^"Panel/Column/Rows")

var _manager: Node = null
## What the rows say right now, so a test can read what the player reads.
var _lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	# Above the quest tracker (7) and below the interaction prompt (10): a
	# crosshair prompt always draws over the relationships.
	layer = 8
	_manager = _find_manager(get_tree().get_root())
	if _manager == null:
		Log.warn("FriendshipHUD", "No NpcManager; the relationship panel stays empty")
		return
	EventBus.npc_friendship_changed.connect(_on_friendship_changed)
	EventBus.romance_started.connect(_on_romance_changed)
	EventBus.npc_married.connect(_on_romance_changed)
	_refresh()


func _exit_tree() -> void:
	if EventBus.npc_friendship_changed.is_connected(_on_friendship_changed):
		EventBus.npc_friendship_changed.disconnect(_on_friendship_changed)
	if EventBus.romance_started.is_connected(_on_romance_changed):
		EventBus.romance_started.disconnect(_on_romance_changed)
	if EventBus.npc_married.is_connected(_on_romance_changed):
		EventBus.npc_married.disconnect(_on_romance_changed)


## The lines as drawn, for a test that wants the player's view rather than the
## friendship resource underneath it.
func row_texts() -> PackedStringArray:
	return _lines.duplicate()


func _on_friendship_changed(_npc_id: StringName, _hearts: int, _tier: String) -> void:
	_refresh()


func _on_romance_changed(_npc_id: StringName) -> void:
	_refresh()


## One row per villager, in the cast's stable id order.
##
## The panel owns the child labels: rebuilding them on each repaint means a
## villager added to the cast later gets a row without the scene being regenerated.
func _refresh() -> void:
	if _rows == null or _manager == null:
		return
	for child: Node in _rows.get_children():
		child.free()
	_lines = PackedStringArray()
	for npc: Npc in _manager.call("npcs"):
		if npc == null or npc.data == null:
			continue
		var friendship: Friendship = npc.friendship
		if friendship == null:
			continue
		var stage := friendship.romance_stage_name()
		var text := "%s  %s  %d/%d%s" % [
			npc.data.display_name, friendship.tier_name(), friendship.hearts(),
			Friendship.MAX_HEARTS, "  " + stage if not stage.is_empty() else "",
		]
		_lines.append(text)
		var label := Label.new()
		label.name = "Row_%s" % npc.data.id
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.88))
		_rows.add_child(label)


## Depth-first search for the manager. A group rather than a name so a test can
## stand up a second cast anywhere in the tree without this HUD caring where.
static func _find_manager(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group(NPC_SERVICE_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _find_manager(child)
		if found != null:
			return found
	return null
