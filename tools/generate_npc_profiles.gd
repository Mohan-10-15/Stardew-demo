extends SceneTree
## Links each shipped NpcData to its CharacterProfile (W4.2). Run after
## generate_character_profiles.gd. Existing ids and all other fields are kept.

const NPC_DIR := "res://resources/npc/npcs/"
const PROFILE_DIR := "res://resources/npc/profiles/"


func _initialize() -> void:
	var dir := DirAccess.open(NPC_DIR)
	if dir == null:
		printerr("[generate_npc_profiles] no npc directory")
		quit(1)
		return
	var linked := 0
	for entry: String in dir.get_files():
		if not entry.ends_with(".tres"):
			continue
		var npc := ResourceLoader.load(NPC_DIR + entry) as NpcData
		if npc == null:
			continue
		var profile := ResourceLoader.load(
			PROFILE_DIR + String(npc.id) + ".tres") as CharacterProfile
		if profile == null:
			printerr("[generate_npc_profiles] no profile for %s" % npc.id)
			continue
		npc.profile = profile
		if ResourceSaver.save(npc, NPC_DIR + entry) != OK:
			printerr("[generate_npc_profiles] failed for %s" % npc.id)
			continue
		linked += 1
	print("[generate_npc_profiles] linked %d cast profiles" % linked)
	quit(0)
