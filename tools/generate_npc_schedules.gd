extends SceneTree
## Headless tool: writes the named-location and NPC schedule resources.
##
## Writes `resources/world/locations/*.tres` and `resources/npc/schedules/*.tres`.
## Run `generate_npc_data.gd` first: the cottage locations take their position from
## [member NpcData.home], so the two generators have an order and this is the second
## half of it.
##
## Run it with:
## [codeblock]
## & "tools/Godot_v4.5-stable_win64_console.exe" --headless --path . \
##     --script res://tools/generate_npc_schedules.gd
## [/codeblock]

const LOCATION_DIR := "res://resources/world/locations/"
const SCHEDULE_DIR := "res://resources/npc/schedules/"
const NPC_DIR := "res://resources/npc/npcs/"

## ## The shared places
##
## Only the places a schedule sends a villager to that is not their own doorstep. The
## cottages come from the villager definitions themselves.
##
## Every coordinate here was chosen against the world's own collider table and is
## commented with what it is standing clear of. Two of them are load-bearing in a way
## that is easy to undo by accident:
##
## - [code]general_store[/code] and [code]kitchen_garden[/code] are outside the farm
##   fence, because `test_world_geometry.gd` asserts the fence perimeter is closed. The
##   farm plot is therefore not a destination. That is a deliberate design decision, not
##   a gap to be filled by punching a hole in the fence later.
## - [code]pond_shore[/code] is on the basin's inner slope, where the terrain is about
##   5 cm below the rim: inside the walkable band, but not in the water.
const SHARED_PLACES: Array[Dictionary] = [
	{
		"id": &"village_well", "display_name": "The Village Well",
		"kind": LocationData.KIND_SOCIAL, "position": Vector2(30.0, 6.4),
		# 2.4 m from the well's axis, clear of its 1.1 m radius, looking back at it.
		"facing": 0.0,
	},
	{
		"id": &"village_square", "display_name": "The Village Square",
		"kind": LocationData.KIND_SOCIAL, "position": Vector2(38.0, 8.0),
		# The centre of [constant WorldBuilder.REGION_VILLAGE], which the scatter rules
		# guarantee is clear of every tree, rock and bush.
		"facing": LocationData.FACING_UNSET,
	},
	{
		"id": &"village_orchard", "display_name": "The Orchard",
		"kind": LocationData.KIND_NATURE, "position": Vector2(38.0, 18.0),
		# Inside the village's clear disc, 2 m north-east of house 4's collider.
		"facing": LocationData.FACING_UNSET,
	},
	{
		"id": &"general_store", "display_name": "The General Store",
		"kind": LocationData.KIND_WORK, "position": Vector2(14.5, -18.4),
		# 1.2 m in front of the stall counter, and 3.5 m east of the farm fence rail.
		"facing": 0.0,
	},
	{
		"id": &"kitchen_garden", "display_name": "Mira's Kitchen Garden",
		"kind": LocationData.KIND_WORK, "position": Vector2(18.5, -24.0),
		# Behind the shop, east of the fence.
		"facing": LocationData.FACING_UNSET,
	},
	{
		"id": &"pond_shore", "display_name": "The Pond Shore",
		"kind": LocationData.KIND_NATURE, "position": Vector2(-14.0, 28.5),
		# 15.5 m from the pond centre, just inside the 17 m rim: the slope, not the water.
		"facing": PI,
	},
	{
		"id": &"forest_edge", "display_name": "The Forest Edge",
		"kind": LocationData.KIND_NATURE, "position": Vector2(-30.0, 18.0),
		# Reachable from the village without crossing the farm fence, which is why it is
		# here and not further west.
		"facing": LocationData.FACING_UNSET,
	},
]

