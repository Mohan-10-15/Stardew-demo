class_name WorldLogicValidator
extends RefCounted
## Pure content-graph validation. No scene dependency, so it runs headlessly
## from both tools/validate_world_logic.gd and a test suite. A dangling id here
## is a bug in data, not in a service — fixing the data is the fix.

static func validate() -> Dictionary:
	var errors: Array[String] = []
	var nodes := 0
	var edges := 0

	# Collections -> items / npcs / embers / unlocks
	var dir := DirAccess.open("res://resources/collections")
	if dir == null:
		errors.append("no collection directory")
	else:
		for entry: String in dir.get_files():
			if not entry.ends_with(".tres"):
				continue
			var data := ResourceLoader.load("res://resources/collections/" + entry) as CollectionData
			if data == null or not data.is_valid():
				errors.append("invalid collection %s" % entry)
				continue
			nodes += 1
			if not HeartstoneState.EMBERS.has(data.ember):
				errors.append("%s names unknown ember %s" % [data.id, data.ember])
			for item_id: StringName in data.entries:
				edges += 1
				if data.kind == "npc":
					if not NpcRegistry.has_npc(item_id):
						errors.append("%s names unknown npc %s" % [data.id, item_id])
				elif not _is_known_source(item_id):
					errors.append("%s names unknown item %s" % [data.id, item_id])
			for tier: CollectionTier in data.tiers:
				edges += 1
				if String(tier.unlock).is_empty():
					errors.append("%s has an empty tier unlock" % data.id)

	# Schedules -> locations and npcs
	for schedule: NpcSchedule in _all_schedules():
		nodes += 1
		# Festival and spouse schedules are variants keyed by a synthetic id
		# (e.g. mira_festival); the npc is the part before the suffix.
		var owner := String(schedule.npc_id)
		if owner.ends_with("_festival"):
			owner = owner.trim_suffix("_festival")
		elif owner.ends_with("_spouse"):
			owner = owner.trim_suffix("_spouse")
		if not NpcRegistry.has_npc(StringName(owner)):
			errors.append("schedule names unknown npc %s" % schedule.npc_id)
		for entry: NpcScheduleEntry in schedule.entries:
			edges += 1
			if not LocationRegistry.has_location(entry.location):
				errors.append("%s schedules unknown location %s" % [
					schedule.npc_id, entry.location,
				])

	# Quests -> giver / objective / reward ids
	for quest: QuestData in _all_quests():
		nodes += 1
		if not NpcRegistry.has_npc(quest.giver):
			errors.append("quest %s has unknown giver %s" % [quest.id, quest.giver])
		if quest.reward != null and not String(quest.reward.item_id).is_empty():
			edges += 1
			if not ItemRegistry.has_item(quest.reward.item_id):
				errors.append("quest %s rewards unknown item %s" % [
					quest.id, quest.reward.item_id,
				])

	return {"ok": errors.is_empty(), "errors": errors, "nodes": nodes, "edges": edges}


## A collection entry may be a real item, a crop, a craft output or a dish —
## the Table collection is explicitly "crafted + cooked", so recipe ids are
## valid sources even though they have no ItemDefinition of their own.
static func _is_known_source(id: StringName) -> bool:
	if ItemRegistry.has_item(id) or CropRegistry.get_crop(id) != null:
		return true
	for recipe: Recipe in CraftingService.all_recipes():
		if recipe.id == id or recipe.output_id == id:
			return true
	for recipe: CookingRecipe in CookingService.all_recipes():
		if recipe.id == id or recipe.output_id == id:
			return true
	return false


static func _all_schedules() -> Array[NpcSchedule]:
	var out: Array[NpcSchedule] = []
	var dir := DirAccess.open("res://resources/npc/schedules")
	if dir == null:
		return out
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var schedule := ResourceLoader.load(
				"res://resources/npc/schedules/" + entry) as NpcSchedule
			if schedule != null:
				out.append(schedule)
	return out


static func _all_quests() -> Array[QuestData]:
	var out: Array[QuestData] = []
	var dir := DirAccess.open("res://resources/quests")
	if dir == null:
		return out
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var quest := ResourceLoader.load("res://resources/quests/" + entry) as QuestData
			if quest != null:
				out.append(quest)
	return out
