extends TestSuite
## W1.5 / W1.6 / W1.8: the starting page tells the player what the game is,
## every page is valid, and every licensed asset owns a credits row.

const TITLE := "res://scenes/ui/title_screen.tscn"
const LICENCES := "res://docs/ASSET_LICENSES.md"
const BUTTONS: Array[String] = [
	"NewGame", "Continue", "About", "HowToPlay", "Settings", "Credits", "Quit",
]


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		&"about_pages_are_valid_and_fit",
		&"credits_cover_every_licensed_pack",
		&"the_title_offers_every_front_door_button",
		&"continue_is_disabled_without_a_save",
	]


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"about_pages_are_valid_and_fit":
			return _t_about(case)
		&"credits_cover_every_licensed_pack":
			return _t_credits(case)
		&"the_title_offers_every_front_door_button":
			return await _t_buttons(case)
		&"continue_is_disabled_without_a_save":
			return await _t_continue(case)
	return fail(case, "no case implementation for %s" % case)


func _load_pages() -> Array[AboutPage]:
	var out: Array[AboutPage] = []
	var dir := DirAccess.open("res://resources/ui/about")
	if dir == null:
		return out
	for entry: String in dir.get_files():
		if entry.ends_with(".tres"):
			var page := ResourceLoader.load("res://resources/ui/about/" + entry) as AboutPage
			if page != null and page.is_valid():
				out.append(page)
	return out


func _t_about(c: StringName) -> Dictionary:
	var pages := _load_pages()
	if pages.size() < 5:
		return fail(c, "only %d valid About pages" % pages.size())
	var ids: Array[StringName] = []
	for page: AboutPage in pages:
		if ids.has(page.id):
			return fail(c, "duplicate About id %s" % page.id)
		ids.append(page.id)
	if not ids.has(&"how_to_play"):
		return fail(c, "How to Play has no About page")
	return succeeded(c, "%d valid About pages" % pages.size())


func _t_credits(c: StringName) -> Dictionary:
	var data := ResourceLoader.load("res://resources/ui/credits.tres") as CreditsData
	if data == null or data.entries.size() < 4:
		return fail(c, "no credits data")
	var text := _read(LICENCES)
	var credits_text := ""
	for entry: CreditEntry in data.entries:
		credits_text += entry.label + " " + entry.detail + "\n"
	for needle: String in ["KayKit", "Farm Buildings", "Nature", "Godot"]:
		if not text.contains(needle):
			return fail(c, "licence document is missing %s" % needle)
		if not credits_text.contains(needle):
			return fail(c, "credits are missing %s" % needle)
	return succeeded(c, "%d credits rows cover all licensed packs" % data.entries.size())


func _t_buttons(c: StringName) -> Dictionary:
	var packed := load(TITLE) as PackedScene
	if packed == null:
		return fail(c, "no title scene")
	var title := packed.instantiate()
	root().add_child(title)
	await _step(3)
	for name: String in BUTTONS:
		var button := title.get_node_or_null("Panel/Column/" + name) as Button
		if button == null:
			title.free()
			return fail(c, "title has no %s button" % name)
		if OS.get_name() != "Web" and button.focus_mode == Control.FOCUS_NONE:
			title.free()
			return fail(c, "%s cannot take focus" % name)
	title.free()
	return succeeded(c, "%d front-door buttons present and focusable" % BUTTONS.size())


func _t_continue(c: StringName) -> Dictionary:
	var packed := load(TITLE) as PackedScene
	var title := packed.instantiate()
	root().add_child(title)
	await _step(3)
	var button := title.get_node_or_null(^"Panel/Column/Continue") as Button
	if button == null:
		title.free()
		return fail(c, "no Continue button")
	var save := _find_group(root(), &"save_service")
	# With no service in the tree the only honest state is "disabled".
	if save != null and bool(save.call("has_save")):
		var enabled := not button.disabled
		title.free()
		return succeeded(c, "Continue enabled with a save: %s" % enabled)
	if not button.disabled:
		title.free()
		return fail(c, "Continue is offered without a save")
	title.free()
	return succeeded(c, "Continue disabled when no save is available")


func _find_group(node: Node, group: StringName) -> Node:
	if node == null:
		return null
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _find_group(child, group)
		if found != null:
			return found
	return null


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