## ## The days
##
## Times are [method Clock.to_game_minutes]: `800` is 08:00, `2400` is midnight, and a
## window ending [constant NpcScheduleEntry.OPEN_END] runs to 2:00 AM.
##
## Every schedule has at least one block that is gated on the weather or the season, so
## the day visibly differs from day to day. That is the point of pulling the weather roll
## forward: without it a schedule can only ever say "at this hour", and six villagers
## walking the same loop forever is what the group is meant to stop.
const SCHEDULES: Array[Dictionary] = [
	{
		"id": &"mira",
		"blocks": [
			{"at": [600, 800], "where": &"mira_cottage", "doing": "waking"},
			{"at": [800, 1200], "where": &"kitchen_garden", "doing": "tending the beds",
				"dry": true},
			{"at": [800, 1200], "where": &"village_square", "doing": "sheltering",
				"wet": true},
			{"at": [1200, 1700], "where": &"village_well", "doing": "gossip"},
			{"at": [1700, 2100], "where": &"general_store", "doing": "errands"},
			{"at": [2100, NpcScheduleEntry.OPEN_END], "where": &"mira_cottage", "doing": "sleeping"},
		],
	},
	{
		"id": &"bram",
		"blocks": [
			{"at": [600, 700], "where": &"bram_cottage", "doing": "waking"},
			{"at": [700, 1200], "where": &"forest_edge", "doing": "hauling timber",
				"thawed": true},
			{"at": [700, 1200], "where": &"village_square", "doing": "sorting nails",
				"winter": true},
			{"at": [1200, 1300], "where": &"village_well", "doing": "washing up"},
			{"at": [1300, 1700], "where": &"village_square", "doing": "mending"},
			{"at": [1700, 2100], "where": &"general_store", "doing": "buying nails"},
			{"at": [2100, NpcScheduleEntry.OPEN_END], "where": &"bram_cottage", "doing": "sleeping"},
		],
	},
	{
		"id": &"odette",
		"blocks": [
			{"at": [600, 900], "where": &"odette_cottage", "doing": "reading, slowly"},
			{"at": [900, 1600], "where": &"pond_shore", "doing": "reading the water",
				"calm": true},
			{"at": [900, 1600], "where": &"odette_cottage", "doing": "waiting it out",
				"wild": true},
			{"at": [1600, 1800], "where": &"village_well", "doing": "talking"},
			{"at": [1800, 2100], "where": &"general_store", "doing": "buying tea"},
			{"at": [2100, NpcScheduleEntry.OPEN_END], "where": &"odette_cottage", "doing": "sleeping"},
		],
	},
	{
		"id": &"fen",
		"blocks": [
			{"at": [600, 700], "where": &"fen_cottage", "doing": "waking"},
			{"at": [700, 1500], "where": &"forest_edge", "doing": "foraging"},
			{"at": [1500, 1700], "where": &"village_square", "doing": "selling, reluctantly"},
			{"at": [1700, 2000], "where": &"general_store", "doing": "buying salt"},
			{"at": [2000, NpcScheduleEntry.OPEN_END], "where": &"fen_cottage", "doing": "sleeping"},
		],
	},
	{
		"id": &"halda",
		"blocks": [
			{"at": [600, 700], "where": &"halda_cottage", "doing": "waking"},
			{"at": [700, 1200], "where": &"village_orchard", "doing": "pruning"},
			{"at": [1200, 1700], "where": &"village_well", "doing": "arguing about the season"},
			# In Fall she keeps the harvest out on display and does not leave the square.
			{"at": [700, 1700], "where": &"village_square", "doing": "minding the harvest",
				"fall": true},
			{"at": [1700, 2100], "where": &"general_store", "doing": "errands"},
			{"at": [2100, NpcScheduleEntry.OPEN_END], "where": &"halda_cottage", "doing": "sleeping"},
		],
	},
	{
		"id": &"sable",
		"blocks": [
			{"at": [600, 800], "where": &"sable_cottage", "doing": "waking"},
			{"at": [800, 1600], "where": &"village_square", "doing": "mending"},
			{"at": [1600, 1900], "where": &"village_well", "doing": "listening"},
			{"at": [1900, 2100], "where": &"general_store", "doing": "buying thread"},
			{"at": [2100, NpcScheduleEntry.OPEN_END], "where": &"sable_cottage", "doing": "sleeping"},
		],
	},
]


func _initialize() -> void:
	_ensure_dir(LOCATION_DIR)
	_ensure_dir(SCHEDULE_DIR)

	var npcs := _existing_npcs()
	if npcs.is_empty():
		printerr("[generate_npc_schedules] no villagers found in %s" % NPC_DIR)
		printerr("[generate_npc_schedules] run generate_npc_data.gd first")
		quit(1)
		return

	var exit_code := 0
	exit_code += _write_locations(npcs)
	exit_code += _write_schedules()
	quit(1 if exit_code > 0 else 0)


## The cottage locations, positioned from the villager definitions themselves.
##
## The spawn point and the place a schedule sends someone home are the same thing, and
## deriving one from the other is what stops them drifting. A test asserts the equality
## as well, because a generator that writes the right value today and the wrong one
## after a hand edit is exactly the kind of thing nobody notices.
func _write_locations(npcs: Dictionary) -> int:
	var errors := 0
	var written := 0

	for npc_id: StringName in npcs:
		var data: NpcData = npcs[npc_id]
		var place := LocationData.new()
		place.id = StringName("%s_cottage" % npc_id)
		place.display_name = "%s's Cottage" % data.display_name
		place.kind = LocationData.KIND_HOME
		place.position = data.home
		# Face out of the door. Two of the six live on the square rather than in a
		# cottage, so there is no door to face; they keep the heading they arrived with.
		place.facing = _cottage_facing(npc_id)
		if not place.is_valid():
			printerr("[generate_npc_schedules] cottage for %s is invalid" % npc_id)
			errors += 1
			continue
		errors += _save(place, "%s%s.tres" % [LOCATION_DIR, place.id])
		written += 1

	for spec: Dictionary in SHARED_PLACES:
		var place := LocationData.new()
		place.id = spec["id"]
		place.display_name = spec["display_name"]
		place.kind = spec["kind"]
		place.position = spec["position"]
		place.facing = spec["facing"]
		if not place.is_valid():
			printerr("[generate_npc_schedules] location %s is invalid" % place.id)
			errors += 1
			continue
		errors += _save(place, "%s%s.tres" % [LOCATION_DIR, place.id])
		written += 1

	print("[generate_npc_schedules] wrote %d locations to %s" % [written, LOCATION_DIR])
	return errors


