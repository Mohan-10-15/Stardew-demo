class_name FestivalData
extends Resource
## A one-day event in the physical valley, as data.
##
## A festival defers every villager's authored day to a shared gathering
## schedule, puts decorations in the square, and pays the player for attending.
## The consequence of skipping is missing the reward — no hidden penalty.

@export var id: StringName = &""
@export var display_name: String = ""
@export var season: int = 0
@export var day_of_month: int = 1
@export var location: StringName = &"village_square"
@export var description: String = ""
@export var reward_gold: int = 0
@export var reward_item: StringName = &""
@export var heart_reward: int = 1


func occurs_on(season_value: int, day_value: int) -> bool:
	return season_value == season and day_value == day_of_month


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and day_of_month >= 1 and day_of_month <= 28 \
		and season >= 0 and season <= 3 and reward_gold >= 0
