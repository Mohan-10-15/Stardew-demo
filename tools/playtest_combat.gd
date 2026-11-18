extends SceneTree
## Real-window review of the mine: enter with E, strike with K, clear the Warden.
##
##     godot --path . --rendering-driver opengl3 --script res://tools/playtest_combat.gd
##
## Enemy health is trimmed between presses so this review fits in a few seconds;
## the entry, the attack and the outcomes are real events and real input.

const MAIN := "res://scenes/core/main.tscn"
const SHOT := "res://art_review_combat_"

var _main: Node = null
var _landed := 0
var _cleared := 0


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
	var bus := root.get_node_or_null(^"EventBus")
	bus.connect(&"attack_landed", func(_id: StringName, _dmg: int) -> void: _landed += 1)
	bus.connect(&"mine_cleared", func() -> void: _cleared += 1)
	root.add_child(_main)
	var ready := [false]
	bus.game_ready.connect(func() -> void: ready[0] = true)
	var deadline := Time.get_ticks_msec() + 30000
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	var combat: Node = _main.get("combat_service")
	var player: Node3D = _main.get("player")
	var entrance := _main.get_node_or_null(^"World/MineEntrance")
	if combat == null or player == null or entrance == null:
		printerr("[play] missing combat, player or mine entrance")
		quit(1)
		return
	player.global_position = Vector3(-30, 0.4, 2)
	await _settle(4)
	await _key(KEY_E)
	await _settle(4)
	if not bool(combat.get("in_mine")):
		printerr("[play] E did not open the mine")
		quit(1)
		return
	print("[play] mine opened with %d enemies" % int(combat.get("enemies_remaining")))
	await _shot(SHOT + "01_wave.png")

	# Real K press with an enemy in reach.
	var target: Enemy = null
	for enemy: Enemy in combat.get("enemies"):
		if is_instance_valid(enemy) and not enemy.data.is_boss:
			target = enemy
			break
	if target == null:
		printerr("[play] no regular enemy spawned")
		quit(1)
		return
	player.global_position = target.global_position + Vector3(0, 0.4, 2.0)
	await _settle(3)
	await _key(KEY_K)
	await _settle(3)
	if _landed < 1:
		printerr("[play] K did not land an attack")
		quit(1)
		return
	print("[play] attack landed (%d)" % _landed)
	await _shot(SHOT + "02_attack.png")

	# Fast-forward the descent and the rest of the fight for this review.
	var guard := 0
	while not bool(combat.get("boss_spawned")) and guard < 90:
		guard += 1
		var victim: Enemy = null
		for enemy: Enemy in combat.get("enemies"):
			if is_instance_valid(enemy) and not enemy.data.is_boss:
				victim = enemy
				break
		if victim == null:
			if int(combat.get("enemies_remaining")) > 0:
				continue
			break
		while victim.health > 0:
			victim.take_damage(60)
		combat.call("_on_enemy_defeated", victim)
	var boss: Enemy = null
	for enemy: Enemy in combat.get("enemies"):
		if is_instance_valid(enemy) and enemy.data.is_boss:
			boss = enemy
	if boss == null:
		printerr("[play] the Warden never appeared")
		quit(1)
		return
	print("[play] Warden awakened")
	await _shot(SHOT + "03_boss.png")
	while boss.health > 0:
		boss.take_damage(60)
	combat.call("_on_enemy_defeated", boss)
	if _cleared != 1:
		printerr("[play] mine_cleared did not fire")
		quit(1)
		return
	print("[play] mine cleared")
	await _shot(SHOT + "04_cleared.png")
	print("[play] PASS")
	quit(0)


func _key(code: int) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(3)
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await _settle(3)


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(path)
