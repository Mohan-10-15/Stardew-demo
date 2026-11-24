class_name JuiceService
extends Node
## W5.4: owns trauma and the brief hit-stop. Every effect respects the
## accessibility settings, and 0 % shake / off switches produce exactly zero
## added motion rather than a smaller version of it.

signal shaken(amount: float)

var trauma: float = 0.0
var hit_stop_left: float = 0.0
var _time: float = 0.0
var _normal_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_normal_scale = Engine.time_scale


func _exit_tree() -> void:
	Engine.time_scale = _normal_scale


func _process(delta: float) -> void:
	_time += delta
	trauma = Juice.decay_trauma(trauma, delta)
	if hit_stop_left > 0.0:
		hit_stop_left -= delta
		if hit_stop_left <= 0.0:
			hit_stop_left = 0.0
			Engine.time_scale = _normal_scale


static func find(start: Node) -> JuiceService:
	if start == null:
		return null
	if start is JuiceService:
		return start as JuiceService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)
	var applied := Juice.shake_from_trauma(trauma, Config.settings.screen_shake)
	if applied > 0.0:
		shaken.emit(applied)


## Deterministic two-axis shake; the camera adds this as a small offset.
func shake_offset() -> Vector2:
	var amount := Juice.shake_from_trauma(trauma, Config.settings.screen_shake)
	if amount <= 0.0:
		return Vector2.ZERO
	return Vector2(
		sin(_time * 47.0) * amount * 0.12,
		sin(_time * 61.0 + 1.7) * amount * 0.10
	)


func hit_stop(strength: float) -> void:
	var seconds := Juice.hit_stop_seconds(strength, Config.settings.hit_stop)
	if seconds <= 0.0:
		return
	hit_stop_left = seconds
	Engine.time_scale = 0.05
