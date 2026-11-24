extends TestSuite
## W6.5: layered ambience selection is pure and every selected id exists in
## the audio registry.

func get_cases() -> Array[StringName]:
	return [&"bed_and_weather_layers_are_distinct", &"all_ambience_ids_exist"]


func _run(case: StringName) -> Dictionary:
	match case:
		&"bed_and_weather_layers_are_distinct":
			var mine := AmbienceDirector.bed_for({"location": "deep_mines"})
			var pond := AmbienceDirector.bed_for({"location": "pond_shore"})
			var night := AmbienceDirector.bed_for({"hour": 22})
			var rain := AmbienceDirector.weather_for({"weather": 1})
			var storm := AmbienceDirector.weather_for({"weather": 2})
			var snow := AmbienceDirector.weather_for({"weather": 3})
			if mine != &"cave_loop" or pond != &"pond_loop" or night != &"crickets_loop":
				return fail(case, "beds: %s / %s / %s" % [mine, pond, night])
			if rain == storm or snow == rain:
				return fail(case, "weather layers not distinct: %s %s %s" % [
					rain, storm, snow,
				])
			return succeeded(case, "location bed + weather layer distinct")
		&"all_ambience_ids_exist":
			var ids: Array[StringName] = [
				&"birds_loop", &"crickets_loop", &"pond_loop", &"cave_loop",
				&"storm_loop", &"snow_loop", &"bird_chirp", &"cricket_chirp",
				&"cave_drip", &"footstep_dirt", &"footstep_grass_b", &"footstep_wood_b",
			]
			for id: StringName in ids:
				if AudioRegistry.sound_for(id) == null:
					return fail(case, "%s has no definition" % id)
			return succeeded(case, "%d new ambience/footstep sounds authored" % ids.size())
	return fail(case, "no case implementation for %s" % case)
