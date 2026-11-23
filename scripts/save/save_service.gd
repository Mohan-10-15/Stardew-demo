class_name SaveService
extends Node
## The aggregate, versioned save — M16.
##
## Each service already knows how to round-trip its own state; what was missing
## was the one file that carries all of them together. This node owns the file
## format, the version number and the migration path, and calls each service's
## own `to_dict`/`from_dict` — it never reads a service's private fields.
##
## Writes are atomic: a temporary file is written first and renamed over the
## real save, so a crash mid-write cannot leave a half JSON file. A corrupt or
## older save degrades field by field rather than being thrown away.

const SERVICE_GROUP := &"save_service"
const SAVE_VERSION := 3
const SAVE_PATH := "user://hollowbrook.save"
const TEMP_PATH := "user://hollowbrook.save.tmp"

## Services, assigned by `main.gd` after they are spawned. Kept nullable so a
## content test can exercise the file format with only a subset attached.
var time_service: Node = null
var player_state: Node = null
var farm_service: Node = null
var npc_manager: Node = null
var quest_service: Node = null
var dialogue_service: Node = null
var cutscene_director: Node = null
var story_service: Node = null
var combat_service: Node = null
var festival_service: Node = null
var fishing_service: Node = null
var animal_service: Node = null
var machine_service: Node = null
var building_service: Node = null
var tutorial_service: Node = null
var collection_service: Node = null
var heartstone: Object = null
var valley_memory: Node = null
var voxel_service: Node = null
## The player body, saved separately from `player_state` (which owns the bag,
## purse and stamina but deliberately not a world coordinate).
var player: Node3D = null

var last_error: StringName = &""


static func find(start: Node) -> SaveService:
	if start == null:
		return null
	if start is SaveService:
		return start as SaveService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Removes the save so "New Game" starts genuinely fresh. A failed removal is
## reported, not swallowed: the title screen's Continue button must never offer
## a save the player thought they had deleted.
func delete_save() -> bool:
	last_error = &""
	if not has_save():
		return true
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if error != OK:
		last_error = &"cannot_delete"
		Log.warn("Save", "could not delete the old save")
		return false
	return true


## Snapshot every attached service into one versioned dictionary.
func to_dict() -> Dictionary:
	var data := {"version": SAVE_VERSION}
	if time_service != null and time_service.has_method("to_dict"):
		data["time"] = time_service.call("to_dict")
	if player_state != null and player_state.has_method("to_dict"):
		data["player"] = player_state.call("to_dict")
	if farm_service != null and farm_service.get("grid") != null:
		var grid: Object = farm_service.get("grid")
		if grid.has_method("to_dict"):
			data["farm"] = grid.call("to_dict")
	if npc_manager != null and npc_manager.has_method("to_dict"):
		data["npcs"] = npc_manager.call("to_dict")
	if quest_service != null and quest_service.has_method("to_dict"):
		data["quests"] = quest_service.call("to_dict")
	if dialogue_service != null and dialogue_service.has_method("to_dict"):
		data["dialogue"] = dialogue_service.call("to_dict")
	if player != null:
		var p := player.global_position
		data["player_position"] = {"x": p.x, "y": p.y, "z": p.z}
	if machine_service != null and machine_service.has_method("to_dict"):
		data["machines"] = machine_service.call("to_dict")
	if building_service != null and building_service.has_method("to_dict"):
		data["buildings"] = building_service.call("to_dict")
	if tutorial_service != null and tutorial_service.has_method("to_dict"):
		data["tutorial"] = tutorial_service.call("to_dict")
	if collection_service != null and collection_service.has_method("to_dict"):
		data["collections"] = collection_service.call("to_dict")
	if heartstone != null and heartstone.has_method("to_dict"):
		data["heartstone"] = heartstone.call("to_dict")
	if valley_memory != null and valley_memory.has_method("to_dict"):
		data["valley_memory"] = valley_memory.call("to_dict")
	if voxel_service != null and voxel_service.has_method("to_dict"):
		data["voxel"] = voxel_service.call("to_dict")
	if animal_service != null and animal_service.has_method("to_dict"):
		data["animals"] = animal_service.call("to_dict")
	if fishing_service != null and fishing_service.has_method("to_dict"):
		data["fishing"] = fishing_service.call("to_dict")
	if festival_service != null and festival_service.has_method("to_dict"):
		data["festival"] = festival_service.call("to_dict")
	if combat_service != null and combat_service.has_method("to_dict"):
		data["combat"] = combat_service.call("to_dict")
	if story_service != null and story_service.has_method("to_dict"):
		data["story"] = story_service.call("to_dict")
	if cutscene_director != null:
		var flags: Variant = cutscene_director.get("applied_flags")
		if flags is Dictionary:
			data["cutscene_flags"] = flags.duplicate()
	return data


