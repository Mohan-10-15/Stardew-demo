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

## Scene path of the model drawn while the plant is a seedling.
##
## Art, not balance — the numbers above are the crop's *rules*, and a designer
## should be able to change its silhouette without touching when it ripens or what
## it yields. Empty means "no model for this stage", and [SoilTile] draws the
## procedural cylinder instead, so content added without art still works.
@export_file("*.fbx") var sprout_model: String = ""
## Scene path of the model drawn once the plant is past the halfway mark.
##
## The Quaternius nature pack ships no seedling models and no per-day growth
## stages, so the two-stage swap is the honest amount of stage information these
## assets actually carry. Silhouette change rather than a coloured cylinder
## growing is what makes progress legible from a standing height.
@export_file("*.fbx") var mature_model: String = ""
## Height in metres the mature model is drawn at, on a 2 m tile.
##
## Models are authored at wildly different natural sizes — `Corn_1` is 1.98 m and
## `Plant_4` is 0.81 m — so the tile scales each one to this height instead of
## dropping them in at native size. The tile's own extent still scales it, so this
## holds relative to the plot rather than to absolute metres.
@export_range(0.1, 3.0, 0.05) var model_height: float = 1.1


## Whether this crop has a real model for both stages.
##
## Half-configured art is a content bug: a crop with a mature model but no sprout
## model would jump from a coloured cylinder straight to full geometry halfway
## through the season, which reads as a glitch rather than as growth. Checked by
## [method is_valid] so it is reported once at load.
func has_model_art() -> bool:
	return not sprout_model.is_empty() and not mature_model.is_empty()


## The model to draw at [param planted_fraction] growth, or `""` if this crop has
## no art.
##
## Split at the halfway mark rather than per-day: the pack has exactly two usable
## plant silhouettes per crop, and a daily crossover would just alternate between
## them.
func stage_model(planted_fraction: float) -> String:
	if not has_model_art():
		return ""
	return sprout_model if planted_fraction < 0.5 else mature_model


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
	# Art is optional, but half of it is a mistake worth naming.
	if sprout_model.is_empty() != mature_model.is_empty():
		return false
	return true


## "4 days · sells for 35g · regrows"
func describe() -> String:
	var parts: Array[String] = ["%d days" % days_to_grow]
	parts.append("sells for %dg" % sell_price)
	if regrows:
		parts.append("regrows every %d days" % regrow_days)
	return " · ".join(parts)