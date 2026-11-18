class_name EnemyData
extends Resource
## One mine enemy, as data. Bodies are the same CC0 KayKit rigs the villagers
## use, tinted into cave shades — no new pack, no licence question.

@export var id: StringName = &""
@export var display_name: String = ""
@export var model: String = ""
@export var tint: Color = Color.WHITE
@export var target_height: float = 1.8
@export var max_health: int = 60
@export var damage: int = 8
@export var speed: float = 2.2
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.4
@export var is_boss: bool = false
@export var gold_reward: int = 0
@export var ore_reward: StringName = &"iron_ore"


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and not model.is_empty() \
		and max_health > 0 and damage > 0 and speed > 0.0
