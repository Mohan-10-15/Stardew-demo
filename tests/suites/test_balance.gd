extends TestSuite
## The balance sweep: does the crop table the game ships actually progress a
## player from broke to the copper tool gate, no matter which crop they plant?
##
## This is the one place the C# half of the project is exercised. Everything
## asserted here is derived from `resources/farming/crops/*.tres` and
## `resources/*/items/*.tres`, so a crop rebalance that makes the worst option
## unplayable fails here rather than in a player's hands.
##
## ## Why the first two cases exist
##
## The sweep is the only system that lives behind a language boundary. If the
## build stage in `tools/check.ps1` regresses, or the assembly name drifts from
## `dotnet/project/assembly_name`, the failure mode is *not* an exception â€” it is
## `BalanceSweep` silently being unloadable, and every balance assertion below
## would then skip. The first case therefore asserts the boundary itself, with a
## message naming the command that fixes it.

const SWEEP_SCRIPT := "res://scripts/sim/BalanceSweep.cs"


func get_cases() -> Array[StringName]:
	return [
		&"the_csharp_sweep_is_buildable_and_loadable",
		&"the_sweep_runs_on_the_shipped_crop_table",
		&"every_shipped_crop_enters_the_sweep",
		&"every_strategy_reports_an_end_balance",
		&"the_tool_gates_are_ascending_and_positive",
		&"the_second_tool_gate_is_reachable_in_two_years",
		&"the_worst_profitable_crop_also_reaches_the_gate",
		&"the_best_crop_is_never_worse_than_the_worst",
		&"the_gate_is_never_later_for_the_best_crop",
		&"a_strategy_never_spends_more_than_it_grosses",
		&"the_widest_gate_spread_is_reported",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"the_csharp_sweep_is_buildable_and_loadable":
			return _t_boundary()
		&"the_sweep_runs_on_the_shipped_crop_table":
			return _t_runs()
		&"every_shipped_crop_enters_the_sweep":
			return _t_every_crop_enters()
		&"every_strategy_reports_an_end_balance":
			return _t_every_strategy_reports()
		&"the_tool_gates_are_ascending_and_positive":
			return _t_gates_ascending()
		&"the_second_tool_gate_is_reachable_in_two_years":
			return _t_gate_reachable()
		&"the_worst_profitable_crop_also_reaches_the_gate":
			return _t_worst_reaches_gate()
		&"the_best_crop_is_never_worse_than_the_worst":
			return _t_best_beats_worst()
		&"the_gate_is_never_later_for_the_best_crop":
			return _t_gate_ordering()
		&"a_strategy_never_spends_more_than_it_grosses":
			return _t_spending_within_income()
		&"the_widest_gate_spread_is_reported":
			return _t_spread_reported()
	return fail(case, "no such case")


## The boundary itself. `can_instantiate()` is false when the assembly is missing
## or its name no longer matches `dotnet/project/assembly_name`, which is exactly
## the failure that would otherwise make every case below silently trivial.
func _t_boundary() -> Dictionary:
	var script := load(SWEEP_SCRIPT) as Script
	if script == null:
		return fail(&"the_csharp_sweep_is_buildable_and_loadable",
			"%s could not be loaded. Run: dotnet build Hollowbrook.csproj" % SWEEP_SCRIPT)
	if not script.can_instantiate():
		return fail(&"the_csharp_sweep_is_buildable_and_loadable",
			"BalanceSweep is present but not instantiable - the C# project is stale or unbuilt. Run: dotnet build Hollowbrook.csproj")
	return succeeded(&"the_csharp_sweep_is_buildable_and_loadable")


func _t_runs() -> Dictionary:
	var report := BalanceReport.sweep()
	if not bool(report.get("ok", false)):
		return fail(&"the_sweep_runs_on_the_shipped_crop_table",
			"sweep refused: %s" % String(report.get("reason", "unknown")))
	if int(report.get("days", 0)) != Clock.DAYS_PER_YEAR * BalanceReport.YEARS:
		return fail(&"the_sweep_runs_on_the_shipped_crop_table",
			"sweep ran for %d days, expected %d" % [
				int(report.get("days", 0)), Clock.DAYS_PER_YEAR * BalanceReport.YEARS])
	return succeeded(&"the_sweep_runs_on_the_shipped_crop_table",
		"%d crops over %d days" % [int(report.get("crop_count", 0)), int(report.get("days", 0))])


func _t_every_crop_enters() -> Dictionary:
	var report := BalanceReport.sweep()
	if not bool(report.get("ok", false)):
		return fail(&"every_shipped_crop_enters_the_sweep", String(report.get("reason", "")))
	var shipped := CropRegistry.all_crops().size()
	var swept := int(report.get("crop_count", -1))
	if swept != shipped:
		return fail(&"every_shipped_crop_enters_the_sweep",
			"swept %d of %d crops" % [swept, shipped])
	return succeeded(&"every_shipped_crop_enters_the_sweep", "%d crops" % swept)


func _t_every_strategy_reports() -> Dictionary:
	var report := BalanceReport.sweep()
	var strategies: Array = report.get("strategies", [])
	if strategies.size() != 4:
		return fail(&"every_strategy_reports_an_end_balance",
			"expected 4 strategies, got %d" % strategies.size())
	for entry: Dictionary in strategies:
		var id := String(entry.get("id", "?"))
		if not entry.has("end_gold") or not entry.has("gross") or not entry.has("tool_days"):
			return fail(&"every_strategy_reports_an_end_balance", "%s is missing a field" % id)
	return succeeded(&"every_strategy_reports_an_end_balance",
		"4 strategies: %s" % ", ".join(_strategy_ids(report)))


func _t_gates_ascending() -> Dictionary:
	var gates := BalanceReport.tool_gates()
	if gates.is_empty():
		return fail(&"the_tool_gates_are_ascending_and_positive",
			"no purchasable tool tiers found; check ItemDefinition.tool_tier and buy_price")
	var previous := -1.0
	for gate: float in gates:
		if gate <= 0.0:
			return fail(&"the_tool_gates_are_ascending_and_positive", "gate of %s is not positive" % str(gate))
		if gate < previous:
			return fail(&"the_tool_gates_are_ascending_and_positive",
				"gates are not ascending: %s follows %s" % [str(gate), str(previous)])
		previous = gate
	return succeeded(&"the_tool_gates_are_ascending_and_positive",
		"gates: %s" % str(gates))


func _t_gate_reachable() -> Dictionary:
	var report := BalanceReport.sweep()
	if not bool(report.get("ok", false)):
		return fail(&"the_second_tool_gate_is_reachable_in_two_years", String(report.get("reason", "")))
	for id: String in _strategy_ids(report):
		var day := BalanceReport.gate_day(report, id, 1)
		if day < 0:
			return fail(&"the_second_tool_gate_is_reachable_in_two_years",
				"%s never afforded the second tool gate in %d days" % [id, int(report.get("days", 0))])
		if day >= int(report.get("days", 0)):
			return fail(&"the_second_tool_gate_is_reachable_in_two_years",
				"%s needed %d days, past the horizon" % [id, day])
	return succeeded(&"the_second_tool_gate_is_reachable_in_two_years")


func _t_worst_reaches_gate() -> Dictionary:
	var report := BalanceReport.sweep()
	if not bool(report.get("ok", false)):
		return fail(&"the_worst_profitable_crop_also_reaches_the_gate", String(report.get("reason", "")))
	var day := BalanceReport.gate_day(report, "WorstPerDay", 1)
	if day < 0:
		return fail(&"the_worst_profitable_crop_also_reaches_the_gate",
			"the worst profitable crop never reaches the second tool gate - planting is not a viable income floor")
	return succeeded(&"the_worst_profitable_crop_also_reaches_the_gate", "day %d" % day)


func _t_best_beats_worst() -> Dictionary:
	var report := BalanceReport.sweep()
	var best := BalanceReport.gold_of(report, "BestPerDay")
	var worst := BalanceReport.gold_of(report, "WorstPerDay")
	if best < worst:
		return fail(&"the_best_crop_is_never_worse_than_the_worst",
			"BestPerDay ended with %s, WorstPerDay with %s" % [str(best), str(worst)])
	return succeeded(&"the_best_crop_is_never_worse_than_the_worst",
		"best %s vs worst %s" % [str(best), str(worst)])


func _t_gate_ordering() -> Dictionary:
	var report := BalanceReport.sweep()
	var best := BalanceReport.gate_day(report, "BestPerDay", 1)
	var worst := BalanceReport.gate_day(report, "WorstPerDay", 1)
	if best < 0 or worst < 0:
		return fail(&"the_gate_is_never_later_for_the_best_crop",
			"gate day missing (best %d, worst %d)" % [best, worst])
	if best > worst:
		return fail(&"the_gate_is_never_later_for_the_best_crop",
			"BestPerDay reached the gate on day %d, WorstPerDay on %d" % [best, worst])
	return succeeded(&"the_gate_is_never_later_for_the_best_crop", "best %d, worst %d" % [best, worst])


func _t_spending_within_income() -> Dictionary:
	var report := BalanceReport.sweep()
	for entry: Dictionary in report.get("strategies", []):
		var gross := float(entry.get("gross", 0.0))
		var spend := float(entry.get("seed_spend", 0.0))
		if spend > gross:
			return fail(&"a_strategy_never_spends_more_than_it_grosses",
				"%s spent %s on seed but grossed %s" % [String(entry.get("id", "?")), str(spend), str(gross)])
	return succeeded(&"a_strategy_never_spends_more_than_it_grosses")


func _t_spread_reported() -> Dictionary:
	var report := BalanceReport.sweep()
	var fastest := int(report.get("fastest_tier2_day", -1))
	var slowest := int(report.get("slowest_tier2_day", -1))
	if fastest < 0 or slowest < 0:
		return fail(&"the_widest_gate_spread_is_reported",
			"spread not computed (fastest %d, slowest %d)" % [fastest, slowest])
	if fastest > slowest:
		return fail(&"the_widest_gate_spread_is_reported",
			"fastest %d is later than slowest %d" % [fastest, slowest])
	return succeeded(&"the_widest_gate_spread_is_reported", "day %d .. day %d" % [fastest, slowest])


func _strategy_ids(report: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in report.get("strategies", []):
		out.append(String(entry.get("id", "?")))
	return out
