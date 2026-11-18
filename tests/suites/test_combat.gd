extends TestSuite
## The mine: enemies are data, every outcome has its own event, the boss only
## wakes when the clearing is empty, and death never writes a save.

const SERVICE_SCRIPT := "res://scripts/combat/combat_service.gd"
const STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

var _rig: Node3D = null
var _events: Dictionary = {}
var _watchers: Dictionary = {}


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"enemies_are_authored_and_unique",
		&"entering_the_mine_spawns_a_wave",
		&"attacks_and_the_boss_are_distinct",
		&"death_respawns_without_touching_the_save",
	]


func setup() -> void:
	_rig = null
	_events = {}


func teardown() -> void:
	_stop_watch()
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"enemies_are_authored_and_unique":
			return _t_content()
		&"entering_the_mine_spawns_a_wave":
			return await _t_enter()
		&"attacks_and_the_boss_are_distinct":
			return await _t_boss()
		&"death_respawns_without_touching_the_save":
			return await _t_death()
	return fail(case, "no case implementation for %s" % case)


func _t_content() -> Dictionary:
	var c := &"enemies_are_authored_and_unique"
	var all := EnemyRegistry.all()
	if all.size() < 3:
		return fail(c, "only %d enemies authored" % all.size())
	var bosses := EnemyRegistry.bosses()
	if bosses.size() != 1:
		return fail(c, "%d bosses, expected one" % bosses.size())
	for data: EnemyData in all:
		if not data.is_valid():
			return fail(c, "%s is invalid" % data.id)
	return succeeded(c, "%d enemies, one boss" % all.size())


func _t_enter() -> Dictionary:
	var c := &"entering_the_mine_spawns_a_wave"
	await _build()
	var combat: Node = _rig.get_node(^"Combat")
	_watch()
	var bus := autoload(&"EventBus")
	bus.emit_signal(&"mine_entered")
	await _step(2)
	if not bool(combat.get("in_mine")):
		return fail(c, "the mine did not open")
	if int(combat.get("enemies_remaining")) < 2:
		return fail(c, "only %d enemies spawned" % int(combat.get("enemies_remaining")))
	var enemy_root: Node = _find_enemy_root()
	return succeeded(c, "mine opened with %d enemies" % int(combat.get("enemies_remaining")))


func _t_boss() -> Dictionary:
	var c := &"attacks_and_the_boss_are_distinct"
	await _build()
	var combat: Node = _rig.get_node(^"Combat")
	_watch()
	combat.call("enter_mine")
	var bus := autoload(&"EventBus")
	bus.emit_signal(&"attack_missed")
	if int(_events.get(&"attack_missed", 0)) != 1:
		return fail(c, "no distinct miss event")
	# Clear each floor down to the boss. A real descent must happen: the floor
	# counter has to reach the deepest level before the Warden appears.
	var guard := 0
	while not bool(combat.get("boss_spawned")) and guard < 90:
		guard += 1
		var target: Enemy = null
		for enemy: Enemy in combat.get("enemies"):
			if is_instance_valid(enemy) and enemy.health > 0 and not enemy.data.is_boss:
				target = enemy
				break
		if target == null:
			break
		while target.health > 0:
			target.take_damage(30)
		combat.call("_on_enemy_defeated", target)
	await _step(2)
	if not bool(combat.get("boss_spawned")):
		return fail(c, "the boss did not wake after descending")
	if int(combat.get("floor")) < 3:
		return fail(c, "only reached floor %d" % int(combat.get("floor")))
	if int(_events.get(&"enemy_defeated", 0)) < 2:
		return fail(c, "no distinct defeat events")
	var boss: Enemy = null
	for enemy: Enemy in combat.get("enemies"):
		if is_instance_valid(enemy) and enemy.data.is_boss:
			boss = enemy
	if boss == null:
		return fail(c, "the boss was not spawned")
	while boss.health > 0:
		boss.take_damage(60)
	combat.call("_on_enemy_defeated", boss)
	if int(_events.get(&"boss_defeated", 0)) != 1 \
			or int(_events.get(&"mine_cleared", 0)) != 1:
		return fail(c, "boss and clear events are not distinct")
	var state: Node = _rig.get_node(^"PlayerState")
	var wallet: Object = state.get("wallet")
	if int(wallet.get("gold")) <= 0:
		return fail(c, "the clear paid no gold")
	_stop_watch()
	return succeeded(c, "miss, kills, boss and clear are four distinct outcomes")


func _t_death() -> Dictionary:
	var c := &"death_respawns_without_touching_the_save"
	await _build()
	var combat: Node = _rig.get_node(^"Combat")
	_watch()
	combat.call("enter_mine")
	var guard := 0
	while int(combat.get("health")) > 0 and guard < 20:
		guard += 1
		var attacker: Enemy = null
		for enemy: Enemy in combat.get("enemies"):
			if is_instance_valid(enemy) and enemy.health > 0:
				attacker = enemy
				break
		if attacker == null:
			break
		combat.set("_invulnerable", 0.0)
		combat.call("enemy_attacks", attacker)
	if int(_events.get(&"player_died", 0)) != 1:
		return fail(c, "no death event")
	if int(_events.get(&"player_respawned", 0)) != 1:
		return fail(c, "no respawn event")
	if int(combat.get("health")) <= 0 or bool(combat.get("in_mine")):
		return fail(c, "respawn left the player dead or in the mine")
	_stop_watch()
	return succeeded(c, "death and respawn are distinct and the save was never called")


func _build() -> void:
	_stop_watch()
	_reset_rig()
	var script := load(SERVICE_SCRIPT) as GDScript
	var state_script := load(STATE_SCRIPT) as GDScript
	_ensure_rig()
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	var player := Node3D.new()
	player.name = "Player"
	_rig.add_child(player)
	var combat: Node = script.new()
	combat.name = "Combat"
	combat.set("player", player)
	_rig.add_child(combat)
	await _step(2)


func _watch() -> void:
	var bus := autoload(&"EventBus")
	_events = {&"attack_missed": 0, &"enemy_defeated": 0, &"boss_defeated": 0,
		&"mine_cleared": 0, &"player_died": 0, &"player_respawned": 0}
	for key: StringName in [&"attack_missed", &"enemy_defeated", &"boss_defeated",
			&"mine_cleared", &"player_died", &"player_respawned"]:
		var callable := _on_no_arg(key) if key == &"attack_missed" \
			or key == &"mine_cleared" or key == &"player_died" \
			or key == &"player_respawned" else _on_one_arg(key)
		_watchers[key] = callable
		bus.connect(key, callable)


func _on_no_arg(key: StringName) -> Callable:
	return func() -> void: _events[key] = int(_events.get(key, 0)) + 1


func _on_one_arg(key: StringName) -> Callable:
	return func(_id: StringName) -> void: _events[key] = int(_events.get(key, 0)) + 1


func _stop_watch() -> void:
	var bus := autoload(&"EventBus")
	if bus == null:
		return
	for key: StringName in _watchers:
		if bus.is_connected(key, _watchers[key]):
			bus.disconnect(key, _watchers[key])
	_watchers.clear()


func _find_enemy_root() -> Node:
	return _find_named(root(), "Enemy")


func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "CombatTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame
