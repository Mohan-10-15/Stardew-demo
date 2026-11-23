extends TestSuite
## W4.1–W4.4: twelve distinct anime-styled profiles, linked to the cast, with
## every schedule activity mapped to a real clip from the shared rig library.

func get_cases() -> Array[StringName]:
	return [
		&"thirteen_valid_distinct_profiles",
		&"every_villager_has_a_profile",
		&"every_schedule_activity_maps_to_a_clip",
		&"mapped_clips_exist_in_the_kaykit_library",
	]


func _profiles() -> Array[CharacterProfile]:
	var out: Array[CharacterProfile] = []
	var dir := DirAccess.open("res://resources/npc/profiles")
	if dir == null:
		return out
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var profile := ResourceLoader.load(
				"res://resources/npc/profiles/" + entry) as CharacterProfile
			if profile != null:
				out.append(profile)
	return out


func _run(case: StringName) -> Dictionary:
	match case:
		&"thirteen_valid_distinct_profiles":
			var profiles := _profiles()
			if profiles.size() < 13:
				return fail(case, "only %d profiles" % profiles.size())
			var signatures := {}
			var builds := {}
			for profile: CharacterProfile in profiles:
				if not profile.is_valid():
					return fail(case, "%s is invalid" % profile.id)
				if signatures.has(profile.signature()):
					return fail(case, "duplicate signature: %s" % profile.signature())
				signatures[profile.signature()] = true
				builds[profile.build] = true
			if builds.size() < 5:
				return fail(case, "only %d distinct body builds" % builds.size())
			return succeeded(case, "%d distinct profiles, %d builds" % [
				profiles.size(), builds.size(),
			])
		&"every_villager_has_a_profile":
			var dir := DirAccess.open("res://resources/npc/npcs")
			if dir == null:
				return fail(case, "no npc directory")
			var linked := 0
			for entry: String in dir.get_files():
				if not entry.ends_with(".tres"):
					continue
				var npc := ResourceLoader.load("res://resources/npc/npcs/" + entry) as NpcData
				if npc != null and npc.profile != null:
					linked += 1
			if linked < 12:
				return fail(case, "only %d of 12 villagers linked" % linked)
			return succeeded(case, "%d villagers linked" % linked)
		&"every_schedule_activity_maps_to_a_clip":
			var checked := 0
			var dir := DirAccess.open("res://resources/npc/schedules")
			if dir == null:
				return fail(case, "no schedules")
			for entry: String in dir.get_files():
				if not entry.ends_with(".tres"):
					continue
				var schedule := ResourceLoader.load(
					"res://resources/npc/schedules/" + entry) as NpcSchedule
				if schedule == null:
					continue
				for item: NpcScheduleEntry in schedule.entries:
					checked += 1
					if NpcAnimator.clip_for(item.activity) == &"":
						return fail(case, "%s has no clip" % item.activity)
			return succeeded(case, "%d schedule entries map to clips" % checked)
		&"mapped_clips_exist_in_the_kaykit_library":
			# The 76 names come from tools/probe_rig.gd on the shipped FBXs.
			var library: Array[StringName] = [
				&"Idle", &"Unarmed_Idle", &"Walking_A", &"Walking_B", &"Interact",
				&"Use_Item", &"Sit_Chair_Idle", &"Lie_Idle", &"PickUp", &"Cheer",
				&"Blocking", &"Running_A", &"Running_B",
			]
			for activity: StringName in NpcAnimator.ACTIVITY_CLIPS:
				var clip := NpcAnimator.clip_for(activity)
				if not library.has(clip):
					return fail(case, "%s maps to unknown clip %s" % [activity, clip])
			return succeeded(case, "%d activity mappings valid" % NpcAnimator.ACTIVITY_CLIPS.size())
	return fail(case, "no case implementation for %s" % case)
