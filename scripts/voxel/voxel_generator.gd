class_name VoxelGenerator
extends RefCounted
## Seeded terrain for the Builders' Plot and the Deep Mines. Pure: same seed
## and floor always produce the same blocks, which is what the determinism
## test and the weekly mine reset rely on.

const SOLID := &"hollowbrook_stone"
const GROUND := &"hollowbrook_soil"
const GRASS := &"hollowbrook_grass"
const ORE_COPPER := &"copper_vein_block"
const ORE_IRON := &"iron_vein_block"
const ORE_GOLD := &"gold_vein_block"
const ORE_EMBER := &"ember_crystal_block"
const WATER := &"water_block"

var seed_value: int = 12345


func _init(value: int = 12345) -> void:
	seed_value = value


## Builds a square plot: a flat grass surface over soil and stone.
func generate_plot(grid: VoxelGrid, half: int, ground_y: int) -> void:
	for x: int in range(-half, half):
		for z: int in range(-half, half):
			grid.set_block(Vector3i(x, ground_y, z), GRASS)
			for y: int in range(ground_y - 3, ground_y):
				grid.set_block(Vector3i(x, y, z), GROUND if y == ground_y - 1 else SOLID)
			if absi(x) == half - 1 or absi(z) == half - 1:
				grid.set_block(Vector3i(x, ground_y + 1, z), &"fence_block")


## Builds one mine floor: cave floors from layered 3D noise, ore by depth,
## tunnels carved along two seeded axes so enemies and players can move.
func generate_mine_floor(grid: VoxelGrid, floor: int, half: int, base_y: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + floor * 7919
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.12
	for x: int in range(-half, half):
		for z: int in range(-half, half):
			var h := base_y + int(round(noise.get_noise_2d(x, z) * 2.0))
			grid.set_block(Vector3i(x, h, z), SOLID)
			if h < base_y:
				grid.set_block(Vector3i(x, h + 1, z), WATER)
			var depth := floor * 6 + (base_y - h)
			for y: int in range(h - 1, h - 4, -1):
				var ore := _ore_at(depth, x, y, z, noise)
				grid.set_block(Vector3i(x, y, z), ore if ore != &"" else SOLID)
	# Two straight tunnels through the floor, at seeded offsets.
	var corridor_x := (seed_value + floor * 13) % (half - 2)
	var corridor_z := (seed_value + floor * 29) % (half - 2)
	for x: int in range(-half, half):
		for y: int in range(base_y + 1, base_y + 4):
			grid.set_block(Vector3i(x, y, corridor_z - half + 1), &"")
	for z: int in range(-half, half):
		for y: int in range(base_y + 1, base_y + 4):
			grid.set_block(Vector3i(corridor_x - half + 1, y, z), &"")


func _ore_at(depth: int, x: int, y: int, z: int, noise: FastNoiseLite) -> StringName:
	var n := noise.get_noise_3d(x * 3, y * 3, z * 3)
	if n > 0.62 and depth >= 45:
		return ORE_EMBER
	if n > 0.55 and depth >= 24:
		return ORE_GOLD
	if n > 0.45 and depth >= 10:
		return ORE_IRON
	if n > 0.38:
		return ORE_COPPER
	return &""
