class_name StoryService
extends Node
## The valley's main progression, driven by things the player actually does.
##
## A manager, not a rule-maker: chapters are data, and this node only watches
## the EventBus for the flags they require. It holds no quest ids or crop names.
## Reaching the ending publishes one event and then keeps going — free play is
## not a separate mode that needs a second save.

const SERVICE_GROUP := &"story_service"

var current_stage: StringName = &""
## Flags set by the world, keyed by name. Persisted with the save.
var flags: Dictionary = {}
var ending_reached: bool = false


static func find(start: Node) -> StoryService:
	if start == null:
		return null
	if start is StoryService:
		return start as StoryService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus != null:
		bus.quest_turned_in.connect(_on_quest_turned_in)
		bus.npc_friendship_changed.connect(_on_friendship)
		bus.npc_married.connect(_on_married)
		bus.crop_harvested.connect(_on_harvest)
		bus.cutscene_finished.connect(_on_cutscene)
		bus.cutscene_skipped.connect(_on_cutscene)
	_start()


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.quest_turned_in.is_connected(_on_quest_turned_in):
		bus.quest_turned_in.disconnect(_on_quest_turned_in)
	if bus.npc_friendship_changed.is_connected(_on_friendship):
		bus.npc_friendship_changed.disconnect(_on_friendship)
	if bus.npc_married.is_connected(_on_married):
		bus.npc_married.disconnect(_on_married)
	if bus.crop_harvested.is_connected(_on_harvest):
		bus.crop_harvested.disconnect(_on_harvest)
	if bus.cutscene_finished.is_connected(_on_cutscene):
		bus.cutscene_finished.disconnect(_on_cutscene)
	if bus.cutscene_skipped.is_connected(_on_cutscene):
		bus.cutscene_skipped.disconnect(_on_cutscene)


func set_flag(name: StringName, value: bool = true) -> void:
	if value:
		flags[name] = true
	else:
		flags.erase(name)
	_evaluate()


func _start() -> void:
	# The player begins in chapter one; opening it is not an event, so no
	# cutscene, reward or signal fires on service creation. Playing the intro is
	# `main.gd`'s `play_intro_cutscene` job, and its `cutscene_finished` flag is
	# what advances the story to chapter two.
	var first := StoryRegistry.first()
	current_stage = first.id if first != null else &""


## Opens the first chapter whose requirements are all met and which is later
## than the current one. Only one chapter advances per call, so a burst of
## events cannot skip a beat the player never saw.
func _evaluate() -> void:
	var chapters := StoryRegistry.all()
	if chapters.is_empty():
		return
	var index := -1
	for i: int in chapters.size():
		if chapters[i].id == current_stage:
			index = i
			break
	var next_index := index + 1
	if next_index >= chapters.size():
		return
	var candidate := chapters[next_index]
	for required: StringName in candidate.requires:
		if not bool(flags.get(required, false)):
			return
	_advance_to(candidate)


func _advance_to(chapter: StoryChapter) -> void:
	var previous := current_stage
	current_stage = chapter.id
	if chapter.reward_gold > 0:
		var player := _find_named(get_tree().get_root(), "PlayerState")
		if player != null and player.get("wallet") != null:
			var wallet: Object = player.get("wallet")
			wallet.call("set_gold", int(wallet.get("gold")) + chapter.reward_gold)
	if not chapter.cutscene_id.is_empty():
		var bus := _bus()
		if bus != null:
			bus.call("emit_signal", &"cutscene_requested", chapter.cutscene_id)
	var bus := _bus()
	if bus != null:
		bus.story_stage_changed.emit(previous, chapter.id)
		if chapter.is_ending and not ending_reached:
			ending_reached = true
			bus.story_ending_reached.emit(chapter.id)
	Log.info("Story", "Chapter -> %s (%s)" % [chapter.id, chapter.title])


func _on_quest_turned_in(quest_id: StringName, _giver: StringName) -> void:
	set_flag(StringName("quest_%s_done" % quest_id))


func _on_friendship(_npc_id: StringName, hearts: int, _tier: String) -> void:
	if hearts >= 4:
		set_flag(&"first_friend")


func _on_married(_npc_id: StringName) -> void:
	set_flag(&"married")


func _on_harvest(_tile: Vector2i, _crop: StringName, _amount: int) -> void:
	set_flag(&"first_harvest")


func _on_cutscene(id: StringName) -> void:
	set_flag(StringName("%s_seen" % id))


func to_dict() -> Dictionary:
	return {"current_stage": current_stage, "flags": flags.duplicate(),
		"ending_reached": ending_reached}


func from_dict(data: Dictionary) -> void:
	current_stage = StringName(str(data.get("current_stage", &"")))
	ending_reached = bool(data.get("ending_reached", false))
	var saved: Variant = data.get("flags", {})
	flags = {}
	if saved is Dictionary:
		for key: Variant in (saved as Dictionary):
			if bool((saved as Dictionary)[key]):
				flags[StringName(String(key))] = true


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
