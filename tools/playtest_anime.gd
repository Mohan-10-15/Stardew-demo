extends SceneTree
## W4 evidence: a villager uses an embedded KayKit clip in a real window.
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_anime.gd

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_anime_"

var _main: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[play] no rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	_main = packed.instantiate()
	_main.set("show_title_on_boot", false)
	root.add_child(_main)
	var bus := root.get_node_or_null(^"EventBus")
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	await _settle(30)

	var npc := _find_npc(root, &"mira")
	if npc == null:
		printerr("[play] no Mira")
		quit(1)
		return
	var player: AnimationPlayer = npc.get("_clip_player")
	if player == null:
		printerr("[play] Mira has no embedded AnimationPlayer")
		quit(1)
		return
	var clip: StringName = npc.get("_current_clip")
	if clip.is_empty() or not player.is_playing():
		printerr("[play] no clip is playing (current='%s')" % clip)
		quit(1)
		return
	print("[play] Mira is playing '%s' from her 76 embedded clips" % clip)
	var profile: CharacterProfile = npc.get("data").get("profile")
	print("[play] profile=%s build=%d head=%.2f hair=%s" % [
		profile.id, profile.build, profile.head_scale, profile.hair_style,
	])
	await _shot(SHOT + "01_clip.png")
	print("[play] PASS")
	quit(0)


func _find_npc(node: Node, wanted: StringName) -> Node:
	if node == null:
		return null
	if node.name == wanted and node.has_meta("npc_id"):
		return node
	for child: Node in node.get_children():
		var found := _find_npc(child, wanted)
		if found != null:
			return found
	return null


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
