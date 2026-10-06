extends SceneTree
## Times the places that scale with world size, so the multi-language decision in
## `docs/MULTI_LANGUAGE_ARCHITECTURE.md` rests on a measurement rather than on
## the intuition that native code is faster.
##
## Run:
##     tools/Godot_v4.5-stable_mono_win64_console.exe --headless --path . --script res://tools/profile_boot.gd
##
## Three candidates, all of which get more expensive as the valley grows:
##
##   1. `WorldBuilder.is_reserved` — a linear scan of every keep-out region for
##      every placement candidate.
##   2. `DecorationField._too_close` — a linear scan of every occupied point for
##      every rejected candidate. O(attempts x occupied).
##   3. `NpcNavigation.build` — 112 x 96 = 10,752 cells, two physics queries each.
##      The only one that is genuinely a tight inner loop over engine calls.
##
## Plus the number that bounds all of them: one whole world build with the
## decoration scatter included.
##
## ## Why everything is loaded by path
##
## This is AGENTS.md's first Godot trap. A `--script` entry point is compiled
## during startup, before the autoloads are added to the root, so any `class_name`
## whose file mentions `Log` or `EventBus` fails to compile *here* while compiling
## perfectly well when `run_tests.gd` loads it a frame later. Naming `WorldBuilder`
## directly would make this tool unrunnable; `load()`-ing the script and calling
## through `call()` defers the compile until the autoloads exist.

const WORLD_BUILDER := "res://scripts/world/world_builder.gd"
const NPC_NAVIGATION := "res://scripts/npc/npc_navigation.gd"

## Autoloads are added to the root after `_initialize()` returns, so every
## measurement waits for them first — `NpcNavigation.build` logs through `Log`.
func _initialize() -> void:
	await process_frame
	await process_frame

	var timings: PackedStringArray = []

	var world_builder := load(WORLD_BUILDER) as GDScript
	var nav_script := load(NPC_NAVIGATION) as GDScript
	if world_builder == null or nav_script == null:
		print("[profile] could not load the scripts under test")
		quit(1)
		return

	# The container has to be in the tree: NpcNavigation reads `direct_space_state`
	# off its own World3D, and a parentless Node3D has none.
	var container := Node3D.new()
	container.name = "ProfileRoot"
	root.add_child(container)

	# --- 1. Whole world build + decoration scatter ---------------------------
	var t0 := Time.get_ticks_usec()
	var world := Node3D.new()
	world.name = "World"
	world_builder.call("build", world, 12345)
	container.add_child(world)
	var t_world := Time.get_ticks_usec() - t0
	timings.append("world build + decoration scatter: %.1f ms" % (t_world / 1000.0))

	# Physics only sees shapes that have been flushed to the server, and the
	# builder added them a moment ago. Two frames is what boot_check waits.
	await process_frame
	await process_frame

	# --- 2. Villager navigation grid -----------------------------------------
	var nav: Node = nav_script.new()
	container.add_child(nav)
	var size: Vector2i = nav_script.get("SIZE")
	var t3 := Time.get_ticks_usec()
	var built: bool = nav.call("build")
	var t_nav := Time.get_ticks_usec() - t3
	if built:
		timings.append("NpcNavigation.build over %dx%d cells: %.1f ms (%d walkable, %d blocked)" % [
			size.x, size.y, t_nav / 1000.0,
			int(nav.get("walkable_cells")), int(nav.get("blocked_cells")),
		])
	else:
		timings.append("NpcNavigation.build: no physics space (probe ran before the world settled)")
	nav.free()

	# --- 3. Keep-out check, micro --------------------------------------------
	var reserved_calls := 100000
	var t1 := Time.get_ticks_usec()
	var hits := 0
	for i: int in reserved_calls:
		if world_builder.call("is_reserved", Vector2(float(i % 220) - 110.0, float(i / 220) - 110.0)):
			hits += 1
	var t_reserved := Time.get_ticks_usec() - t1
	timings.append("WorldBuilder.is_reserved x%d: %.1f ms (%.2f us each, %d hits)" % [
		reserved_calls, t_reserved / 1000.0, float(t_reserved) / float(reserved_calls), hits,
	])

	# --- 4. Spacing check, micro ---------------------------------------------
	var occupied: Array[Vector2] = []
	for i: int in 600:
		occupied.append(Vector2(float(i % 30) * 3.0, float(i / 30) * 3.0))
	var spacing_calls := 50000
	var t2 := Time.get_ticks_usec()
	var close_hits := 0
	for i: int in spacing_calls:
		if _too_close(Vector2(float(i % 400), float(i / 400)), occupied, 1.5):
			close_hits += 1
	var t_spacing := Time.get_ticks_usec() - t2
	timings.append("DecorationField._too_close x%d vs %d occupied: %.1f ms (%.2f us each)" % [
		spacing_calls, occupied.size(), t_spacing / 1000.0, float(t_spacing) / float(spacing_calls),
	])

	container.free()

	for line: String in timings:
		print("[profile] %s" % line)
	quit(0)


## A copy of `DecorationField._too_close`, because the original is a private
## method on a node that also wants a scene. The point of the measurement is the
## *shape* of the algorithm — a linear scan per candidate — not the exact bytes.
func _too_close(pos: Vector2, occupied: Array[Vector2], spacing: float) -> bool:
	if spacing <= 0.0:
		return false
	for other: Vector2 in occupied:
		if pos.distance_to(other) < spacing:
			return true
	return false
