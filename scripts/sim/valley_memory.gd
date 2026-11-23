class_name ValleyMemory
extends Node
## "A valley that remembers you" — a ledger of deeds set by real EventBus
## events. It never guesses and never invents: a deed is only recorded when the
## event that means it actually fired. The Mending recites the real ledger.

const SERVICE_GROUP := &"valley_memory"

## id -> triggering signal. Each id is one remembered deed.
const DEEDS: Dictionary = {
	&"first_harvest": &"crop_harvested",
	&"first_catch": &"fish_caught",
	&"first_ore": &"resource_collected",
	&"first_dish": &"dish_cooked",
	&"first_craft": &"craft_succeeded",
	&"first_gift": &"npc_gifted",
	&"first_festival": &"festival_attended",
	&"first_quest": &"quest_turned_in",
	&"first_build": &"building_placed",
	&"first_machine": &"machine_placed",
	&"first_ember": &"ember_returned",
	&"a_friendship": &"npc_friendship_changed",
	&"a_romance": &"romance_started",
	&"a_marriage": &"npc_married",
	&"a_talk": &"npc_talked",
	&"a_sale": &"item_sold",
	&"a_purchase": &"item_purchased",
	&"a_day": &"day_started",
	&"a_season": &"season_changed",
	&"a_gather": &"resource_depleted",
	&"a_quest_step": &"quest_progress_changed",
	&"a_tool_broke": &"tool_broken",
	&"a_weather": &"weather_changed",
	&"a_story_step": &"story_stage_changed",
	&"a_boss": &"boss_defeated",
	&"a_failure": &"farming_failed",
	&"a_refusal": &"gathering_failed",
}

var deeds: Dictionary = {}
var _connected: Dictionary = {}


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus == null:
		return
	for deed: StringName in DEEDS:
		var signal_name: StringName = DEEDS[deed]
		if not bus.has_signal(signal_name) or _connected.has(signal_name):
			continue
		# Bind the deed id: a shared callback cannot tell which signal fired,
		# and guessing from the arguments would misremember the player.
		var callback := _on_event.bind(deed)
		bus.connect(signal_name, callback)
		_connected[signal_name] = callback


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	for signal_name: StringName in _connected:
		if bus.has_signal(signal_name) \
				and bus.is_connected(signal_name, _connected[signal_name]):
			bus.disconnect(signal_name, _connected[signal_name])


func _on_event(_a = null, _b = null, _c = null, deed: StringName = &"") -> void:
	remember(deed)


func remember(deed: StringName) -> bool:
	if not DEEDS.has(deed) or bool(deeds.get(deed, false)):
		return false
	deeds[deed] = true
	return true


func has(deed: StringName) -> bool:
	return bool(deeds.get(deed, false))


func count() -> int:
	var n := 0
	for deed: StringName in DEEDS:
		if has(deed):
			n += 1
	return n


## Up to seven real deeds for the Mending, in a stable order.
func recite(limit: int = 7) -> Array[StringName]:
	var out: Array[StringName] = []
	for deed: StringName in DEEDS:
		if has(deed):
			out.append(deed)
			if out.size() >= mini(limit, 7):
				break
	return out


func to_dict() -> Dictionary:
	var out := {}
	for deed: StringName in DEEDS:
		if has(deed):
			out[String(deed)] = true
	return out


func from_dict(data: Dictionary) -> void:
	deeds.clear()
	for key: Variant in data:
		var deed := StringName(String(key))
		if DEEDS.has(deed) and bool(data[key]):
			deeds[deed] = true


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")
