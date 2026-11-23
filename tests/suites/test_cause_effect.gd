extends TestSuite
## W2.8: the world obeys visible rules. Each rule is tested at the data /
## predicate level its system actually uses, not asserted in a comment.

func get_cases() -> Array[StringName]:
	return [
		&"crops_only_grow_in_their_seasons",
		&"fish_are_gated_by_season_weather_and_hour",
		&"every_festival_defers_the_whole_cast",
		&"schedules_carry_season_and_weather_rules",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"crops_only_grow_in_their_seasons":
			var crops := CropRegistry.all_crops()
			var seasonal := 0
			for crop: CropData in crops:
				if crop.seasons.is_empty():
					continue
				seasonal += 1
				for season: int in range(4):
					var should := crop.seasons.has(season)
					if crop.grows_in(season) != should:
						return fail(case, "%s grows_in(%d) disagrees with its data" % [
							crop.id, season,
						])
			if seasonal < 4:
				return fail(case, "only %d seasonal crops" % seasonal)
			return succeeded(case, "%d seasonal crops respect their seasons" % seasonal)
		&"fish_are_gated_by_season_weather_and_hour":
			var fish: Array[FishData] = []
			var fish_dir := DirAccess.open("res://resources/fishing/fish")
			if fish_dir != null:
				for entry: String in fish_dir.get_files():
					if entry.ends_with(".tres"):
						var data := ResourceLoader.load(
							"res://resources/fishing/fish/" + entry) as FishData
						if data != null:
							fish.append(data)
			var gated := 0
			for data: FishData in fish:
				if data.seasons.is_empty() and data.weathers.is_empty() \
						and data.hour_from == 0 and data.hour_to == 23:
					continue
				gated += 1
				# A night fish legitimately wraps midnight (hour_from > hour_to).
				if data.hour_from < 0 or data.hour_to > 23:
					return fail(case, "%s has out-of-range hours" % data.id)
			if gated < 4:
				return fail(case, "only %d gated fish" % gated)
			return succeeded(case, "%d fish carry season/weather/hour gates" % gated)
		&"every_festival_defers_the_whole_cast":
			var festivals := FestivalRegistry.all()
			var npcs := NpcRegistry.all_npcs()
			for festival: FestivalData in festivals:
				for npc: NpcData in npcs:
					var path := "res://resources/npc/schedules/%s_festival.tres" % npc.id
					var schedule := ResourceLoader.load(path) as NpcSchedule
					if schedule == null:
						return fail(case, "%s has no gathering day for %s" % [
							festival.id, npc.id,
						])
			return succeeded(case, "%d festivals defer all %d villagers" % [
				festivals.size(), npcs.size(),
			])
		&"schedules_carry_season_and_weather_rules":
			var with_season := 0
			var with_weather := 0
			var dir := DirAccess.open("res://resources/npc/schedules")
			if dir == null:
				return fail(case, "no schedules")
			for entry: String in dir.get_files():
				if not entry.ends_with(".tres") or entry.contains("_festival") \
						or entry.contains("_spouse"):
					continue
				var schedule := ResourceLoader.load(
					"res://resources/npc/schedules/" + entry) as NpcSchedule
				if schedule == null:
					continue
				for item: NpcScheduleEntry in schedule.entries:
					if not item.seasons.is_empty():
						with_season += 1
					if not item.weathers.is_empty():
						with_weather += 1
			if with_season < 5 or with_weather < 5:
				return fail(case, "season=%d weather=%d schedule entries" % [
					with_season, with_weather,
				])
			return succeeded(case, "season=%d weather=%d entries" % [with_season, with_weather])
	return fail(case, "no case implementation for %s" % case)
