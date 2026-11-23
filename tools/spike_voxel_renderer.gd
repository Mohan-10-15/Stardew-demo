extends SceneTree
## W3.1 spike: build the same 64x64x32 volume two ways and time it.
##   Godot --headless --path . --script res://tools/spike_voxel_renderer.gd
## (a) custom ArrayMesh mesher via VoxelMesher; (b) GridMap over the same data.
## Numbers go into the W3 renderer decision entry, not into a guess.

const VOL := Vector3i(64, 32, 64)
const CHUNKS := Vector3i(4, 2, 4)


func _initialize() -> void:
	# Build one dense volume of data first, so both paths start from the same grid.
	var grid := VoxelGrid.new()
	var gen := VoxelGenerator.new(777)
	var t0 := Time.get_ticks_usec()
	gen.generate_mine_floor(grid, 1, VOL.x / 2, 4)
	var data_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	# (a) custom mesher: mesh every chunk.
	t0 = Time.get_ticks_usec()
	var faces := 0
	var vertices := 0
	for cx: int in range(CHUNKS.x):
		for cy: int in range(CHUNKS.y):
			for cz: int in range(CHUNKS.z):
				var report: Dictionary = VoxelMesher.build(
					grid, Vector3i(cx, cy, cz))
				faces += int(report.get("faces", 0))
				vertices += (report.get("vertices") as PackedVector3Array).size()
	var custom_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	# (b) GridMap with a one-cube MeshLibrary, setting the same occupied cells.
	t0 = Time.get_ticks_usec()
	var library := MeshLibrary.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	library.create_item(0)
	library.set_item_mesh(0, cube)
	var map := GridMap.new()
	map.mesh_library = library
	var cells := 0
	for x: int in range(VOL.x):
		for y: int in range(4, 10):
			for z: int in range(VOL.z):
				if not grid.get_block(Vector3i(x - 32, y, z - 32)).is_empty():
					map.set_cell_item(Vector3i(x, y, z), 0)
					cells += 1
	var gridmap_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	var custom_kb := float(vertices) * 32.0 / 1024.0
	print("[spike] volume 64x32x64, occupied cells=%d" % cells)
	print("[spike] data build %.1f ms" % data_ms)
	print("[spike] custom mesher: %.1f ms, %d faces, %d verts (~%.0f KiB arrays)" % [
		custom_ms, faces, vertices, custom_kb,
	])
	print("[spike] GridMap: %.1f ms for %d set_cell_item calls" % [gridmap_ms, cells])
	print("[spike] winner: %s" % (
		"custom mesher" if custom_ms <= gridmap_ms else "GridMap"))
	quit(0)
