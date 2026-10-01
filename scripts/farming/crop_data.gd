class_name CropData
extends Resource
## What one kind of crop is: when it ripens, what it yields, what it sells for.
##
## Content, not logic. Adding a crop means adding a `.tres`; nothing in the
## codebase branches on a crop id, and the shop, the seed packet and the tooltip
## all read these fields. This is the "content is data" rule doing real work —
## see `docs/ARCHITECTURE.md` §5.
##
## Ripening is in whole days because the clock advances in 10-minute ticks and
## growth is evaluated once at midnight. Crops do not grow at noon.

## Stable identifier. Looked up by [CropRegistry]; never shown to the player.
@export var id: StringName = &""
## Player-facing name.
@export var display_name: String = "Crop"
## Which [enum WorldTime.Season]s this crop can be planted in. Empty means
## any season, which is how forageable wild crops are expressed.
@export var seasons: Array[int] = []
## Days in the ground before it can be harvested. Always at least 1, because a
## zero-day crop would be harvestable on the same tick it was planted.
@export_range(1, 56, 1) var days_to_grow: int = 4
## Smallest number of produce one harvest gives.
@export_range(1, 10, 1) var min_yield: int = 1
## Largest number of produce one harvest gives.
@export_range(1, 10, 1) var max_yield: int = 1
## Whether the plant stays in the ground after harvesting and keeps producing.
## Tomatoes regrow, beans regrow, turnips do not.
@export var regrows: bool = false
## Days before a regrowing crop can be harvested again.
@export_range(0, 56, 1) var regrow_days: int = 0
## What the general store charges for one seed.
@export_range(0, 10000, 1) var seed_price: int = 20
## What one unit of produce sells for at the shipping bin.
@export_range(0, 10000, 1) var sell_price: int = 35
## Tint of the mature plant, used by the tile mesh.
@export var ripe_color: Color = Color(0.36, 0.62, 0.31)
## Tint of the seedling, before it is harvestable.
@export var sprout_color: Color = Color(0.55, 0.72, 0.38)
## Relative scale of the sprout mesh at planting, ramping to full size at ripeness.
@export_range(0.05, 1.0, 0.01) var sprout_scale: float = 0.2


## Yield for one harvest.
##
## Deterministic when given a seeded generator, so a save loaded twice produces
## the same crops. Falls back to a generator seeded from [member id] so an
## unseeded call still varies between harvests rather than always returning the
## floor.
func roll_yield(rng: RandomNumberGenerator = null) -> int:
	var lo := mini(min_yield, max_yield)
	var hi := maxi(min_yield, max_yield)
	if hi <= lo:
		return lo
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash(String(id))
	return rng.randi_range(lo, hi)


## Whether this crop may be planted in [param season], a [enum WorldTime.Season].
func grows_in(season: int) -> bool:
	# An empty season list means "anywhere", which is how non-crops are declared.
	if seasons.is_empty():
		return true
	return seasons.has(posmod(season, Clock.SEASONS_PER_YEAR))


## A crop that says nothing about itself is a content bug, and the symptom would
## be a seed that plants a permanently invisible plant. Checked by the registry
## at load so it is reported once rather than every time the tile is drawn.
func is_valid() -> bool:
	if id.is_empty():
		return false
	if days_to_grow < 1:
		return false
	if min_yield < 1 or max_yield < 1:
		return false
	if regrows and regrow_days < 1:
		return false
	return true


## "4 days · sells for 35g · regrows"
func describe() -> String:
	var parts: Array[String] = ["%d days" % days_to_grow]
	parts.append("sells for %dg" % sell_price)
	if regrows:
		parts.append("regrows every %d days" % regrow_days)
	return " · ".join(parts)