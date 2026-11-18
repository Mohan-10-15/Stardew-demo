class_name CombatService
extends Node
## The mine: health, attacks, enemy waves, the boss and a death that never
## touches the save.
##
## A manager with no rules about *what* an enemy is — definitions come from
## [EnemyRegistry]. Each outcome publishes a distinct EventBus event.

const SERVICE_GROUP := &"combat_service"
const ENEMY_SCRIPT := "res://scripts/combat/enemy.gd"
const MAX_HEALTH := 100
const ATTACK_DAMAGE := 30
const ATTACK_RANGE := 3.4
const RESPAWN_POINT := Vector3(0, 1.2, 14)
const MINE_CENTRE := Vector3(-30, 0, -6)
const DEEPEST_FLOOR := 3

var player: Node3D = null
var health: int = MAX_HEALTH
var in_mine: bool = false
var enemies_remaining: int = 0
var floor: int = 1
var boss_spawned: bool = false
var cleared: bool = false
var enemies: Array[Enemy] = []
var _invulnerable: float = 0.0


static func find(start: Node) -> CombatService:
	if start == null:
		return null
	if start is CombatService:
		return start as CombatService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	var bus := _bus()
	if bus != null:
		bus.mine_entered.connect(enter_mine)


func _exit_tree() -> void:
	var bus := _bus()
	if bus != null and bus.mine_entered.is_connected(enter_mine):
		bus.mine_entered.disconnect(enter_mine)


func _process(delta: float) -> void:
	_invulnerable = maxf(0.0, _invulnerable - delta)
	if Input.is_action_just_pressed(InputActions.ATTACK) and in_mine:
		attempt_attack()


func enter_mine() -> void:
	if in_mine:
		return
	in_mine = true
	cleared = false
	boss_spawned = false
	floor = 1
	health = MAX_HEALTH
	for data: EnemyData in EnemyRegistry.all():
		if not data.is_boss:
			_spawn(data, MINE_CENTRE + Vector3(
				float(enemies.size()) * 2.2 - 2.0, 0, float(enemies.size() % 2) * 2.0
			))
			enemies_remaining += 1
	Log.info("Combat", "Mine entered: %d enemies" % enemies_remaining)


func _spawn(data: EnemyData, at: Vector3) -> Enemy:
	var script := load(ENEMY_SCRIPT) as GDScript
	if script == null or data == null:
		return null
	var enemy: Enemy = script.new()
	enemy.name = String(data.id)
	get_tree().get_root().add_child(enemy)
	enemy.global_position = at
	enemy.setup(data, self)
	enemies.append(enemy)
	return enemy


func attempt_attack() -> void:
	var target: Enemy = null
	var nearest := ATTACK_RANGE
	for enemy: Enemy in enemies:
		if not is_instance_valid(enemy) or enemy.health <= 0 or player == null:
			continue
		var d := enemy.global_position.distance_to(player.global_position)
		if d < nearest:
			nearest = d
			target = enemy
	var bus := _bus()
	if target == null:
		if bus != null:
			bus.attack_missed.emit()
		return
	var killed := target.take_damage(ATTACK_DAMAGE)
	if bus != null:
		bus.attack_landed.emit(target.data.id, ATTACK_DAMAGE)
	if killed:
		_on_enemy_defeated(target)


func _on_enemy_defeated(enemy: Enemy) -> void:
	var data := enemy.data
	var bus := _bus()
	if bus != null:
		bus.enemy_defeated.emit(data.id)
	_reward(data)
	enemies.erase(enemy)
	enemy.queue_free()
	if data.is_boss:
		cleared = true
		if bus != null:
			bus.boss_defeated.emit(data.id)
			bus.mine_cleared.emit()
		Log.info("Combat", "Mine cleared — the Warden is down")
		return
	enemies_remaining = maxi(0, enemies_remaining - 1)
	if enemies_remaining == 0 and not boss_spawned:
		if floor < DEEPEST_FLOOR:
			descend()
		else:
			boss_spawned = true
			var bosses := EnemyRegistry.bosses()
			if not bosses.is_empty():
				_spawn(bosses[0], MINE_CENTRE + Vector3(0, 0, -4))
				if bus != null:
					bus.mine_boss_spawned.emit()
				Log.info("Combat", "The Mine Warden awakens")


## Clearing a floor opens the way down. Each descent spawns a harder wave, so
## "the mine can be entered and descended" is literally true rather than just a
## longer fight in one room.
func descend() -> void:
	floor += 1
	enemies_remaining = 0
	var scale := (floor - 1) * 20
	for data: EnemyData in EnemyRegistry.all():
		if data.is_boss:
			continue
		var at := MINE_CENTRE + Vector3(
			float(enemies_remaining % 3) * 2.4 - 2.4, 0,
			float(floor) * -2.0 + float(enemies_remaining / 3) * 2.0
		)
		var enemy := _spawn(data, at)
		if enemy != null:
			enemy.health += scale
			enemies_remaining += 1
	var bus := _bus()
	if bus != null:
		bus.mine_floor_changed.emit(floor)
	Log.info("Combat", "Descended to floor %d: %d enemies" % [floor, enemies_remaining])


func _reward(data: EnemyData) -> void:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	if state == null or state.get("wallet") == null:
		return
	var wallet: Object = state.get("wallet")
	wallet.call("set_gold", int(wallet.get("gold")) + data.gold_reward)
	if state.get("inventory") != null and not data.ore_reward.is_empty():
		var bag: Object = state.get("inventory")
		bag.call("add", data.ore_reward, 1)


func enemy_attacks(_enemy: Enemy) -> void:
	if player == null or _invulnerable > 0.0 or health <= 0:
		return
	_invulnerable = 0.6
	health = maxi(0, health - _enemy.data.damage)
	var bus := _bus()
	if bus != null:
		bus.player_damaged.emit(_enemy.data.damage, health)
	if health == 0:
		_die()


func _die() -> void:
	var bus := _bus()
	if bus != null:
		bus.player_died.emit()
	if player != null:
		player.global_position = RESPAWN_POINT
		if player.get("velocity") != null:
			player.set("velocity", Vector3.ZERO)
	health = MAX_HEALTH
	_invulnerable = 2.0
	in_mine = false
	# Death never writes a save: the aggregate save is the player's own choice.
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	if bus != null:
		bus.player_respawned.emit()
	Log.info("Combat", "Respawned at the farm; save untouched")


func to_dict() -> Dictionary:
	return {"health": health, "in_mine": in_mine, "cleared": cleared,
		"boss_spawned": boss_spawned, "enemies_remaining": enemies_remaining,
		"floor": floor}


func from_dict(data: Dictionary) -> void:
	health = clampi(int(data.get("health", MAX_HEALTH)), 0, MAX_HEALTH)
	in_mine = bool(data.get("in_mine", false))
	cleared = bool(data.get("cleared", false))
	boss_spawned = bool(data.get("boss_spawned", false))
	enemies_remaining = maxi(int(data.get("enemies_remaining", 0)), 0)
	floor = clampi(int(data.get("floor", 1)), 1, DEEPEST_FLOOR)


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
