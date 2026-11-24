class_name VoxelService
extends Node
## Owns the player's block edits in the Builders' Plot and the Deep Mines.
## Pure grid logic lives in scripts/voxel/; this node only drives it, draws
## chunks and publishes distinct success/failure events through EventBus.

const SERVICE_GROUP := &"voxel_service"
## Aligned to the 5 m ground cells so the hole cut in the terrain mesh is
## covered exactly by the voxel plot — no invisible rim to fall through.
const PLOT_CENTRE := Vector3i(35, 0, 25)
const PLOT_HALF := 5
const PLOT_GROUND := 1

signal grid_changed()

var grid: VoxelGrid = null
var chunks_root: Node3D = null
var _nodes: Dictionary = {}


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	grid = VoxelGrid.new()
	VoxelGenerator.new(ProjectSettings.get_setting("application/config/seed", 12345)).generate_plot(
		grid, PLOT_HALF, PLOT_GROUND)
	# Child of this service, not of the tree root: freeing a test rig must not
	# fight the tree while it is already removing children.
	chunks_root = Node3D.new()
	chunks_root.name = "VoxelChunks"
	# The grid is authored around the origin for simple integer coordinates;
	# this transform places the Builders' Plot beside the farm in the valley.
	chunks_root.position = Vector3(PLOT_CENTRE)
	add_child(chunks_root)
	rebuild_all()


func rebuild_all() -> void:
	if grid == null:
		return
	for coord: Variant in grid.chunks:
		var key := coord as Vector3i
		if not _nodes.has(key):
			var node := VoxelChunkNode.new()
			node.name = "Chunk_%d_%d_%d" % [key.x, key.y, key.z]
			chunks_root.add_child(node)
			node.setup(key)
			_nodes[key] = node
		(_nodes[key] as VoxelChunkNode).rebuild(grid)


func break_at(cell: Vector3i, tool_id: StringName) -> bool:
	var block_id := grid.get_block(cell)
	var block := BlockRegistry.get_block(block_id)
	var refusal := BlockBreaking.can_break(block, tool_id)
	if refusal != &"":
		EventBus.block_break_refused.emit(block_id, refusal)
		return false
	if not grid.set_block(cell, &""):
		EventBus.block_break_refused.emit(block_id, &"out_of_bounds")
		return false
	_mark_dirty(cell)
	EventBus.block_broken.emit(block_id, cell, tool_id)
	grid_changed.emit()
	return true


func place_at(cell: Vector3i, block_id: StringName) -> bool:
	var block := BlockRegistry.get_block(block_id)
	if block == null:
		EventBus.block_place_refused.emit(block_id, &"no_block")
		return false
	if not grid.is_air(cell):
		EventBus.block_place_refused.emit(block_id, &"occupied")
		return false
	if not grid.set_block(cell, block_id):
		EventBus.block_place_refused.emit(block_id, &"out_of_bounds")
		return false
	_mark_dirty(cell)
	EventBus.block_placed.emit(block_id, cell)
	grid_changed.emit()
	return true


func _mark_dirty(cell: Vector3i) -> void:
	var coord := VoxelGrid.chunk_coord(cell)
	var node: Variant = _nodes.get(coord)
	if node is VoxelChunkNode:
		(node as VoxelChunkNode).rebuild(grid)


## Swaps the block look live. Both packs are procedural and ship in-repo, so
## the player can flip between detailed and 16-pixel blocks without a reload.
func set_texture_pack(pack: String) -> bool:
	if not FileAccess.file_exists("res://assets/voxel/packs/%s/atlas.png" % pack):
		return false
	Config.set_value(&"world", "voxel_texture_pack", pack)
	for node: Variant in _nodes.values():
		if node is VoxelChunkNode:
			(node as VoxelChunkNode).set_texture_pack(pack)
	return true


func active_texture_pack() -> String:
	return String(Config.settings.voxel_texture_pack)


func raycast(origin: Vector3, direction: Vector3, reach: float = 5.0) -> Dictionary:
	return VoxelRaycast.cast(grid, origin, direction, reach)


static func find(start: Node) -> VoxelService:
	if start == null:
		return null
	if start is VoxelService:
		return start as VoxelService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


## Which block a held item places, if any. Data-driven through BlockData.
static func block_for_item(item_id: StringName) -> StringName:
	for block: BlockData in BlockRegistry.all_blocks():
		if block.place_item == item_id and block.collision_kind != "water":
			return block.id
	return &""


func to_dict() -> Dictionary:
	return grid.to_dict() if grid != null else {}


func from_dict(data: Dictionary) -> void:
	if grid == null:
		return
	grid.from_dict(data)
	rebuild_all()
