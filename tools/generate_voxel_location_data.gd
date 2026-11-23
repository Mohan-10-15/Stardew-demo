extends SceneTree
## Adds the Builders' Plot and Deep Mines to the named-location content.
##   Godot --headless --path . --script res://tools/generate_voxel_location_data.gd

const OUT := "res://resources/world/locations/"
const SCRIPT := "res://scripts/world/location_data.gd"

const PLACES: Array[Dictionary] = [
	{"id": &"builders_plot", "name": "The Builders' Plot", "pos": Vector2(34, 26), "kind": &"build"},
	{"id": &"deep_mines_stairs", "name": "The Deep Stairs", "pos": Vector2(-12, -34), "kind": &"mine"},
	{"id": &"mine_lantern_room", "name": "The Lantern Room", "pos": Vector2(-12, -34), "kind": &"mine"},
]


func _initialize() -> void:
	var script := load(SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in PLACES:
		var data: Object = script.new()
		data.set("id", spec["id"])
		data.set("display_name", spec["name"])
		data.set("position", spec["pos"])
		data.set("kind", spec["kind"])
		if not bool(data.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(data, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_voxel_location_data] wrote %d places" % PLACES.size())
	quit(1 if errors > 0 else 0)
