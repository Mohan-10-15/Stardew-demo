extends TestSuite
## W2.7: the content graph is coherent — every referenced id exists. This is
## the "some logic" deliverable made checkable rather than asserted in prose.

func get_cases() -> Array[StringName]:
	return [&"the_content_graph_has_no_dangling_ids",
		&"the_graph_is_large_enough_to_mean_something"]


func _run(case: StringName) -> Dictionary:
	var report := WorldLogicValidator.validate()
	match case:
		&"the_content_graph_has_no_dangling_ids":
			var errors: Array = report.get("errors", [])
			if not errors.is_empty():
				return fail(case, "%d dangling ids: %s" % [
					errors.size(), str(errors.slice(0, 3)),
				])
			return succeeded(case, "0 dangling ids")
		&"the_graph_is_large_enough_to_mean_something":
			var nodes: int = int(report.get("nodes", 0))
			var edges: int = int(report.get("edges", 0))
			if nodes < 30 or edges < 100:
				return fail(case, "only %d nodes / %d edges" % [nodes, edges])
			return succeeded(case, "%d nodes, %d edges checked" % [nodes, edges])
	return fail(case, "no case implementation for %s" % case)
