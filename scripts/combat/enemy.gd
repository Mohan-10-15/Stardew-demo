class_name Enemy
extends CharacterBody3D
## A mine enemy: chase, strike, react, die. All outcomes are reported to the
## CombatService through EventBus; this body never touches the player's wallet
## or the save file.

var data: EnemyData = null
var health: int = 0
var _cooldown: float = 0.0
var _model: Node3D = null
var _service: Node = null


func setup(definition: EnemyData, service: Node) -> void:
	data = definition
	_service = service
	health = definition.max_health
	_collider()
	_build_model()


func _collider() -> void:
	collision_layer = 1 << 5
	collision_mask = 1
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = body_height()
	shape.shape = capsule
	shape.position = Vector3(0, body_height() * 0.5, 0)
	add_child(shape)


func body_height() -> float:
	return data.target_height if data != null else 1.8


func _build_model() -> void:
	if data == null:
		return
	_model = ModelArt.instantiate_standing(data.model, data.target_height)
	if _model == null:
		return
	_model.name = "Model"
	ModelArt.strip_attachments(_model)
	if not ModelArt.is_white(data.tint):
		ModelArt.apply_tint(_model, data.tint)
	add_child(_model)


func _physics_process(delta: float) -> void:
	if data == null or health <= 0 or _service == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var player: Node3D = _service.get("player")
	if player == null:
		return
	var to := Vector2(
		player.global_position.x - global_position.x,
		player.global_position.z - global_position.z
	)
	var distance := to.length()
	if distance > 14.0:
		return
	if distance > data.attack_range:
		var direction := to / maxf(distance, 0.001)
		velocity.x = direction.x * data.speed
		velocity.z = direction.y * data.speed
		var yaw := atan2(-direction.x, -direction.y)
		rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 6.0))
	else:
		velocity.x = move_toward(velocity.x, 0.0, data.speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, data.speed * 4.0 * delta)
		if _cooldown <= 0.0:
			_cooldown = data.attack_cooldown
			_service.call("enemy_attacks", self)
	velocity.y -= 24.0 * delta
	move_and_slide()


## Returns true when this blow killed the enemy.
func take_damage(amount: int) -> bool:
	if health <= 0:
		return false
	health = maxi(0, health - maxi(amount, 0))
	if health == 0:
		collision_layer = 0
		if _model != null:
			_model.visible = false
		return true
	return false
