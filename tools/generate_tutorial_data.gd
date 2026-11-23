extends SceneTree
## Writes the first-day tutorial steps. Run:
##   Godot --headless --path . --script res://tools/generate_tutorial_data.gd

const OUT := "res://resources/ui/tutorial/"
const SCRIPT := "res://resources/ui/tutorial_step.gd"

const STEPS: Array[Dictionary] = [
	{"id": &"move", "order": 0, "hint": "Walk around with {move}. The valley is yours to explore.",
	 "signal": &"footstep", "action": &""},
	{"id": &"look", "order": 1, "hint": "Look around with {look}. Aim at something to see what it can do.",
	 "signal": &"interactable_focused", "action": &""},
	{"id": &"interact", "order": 2, "hint": "Press {interact} to talk, pick up or open what you are aiming at.",
	 "signal": &"interaction_performed", "action": &""},
	{"id": &"hoe", "order": 3, "hint": "Select the hoe with {hotbar}. Your first tools are in the bag.",
	 "signal": &"", "action": &"hotbar_1"},
	{"id": &"till", "order": 4, "hint": "Use the hoe on the farm soil with {use}.",
	 "signal": &"soil_tilled", "action": &""},
	{"id": &"plant", "order": 5, "hint": "Select a seed packet and plant it with {use}.",
	 "signal": &"crop_planted", "action": &""},
	{"id": &"water", "order": 6, "hint": "Fill the can at the well, then water the seed with {use}.",
	 "signal": &"soil_watered", "action": &""},
	{"id": &"talk", "order": 7, "hint": "Say hello to a neighbour with {interact}.",
	 "signal": &"npc_talked", "action": &""},
	{"id": &"inventory", "order": 8, "hint": "Open your bag with {inventory}.",
	 "signal": &"", "action": &"inventory"},
	{"id": &"sleep", "order": 9, "hint": "Rest at the end of the day. A new morning brings new growth.",
	 "signal": &"day_started", "action": &""},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script := load(SCRIPT) as GDScript
	var errors := 0
	for spec: Dictionary in STEPS:
		var step: Object = script.new()
		step.set("id", spec["id"])
		step.set("hint", spec["hint"])
		step.set("completion_signal", spec["signal"])
		step.set("completion_action", StringName(String(spec["action"])))
		step.set("order", int(spec["order"]))
		if not bool(step.call("is_valid")):
			errors += 1
			continue
		if ResourceSaver.save(step, "%s%s.tres" % [OUT, spec["id"]]) != OK:
			errors += 1
	print("[generate_tutorial_data] wrote %d steps" % STEPS.size())
	quit(1 if errors > 0 else 0)
