class_name BalanceReport
extends RefCounted
## The GDScript side of the C# balance sweep: turns the content the game already
## ships into the flat arrays `BalanceSweep.Run` takes, and hands back the report.
##
## This file exists because the two halves of the boundary have to be owned by
## whoever can read them. `scripts/sim/BalanceSweep.cs` knows how to run a nested
## parameter sweep cheaply and knows nothing about `CropData` or `ItemDefinition`;
## this file knows the content schema and nothing about loops. The wire between
## them is twelve flat arrays and a dictionary, all marshalled in a single call —
## see `docs/MULTI_LANGUAGE_ARCHITECTURE.md` for why the boundary is shaped that
## way and for the measurement that put the sweep on the C# side at all.
##
## The numbers themselves are never written here. Every crop value comes from
## `resources/farming/crops/*.tres` through [CropRegistry], every tool gate from
## `resources/*/items/*.tres` through [ItemRegistry], and the calendar from
## [Clock]. Rebalancing a crop is editing a `.tres`; this file does not need to
## change, which is the "content is data" rule applied to a balance model.

## Where the sweep lives. Loaded by path rather than by global class name so a
## missing or unbuilt assembly reports as a failed sweep instead of failing to
## compile every script that reaches this one.
const SWEEP_SCRIPT := "res://scripts/sim/BalanceSweep.cs"

## Two years: a full rotation of all four seasons twice, which is long enough for
## a regrower to prove itself and short enough that a test runs it fast.
const YEARS := 2

## What a new player starts with.
const START_GOLD := 500

## Tool tiers below 1 are the starter tools handed over for free — the hoe and the
## watering can have no `buy_price` and no `tool_tier`. Only purchasable tiers
## become gates.
const FIRST_PAID_TIER := 1


## Runs the sweep over the real crop and tool content.
##
## Returns the report dictionary straight from `BalanceSweep`, plus a `reason`
## key when the sweep could not be started at all. Callers should check `ok`
## before reading anything else.
static func sweep() -> Dictionary:
	var script := load(SWEEP_SCRIPT) as Script
	if script == null or not script.can_instantiate():
		return {
			"ok": false,
			"reason": "BalanceSweep could not be instantiated. Build the C# project first: dotnet build Hollowbrook.csproj",
		}

	var crops := CropRegistry.all_crops()
	if crops.is_empty():
		return {"ok": false, "reason": "no crops loaded"}

	var seed_cost := PackedFloat32Array()
	var sell_price := PackedFloat32Array()
	var yield_avg := PackedFloat32Array()
	var days_to_grow := PackedInt32Array()
	var regrow_days := PackedInt32Array()
	var regrows := PackedInt32Array()
	var season_mask := PackedInt32Array()

	for crop: CropData in crops:
		seed_cost.append(float(crop.seed_price))
		sell_price.append(float(crop.sell_price))
		yield_avg.append(float(crop.min_yield + crop.max_yield) * 0.5)
		days_to_grow.append(crop.days_to_grow)
		regrow_days.append(crop.regrow_days)
		regrows.append(1 if crop.regrows else 0)
		season_mask.append(_mask_for(crop))

	var sweep_node: Object = script.new()
	var report: Dictionary = sweep_node.call(
		"Run",
		Clock.DAYS_PER_YEAR * YEARS,
		Clock.DAYS_PER_SEASON,
		START_GOLD,
		farm_plot_count(),
		seed_cost,
		sell_price,
		yield_avg,
		days_to_grow,
		regrow_days,
		regrows,
		season_mask,
		tool_gates()
	)
	if report is Dictionary:
		report["crop_ids"] = _ids_of(crops)
	return report if report is Dictionary else {"ok": false, "reason": "sweep returned nothing"}


## The day a given tool tier became affordable under [param strategy_id], or -1.
##
## Takes the strategy's `id` from the report (one of `BestPerDay`, `BestMargin`,
## `Cheapest`, `WorstPerDay`) rather than an index, because an index into the
## strategies array silently changes meaning when a strategy is added.
static func gate_day(report: Dictionary, strategy_id: String, tier_index: int) -> int:
	for entry: Dictionary in report.get("strategies", []):
		if String(entry.get("id", "")) != strategy_id:
			continue
		var days := entry.get("tool_days", []) as Array
		if tier_index < 0 or tier_index >= days.size():
			return -1
		return int(days[tier_index])
	return -1


## End gold for one strategy, by its `id`. 0.0 when the strategy is not in the
## report, which is the same as "made nothing" and only reachable by a typo —
## so callers that care should assert the strategy list first.
static func gold_of(report: Dictionary, strategy_id: String) -> float:
	for entry: Dictionary in report.get("strategies", []):
		if String(entry.get("id", "")) == strategy_id:
			return float(entry.get("end_gold", 0.0))
	return 0.0


## One affordability gate per purchasable tool tier, ascending: every tool that
## shares a tier costs the same in the shipped content, so the gate for a tier is
## what a player must be able to spend to clear it in one go (an axe *and* a
## pickaxe, not either).
##
## Tiers with no purchasable tool are skipped rather than entering as 0, because
## a zero-cost gate would report "bought on day 0" and mean nothing.
static func tool_gates() -> PackedFloat32Array:
	var per_tier := {}
	for item: ItemDefinition in ItemRegistry.all_items():
		if item.category != ItemDefinition.Category.TOOL:
			continue
		if item.tool_tier < FIRST_PAID_TIER:
			continue
		if item.buy_price <= 0:
			continue
		per_tier[item.tool_tier] = float(per_tier.get(item.tool_tier, 0.0)) + float(item.buy_price)

	var tiers := per_tier.keys()
	tiers.sort()
	var gates := PackedFloat32Array()
	for tier: int in tiers:
		gates.append(float(per_tier[tier]))
	return gates


## How many soil tiles the farm actually has.
##
## Read off an unattached [FarmGrid] rather than typed in, so the sweep re-runs at
## the real plot size the moment someone widens the field. The node is never added
## to the tree, so `_build()` does not run and no tiles are created.
static func farm_plot_count() -> int:
	var grid := FarmGrid.new()
	var count := grid.columns * grid.rows
	grid.free()
	return count


## `CropData.seasons` is a list of [enum WorldTime.Season] values; the sweep takes
## a bitmask. An empty list means "any season" — the wildcard the registry
## documents for forageable wild crops — and becomes all four bits.
static func _mask_for(crop: CropData) -> int:
	if crop.seasons.is_empty():
		return 0xF
	var mask := 0
	for season: int in crop.seasons:
		if season >= 0 and season < Clock.SEASONS_PER_YEAR:
			mask |= 1 << season
	return mask


static func _ids_of(crops: Array[CropData]) -> Array[String]:
	var out: Array[String] = []
	for crop: CropData in crops:
		out.append(String(crop.id))
	return out
