extends CanvasLayer
## A quiet line naming the current story chapter. It listens; it never decides
## what the story should do.

const STORY_GROUP := &"story_service"

@onready var _label: Label = get_node_or_null(^"Panel/Chapter") as Label


func _ready() -> void:
	layer = 6
	EventBus.story_stage_changed.connect(_on_stage)
	_refresh()


func _exit_tree() -> void:
	if EventBus.story_stage_changed.is_connected(_on_stage):
		EventBus.story_stage_changed.disconnect(_on_stage)


func _on_stage(_previous: StringName, _current: StringName) -> void:
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var service := _find_story()
	if service == null:
		_label.text = ""
		return
	var stage := StringName(str(service.get("current_stage")))
	var chapter := StoryRegistry.chapter_for(stage)
	var number := String(stage).substr(2, 2) if String(stage).begins_with("ch") \
		else String(stage)
	_label.text = ("Chapter %s — %s" % [number, chapter.title]) \
		if chapter != null else ""


func _find_story() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return _search((loop as SceneTree).root)


func _search(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group(STORY_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null
