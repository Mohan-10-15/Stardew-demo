extends SceneTree
## Headless tool: generates `scenes/core/main.tscn`.
##
## Run:
##     godot --headless --path . --script res://tools/generate_main_scene.gd
##
## Intentionally near-empty: the main scene is a container that spawns the
## world and the player at runtime. The sun and camera come from `world.tscn`
## and `player.tscn` respectively, so adding a camera here would fight the
## player's rig over `current`.

const OUTPUT_PATH := "res://scenes/core/main.tscn"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Main"
	root.set_script(load("res://scripts/core/main.gd"))

	# Explicit owner so the node is serialised into the scene file.
	root.owner = root

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		printerr("[generate_main_scene] pack failed: %d" % err)
		quit(1)
		return

	err = ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		printerr("[generate_main_scene] save failed: %d" % err)
		quit(1)
		return

	print("[generate_main_scene] wrote %s" % OUTPUT_PATH)
	quit(0)