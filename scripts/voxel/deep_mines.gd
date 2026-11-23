class_name DeepMines
extends Node
## Update 2 W3.6: ten deterministic block floors below the old mine entrance.
## A floor is regenerated from (world seed, floor, week), so player edits last
## until the weekly reset and two players on the same seed see the same cave.

const FLOORS := 10
const HALF := 16
const LANTERN_EVERY := 5
const BOSS_FLOOR := 10

signal floor_changed(floor: int)
signal mine_entered()
signal mine_exited()

var floor: int = 0
var week: int = 0
var world_seed: int = 12345
var grid: VoxelGrid = null
var in_mine: bool = false


func enter() -> void:
	if in_mine:
		return
	in_mine = true
	_generate(1)
	mine_entered.emit()


func exit() -> void:
	if not in_mine:
		return
	in_mine = false
	grid = null
	mine_exited.emit()


func descend() -> bool:
	if not in_mine or floor >= FLOORS:
		return false
	_generate(floor + 1)
	return true


func ascend() -> bool:
	if not in_mine or floor <= 1:
		return false
	_generate(floor - 1)
	return true


func is_lantern_room(value: int = -1) -> bool:
	var target := value if value >= 0 else floor
	return target > 0 and target % LANTERN_EVERY == 0


func is_boss_floor(value: int = -1) -> bool:
	var target := value if value >= 0 else floor
	return target == BOSS_FLOOR


func _generate(value: int) -> void:
	floor = value
	grid = VoxelGrid.new()
	VoxelGenerator.new(world_seed + week * 101).generate_mine_floor(
		grid, floor, HALF, -floor * 6 - 2)
	floor_changed.emit(floor)


func set_week(day: int) -> void:
	var next := int(day) / 7
	if next == week:
		return
	week = next
	if in_mine:
		_generate(floor)


func to_dict() -> Dictionary:
	return {"floor": floor, "week": week, "in_mine": in_mine,
		"seed": world_seed, "edits": grid.to_dict() if grid != null else {}}


func from_dict(data: Dictionary) -> void:
	floor = clampi(int(data.get("floor", 0)), 0, FLOORS)
	week = int(data.get("week", 0))
	in_mine = bool(data.get("in_mine", false))
	world_seed = int(data.get("world_seed", data.get("seed", 12345)))
	if in_mine:
		_generate(floor)
		if data.get("edits") is Dictionary:
			grid.from_dict(data["edits"])
