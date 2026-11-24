class_name CutsceneValidator
extends RefCounted
## W7.2: validate authored cutscenes before they can trap a player. Pure, so
## both a headless tool and a test suite can call the same checks.

const KINDS: Array[StringName] = [
	&"wait", &"dialogue", &"camera_move", &"fade", &"letterbox", &"flag",
	&"play_sound", &"play_music", &"title_card", &"screen_flash",
	&"actor_anim", &"actor_emote", &"actor_move", &"camera_cut",
	&"particle", &"choice", &"set_time", &"set_weather", &"give_item",
	&"story_advance",
]

static var _registry_script := "res://scripts/cutscenes/cutscene_registry.gd"


static func validate() -> Dictionary:
	var errors: Array[String] = []
	var total_duration := 0.0
	var real := 0
	var script := load(_registry_script) as GDScript
	var all: Array[CutscenePlayer] = script.call("all") if script != null else []
	for cutscene: CutscenePlayer in all:
		if cutscene.id == &"" or cutscene.events.is_empty():
			errors.append("%s is empty" % cutscene.id)
			continue
		if not String(cutscene.id).begins_with("test_"):
			real += 1
		var duration := 0.0
		for event: CutsceneEvent in cutscene.events:
			if not KINDS.has(event.kind):
				errors.append("%s uses unknown kind %s" % [cutscene.id, event.kind])
			duration += event.seconds
			if event.kind == &"flag" and String(event.params.get("name", &"")).is_empty():
				errors.append("%s has an unnamed flag" % cutscene.id)
			if event.kind == &"actor_anim" or event.kind == &"actor_emote" \
					or event.kind == &"actor_move":
				var npc_id := StringName(event.params.get("npc", &""))
				if npc_id != &"" and not NpcRegistry.has_npc(npc_id):
					errors.append("%s names unknown npc %s" % [cutscene.id, npc_id])
			if event.kind == &"play_music":
				var cue_id := StringName(event.params.get("id", &""))
				if cue_id != &"" and not ResourceLoader.exists(
						"res://resources/audio/cues/%s.tres" % cue_id):
					errors.append("%s names unknown cue %s" % [cutscene.id, cue_id])
		if duration > 90.0:
			errors.append("%s runs %.1f s (limit 90)" % [cutscene.id, duration])
		total_duration += duration
	if real < 14:
		errors.append("only %d authored cutscenes" % real)
	return {"ok": errors.is_empty(), "errors": errors, "real": real,
		"total": all.size(), "duration": total_duration}