## The house yaw, which is the direction its door faces.
##
## `world_builder.gd` derives each house's yaw from its own position, so this repeats
## that formula rather than hard-coding six angles: a house that moves should turn its
## villager to match. The two square residents have no house and return the sentinel.
func _cottage_facing(npc_id: StringName) -> float:
	var centres := {
		&"mira": Vector2(29.0, 2.0),
		&"bram": Vector2(44.0, 0.0),
		&"odette": Vector2(48.0, 13.0),
		&"fen": Vector2(34.0, 16.0),
	}
	if not centres.has(npc_id):
		return LocationData.FACING_UNSET
	var c: Vector2 = centres[npc_id]
	return sin(c.x * 0.37 + c.y * 0.21) * 0.18


func _write_schedules() -> int:
	var errors := 0
	var written := 0
	for spec: Dictionary in SCHEDULES:
		var npc_id: StringName = spec["id"]
		var schedule := NpcSchedule.new()
		schedule.npc_id = npc_id
		for block: Dictionary in spec["blocks"]:
			schedule.entries.append(_entry(block))
		# Sort on write so authoring order in this file is not load-bearing: the
		# validator wants blocks in ascending start order, and a hand-edited `.tres`
		# that is out of order is a content bug the content test will catch.
		schedule.entries.sort_custom(func(a: NpcScheduleEntry, b: NpcScheduleEntry) -> bool:
			return a.from_minute < b.from_minute
		)
		if not schedule.is_valid():
			printerr("[generate_npc_schedules] schedule for %s is invalid: %s" % [
				npc_id, schedule.describe(),
			])
			errors += 1
			continue
		written += 1
		errors += _save(schedule, "%s%s.tres" % [SCHEDULE_DIR, npc_id])

	print("[generate_npc_schedules] wrote %d schedules to %s" % [written, SCHEDULE_DIR])
	return errors


## Turns one authored block into a resource.
##
## The condition keys are named for what they exclude rather than what they require —
## `dry` means "only when it is not raining", and expands to the other three skies. That
## way no block has to remember to enumerate the weathers it does not care about, and
## adding a weather to the game later cannot silently exclude a block.
func _entry(block: Dictionary) -> NpcScheduleEntry:
	var window: Array = block["at"]
	var entry := NpcScheduleEntry.new()
	entry.from_minute = int(window[0])
	entry.to_minute = int(window[1])
	entry.location = block["where"]
	entry.activity = block["doing"]
	if bool(block.get("dry", false)):
		entry.weathers = [WorldTime.Weather.SUN, WorldTime.Weather.WIND]
	if bool(block.get("wet", false)):
		entry.weathers = [
			WorldTime.Weather.RAIN, WorldTime.Weather.STORM, WorldTime.Weather.SNOW,
		]
	if bool(block.get("calm", false)):
		entry.weathers = [WorldTime.Weather.SUN, WorldTime.Weather.WIND, WorldTime.Weather.RAIN]
	if bool(block.get("wild", false)):
		entry.weathers = [WorldTime.Weather.STORM, WorldTime.Weather.SNOW]
	if bool(block.get("winter", false)):
		entry.seasons = [WorldTime.Season.WINTER]
	if bool(block.get("thawed", false)):
		entry.seasons = [
			WorldTime.Season.SPRING, WorldTime.Season.SUMMER, WorldTime.Season.FALL,
		]
	if bool(block.get("fall", false)):
		entry.seasons = [WorldTime.Season.FALL]
	return entry


func _existing_npcs() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(NPC_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var data := ResourceLoader.load("%s%s" % [NPC_DIR, entry]) as NpcData
			if data != null and data.is_valid():
				out[data.id] = data
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _save(resource: Resource, path: String) -> int:
	if ResourceSaver.save(resource, path) != OK:
		printerr("[generate_npc_schedules] failed to write %s" % path)
		return 1
	return 0


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("[generate_npc_schedules] cannot create %s: %d" % [path, err])
		quit(1)