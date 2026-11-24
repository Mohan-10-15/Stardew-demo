class_name DropRules
extends RefCounted
## W5.3: pure rules for physical drops — settle, magnet, merge, despawn.
## No scene dependency so a --script test drives the whole behaviour.

const SETTLE_SPEED := 0.18
const SETTLE_TIME := 0.35
const MAGNET_RADIUS := 2.5
const MAGNET_STRENGTH := 9.0
const MERGE_RADIUS := 1.0
const DESPAWN_SECONDS := 300.0
const MAX_ACTIVE := 128


static func should_sleep(speed: float, still_for: float) -> bool:
	return speed <= SETTLE_SPEED and still_for >= SETTLE_TIME


## Gentle pull toward the player once a drop has settled. Returns a velocity
## delta, not a force, so it can be applied identically in tests and in Godot.
static func magnet_velocity(drop_pos: Vector3, player_pos: Vector3,
		settled: bool) -> Vector3:
	if not settled:
		return Vector3.ZERO
	var flat := Vector3(player_pos.x - drop_pos.x, 0.0, player_pos.z - drop_pos.z)
	var distance := flat.length()
	if distance <= 0.001 or distance > MAGNET_RADIUS:
		return Vector3.ZERO
	return flat.normalized() * MAGNET_STRENGTH * (1.0 - distance / MAGNET_RADIUS)


static func should_despawn(age: float) -> bool:
	return age >= DESPAWN_SECONDS


## Indices of same-item drops close enough to merge into the first one.
static func merge_groups(entries: Array[Dictionary], radius: float = MERGE_RADIUS) -> Array:
	var groups: Array = []
	var used := {}
	for i: int in range(entries.size()):
		if used.has(i):
			continue
		var group: Array[int] = [i]
		used[i] = true
		for j: int in range(i + 1, entries.size()):
			if used.has(j):
				continue
			if entries[i].get("item_id", &"") != entries[j].get("item_id", &""):
				continue
			var a: Vector3 = entries[i].get("position", Vector3.ZERO)
			var b: Vector3 = entries[j].get("position", Vector3.ZERO)
			if a.distance_to(b) <= radius:
				group.append(j)
				used[j] = true
		if group.size() > 1:
			groups.append(group)
	return groups


static func evict_index(entries: Array[Dictionary]) -> int:
	if entries.size() <= MAX_ACTIVE:
		return -1
	var oldest := 0
	var age := -1.0
	for i: int in range(entries.size()):
		var candidate := float(entries[i].get("age", 0.0))
		if candidate > age:
			age = candidate
			oldest = i
	return oldest