## Restores each attached service from its own key. A missing or malformed key
## simply leaves that service alone, which is how a save from an older build
## degrades gracefully instead of being rejected whole.
func from_dict(data: Dictionary) -> void:
	last_error = &""
	var payload := migrate(data)
	var sections := {
		"time": time_service, "player": player_state, "quests": quest_service,
		"dialogue": dialogue_service,
	}
	for key: String in sections:
		var service: Node = sections[key]
		if service != null and service.has_method("from_dict") \
				and payload.get(key) is Dictionary:
			service.call("from_dict", _stringify_keys(payload[key]))
	if farm_service != null and farm_service.get("grid") != null:
		var grid: Object = farm_service.get("grid")
		if grid.has_method("from_dict") and payload.get("farm") is Dictionary:
			grid.call("from_dict", payload["farm"])
	if npc_manager != null and npc_manager.has_method("from_dict") \
			and payload.get("npcs") is Dictionary:
		npc_manager.call("from_dict", _stringify_keys(payload["npcs"]))
	if machine_service != null and machine_service.has_method("from_dict") \
			and payload.get("machines") is Dictionary:
		machine_service.call("from_dict", payload["machines"])
	if building_service != null and building_service.has_method("from_dict") \
			and payload.get("buildings") is Dictionary:
		building_service.call("from_dict", payload["buildings"])
	if tutorial_service != null and tutorial_service.has_method("from_dict") \
			and payload.get("tutorial") is Dictionary:
		tutorial_service.call("from_dict", payload["tutorial"])
	if collection_service != null and collection_service.has_method("from_dict") \
			and payload.get("collections") is Dictionary:
		collection_service.call("from_dict", payload["collections"])
	if heartstone != null and heartstone.has_method("from_dict") \
			and payload.get("heartstone") is Dictionary:
		heartstone.call("from_dict", payload["heartstone"])
	if valley_memory != null and valley_memory.has_method("from_dict") \
			and payload.get("valley_memory") is Dictionary:
		valley_memory.call("from_dict", payload["valley_memory"])
	if voxel_service != null and voxel_service.has_method("from_dict") \
			and payload.get("voxel") is Dictionary:
		voxel_service.call("from_dict", payload["voxel"])
	if animal_service != null and animal_service.has_method("from_dict") \
			and payload.get("animals") is Dictionary:
		animal_service.call("from_dict", payload["animals"])
	if fishing_service != null and fishing_service.has_method("from_dict") \
			and payload.get("fishing") is Dictionary:
		fishing_service.call("from_dict", payload["fishing"])
	if festival_service != null and festival_service.has_method("from_dict") \
			and payload.get("festival") is Dictionary:
		festival_service.call("from_dict", payload["festival"])
	if combat_service != null and combat_service.has_method("from_dict") \
			and payload.get("combat") is Dictionary:
		combat_service.call("from_dict", payload["combat"])
	if story_service != null and story_service.has_method("from_dict") \
			and payload.get("story") is Dictionary:
		story_service.call("from_dict", _stringify_keys(payload["story"]))
	if cutscene_director != null and payload.get("cutscene_flags") is Dictionary:
		cutscene_director.set("applied_flags", (payload["cutscene_flags"] as Dictionary).duplicate())


## Migrates an older payload to the current shape. Version 1 had no dialogue
## or cutscene flags; version 2 had dialogue but no cutscene flags. Unknown
## future versions are refused rather than guessed at.
func migrate(data: Dictionary) -> Dictionary:
	var payload := data.duplicate(true)
	var version := int(payload.get("version", 0))
	if version > SAVE_VERSION:
		last_error = &"future_version"
		return payload
	if version < 1:
		payload["version"] = 1
	if version < 2 and not payload.has("dialogue"):
		payload["dialogue"] = {}
	if version < 3 and not payload.has("cutscene_flags"):
		payload["cutscene_flags"] = {}
	payload["version"] = SAVE_VERSION
	return payload


## JSON only understands strings, numbers, bools, arrays and objects. Several
## services key their dictionaries by StringName and store Vector2/Vector3, so
## the payload is normalised on the way out rather than trusting the writer.
static func _json_safe(value: Variant) -> Variant:
	if value is StringName or value is String:
		return String(value)
	if value is Vector2:
		return {"x": (value as Vector2).x, "y": (value as Vector2).y}
	if value is Vector3:
		var v := value as Vector3
		return {"x": v.x, "y": v.y, "z": v.z}
	if value is Dictionary:
		var out := {}
		for key: Variant in (value as Dictionary):
			out[String(key)] = _json_safe((value as Dictionary)[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in (value as Array):
			out.append(_json_safe(item))
		return out
	return value


## JSON object keys come back as Strings; most id-keyed sections expect
## StringName keys, so convert the outer layer before handing it to a service.
static func _stringify_keys(data: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in data:
		var value: Variant = data[key]
		if value is Dictionary:
			value = _stringify_keys(value)
		out[StringName(String(key))] = value
	return out


func save_game(path: String = SAVE_PATH) -> bool:
	last_error = &""
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		last_error = &"cannot_write"
		EventBus.game_save_failed.emit(last_error)
		return false
	var payload := to_dict()
	var json := JSON.stringify(_json_safe(payload), "", false)
	file.store_string(json)
	file.flush()
	file.close()
	# Atomic rename: the real save is replaced only once the temp file is whole.
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(path)
	)
	if error != OK:
		last_error = &"cannot_commit"
		EventBus.game_save_failed.emit(last_error)
		return false
	EventBus.game_saved.emit(path)
	return true


func load_game(path: String = SAVE_PATH) -> bool:
	last_error = &""
	if not FileAccess.file_exists(path):
		last_error = &"no_save"
		EventBus.game_load_failed.emit(last_error)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = &"cannot_read"
		EventBus.game_load_failed.emit(last_error)
		return false
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		Log.warn("Save", "JSON parse failed at line %d: %s" % [
			parser.get_error_line(), parser.get_error_message(),
		])
		last_error = &"corrupt"
		EventBus.game_load_failed.emit(last_error)
		return false
	var parsed: Variant = parser.get_data()
	if not parsed is Dictionary:
		last_error = &"corrupt"
		EventBus.game_load_failed.emit(last_error)
		return false
	var payload: Dictionary = parsed
	if int(payload.get("version", 0)) > SAVE_VERSION:
		last_error = &"future_version"
		EventBus.game_load_failed.emit(last_error)
		return false
	from_dict(payload)
	if player != null and payload.get("player_position") is Dictionary:
		var pos: Dictionary = payload["player_position"]
		player.global_position = Vector3(
			float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0))
		)
	EventBus.game_loaded.emit(path)
	return true
