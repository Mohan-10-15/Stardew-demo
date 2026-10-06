class_name NpcSchedule
extends Resource
## A villager's day: an ordered list of [NpcScheduleEntry] blocks.
##
## ## Ordering is priority
##
## [method entry_for] returns the **first** block that both applies and covers the
## current clock, so authoring order is the priority order. That is what lets a
## rain-only block sit above a general one without needing a priority field that nobody
## would set correctly. The cost is that order matters, so the blocks are sorted by
## [method from_minute] on write and [method is_valid] rejects overlaps: two blocks
## covering 09:00 is an authoring bug, and the fix is to order them, not to have the
## loader guess which the author meant.
##
## ## Nothing matches is normal, not an error
##
## A villager whose blocks are all season- or weather-gated has nothing to do on a day
## that misses every filter. [method entry_for] returns null and the caller sends them
## home. That is a valid state — it is what makes a rain-only routine read as unusual
## rather than as the day simply not having been written.

## The villager this schedule belongs to, as [member NpcData.id].
@export var npc_id: StringName = &""

@export var entries: Array[NpcScheduleEntry] = []


## The block this villager should be following at [param time], or null.
##
## Null means "nothing applies" and the caller falls back to home. See the class notes.
func entry_for(time: WorldTime) -> NpcScheduleEntry:
	for entry: NpcScheduleEntry in entries:
		if entry == null or not entry.is_valid():
			continue
		if not entry.applies_on(time):
			continue
		if not entry.covers(time):
			continue
		return entry
	return null


## Where this villager should be at [param time], as a location id, or empty.
##
## The convenience form most callers want. Takes the home id as a parameter rather than
## reading [member NpcData.home] so that this class stays free of any dependency on a
## particular villager's definition — a schedule is content, and content does not reach
## sideways into another resource.
func location_at(time: WorldTime, home_id: StringName = &"") -> StringName:
	var entry := entry_for(time)
	if entry != null:
		return entry.location
	return home_id


## Whether [param id] is named by any block.
func uses_location(id: StringName) -> bool:
	for entry: NpcScheduleEntry in entries:
		if entry != null and entry.location == id:
			return true
	return false


## Every location id this schedule can send the villager to, in block order.
func destinations() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: NpcScheduleEntry in entries:
		if entry != null and not out.has(entry.location):
			out.append(entry.location)
	return out


## Whether any block can ever apply on [param season].
func covers_season(season: int) -> bool:
	for entry: NpcScheduleEntry in entries:
		if entry == null or not entry.is_valid():
			continue
		if entry.seasons.is_empty() or entry.seasons.has(season):
			return true
	return false


## Whether any block can ever apply in [param weather].
func covers_weather(weather: int) -> bool:
	for entry: NpcScheduleEntry in entries:
		if entry == null or not entry.is_valid():
			continue
		if entry.weathers.is_empty() or entry.weathers.has(weather):
			return true
	return false


## Every block in the day, for logs.
func describe() -> String:
	var parts: Array[String] = []
	for entry: NpcScheduleEntry in entries:
		if entry == null:
			continue
		parts.append("%s %s (%s)" % [
			entry.describe_window(), entry.location, entry.activity,
		])
	return ", ".join(parts)


func is_valid() -> bool:
	if npc_id.is_empty():
		return false
	# A day with no blocks at all is not a schedule; it is an oversight, and it would
	# leave the villager permanently at home with nothing in any log to explain it.
	if entries.is_empty():
		return false
	var previous_start := -1
	var previous: NpcScheduleEntry = null
	for entry: NpcScheduleEntry in entries:
		if entry == null or not entry.is_valid():
			return false
		# Authoring order is priority order, so a block starting earlier than the one
		# before it is unsatisfiable: the earlier block already owns that ground.
		if entry.from_minute < previous_start:
			return false
		if previous != null and _overlaps(previous, entry):
			return false
		previous = entry
		previous_start = entry.from_minute
	return true


## Whether two same-day blocks claim the same clock, ignoring their date filters.
##
## Blocks that never apply on the same day cannot overlap in practice, so this is
## checked per pair against their filters where it can: two blocks for disjoint seasons
## are allowed to share a window.
func _overlaps(previous: NpcScheduleEntry, current: NpcScheduleEntry) -> bool:
	if not _seasons_compatible(previous, current):
		return false
	if not _weathers_compatible(previous, current):
		return false
	# Every minute of the playable day, not a sample. A ten-minute step would call two
	# blocks that both claim 12:30 non-overlapping, which is exactly the kind of
	# authoring mistake this is here to refuse.
	#
	# The bounds are HHMM, not hours: 6:00 AM is `600` and 2:00 AM is `2600`, so the
	# sweep is `600 -> 2700`. Writing `PASS_OUT_HOUR * 100` gives `2 * 100 = 200`, and
	# `range(600, 300)` is *empty* - the check silently passed every pair of blocks in
	# the game, which is how an unconditional block came to sit on top of a seasonal one
	# and win every day of the year.
	for minute: int in range(
		Clock.to_game_minutes(Clock.DAY_START_HOUR, 0),
		Clock.to_game_minutes(Clock.PASS_OUT_HOUR, 0) + 100,
	):
		if previous.covers_minute(minute) and current.covers_minute(minute):
			return true
	return false


func _seasons_compatible(a: NpcScheduleEntry, b: NpcScheduleEntry) -> bool:
	if a.seasons.is_empty() or b.seasons.is_empty():
		return true
	for season: int in a.seasons:
		if b.seasons.has(season):
			return true
	return false


func _weathers_compatible(a: NpcScheduleEntry, b: NpcScheduleEntry) -> bool:
	if a.weathers.is_empty() or b.weathers.is_empty():
		return true
	for weather: int in a.weathers:
		if b.weathers.has(weather):
			return true
	return false