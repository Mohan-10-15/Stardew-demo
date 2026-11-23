extends SceneTree
## Writes resources/ui/credits.tres. Run:
##   Godot --headless --path . --script res://tools/generate_credits_data.gd
## The rows mirror docs/ASSET_LICENSES.md; a test asserts no pack is missing.

const OUTPUT := "res://resources/ui/credits.tres"

const ROWS: Array[Dictionary] = [
	{"label": "Hollowbrook Hollow", "detail": "An original game by the repository owner."},
	{"label": "Godot Engine 4.5", "detail": "MIT licence — https://godotengine.org"},
	{"label": "KayKit Adventurers Character Pack", "detail": "CC0 1.0 — https://kaylousberg.itch.io/kaykit-adventurers"},
	{"label": "Quaternius Farm Buildings Pack", "detail": "CC0 1.0 — https://quaternius.com/packs/farmbuildings.html"},
	{"label": "Quaternius Ultimate Nature Pack", "detail": "CC0 1.0 — https://quaternius.com/packs/ultimatenature.html"},
	{"label": "Original audio", "detail": "Synthesised in-engine by AudioSynth; no third-party sound files."},
	{"label": "Original art overlays", "detail": "Anime faces, toon materials, clouds and voxel textures generated in code."},
]


func _initialize() -> void:
	var data := CreditsData.new()
	data.title = "Credits"
	for spec: Dictionary in ROWS:
		var entry := CreditEntry.new()
		entry.label = String(spec["label"])
		entry.detail = String(spec["detail"])
		if not entry.is_valid():
			printerr("[generate_credits_data] invalid row")
			quit(1)
			return
		data.entries.append(entry)
	if ResourceSaver.save(data, OUTPUT) != OK:
		printerr("[generate_credits_data] failed")
		quit(1)
		return
	print("[generate_credits_data] wrote %d rows" % data.entries.size())
	quit(0)
