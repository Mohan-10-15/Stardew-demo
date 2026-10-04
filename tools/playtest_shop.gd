extends SceneTree
## Plays the shop the way a keyboard player does, and photographs it.
##
## The unit tests in `tests/suites/test_ui.gd` prove the panel's logic: the highlight
## moves, Enter trades, E closes. They cannot photograph it, and the question that
## started this work was a *look* question — "the shop is mouse-only" is a complaint
## about what is on the screen, so the screen has to be looked at.
##
## Nothing here calls `Shop.open` or `Shop.buy`. The player is walked to the counter,
## the crosshair is aimed by the real interaction probe, and the shop is opened by the
## real `E` press, then driven with real key events through the same
## `_unhandled_input` a player's keyboard reaches.
##
## Run:
##   & "tools/Godot_v4.5-stable_win64_console.exe" --path . --script res://tools/playtest_shop.gd

const SHOTS := "res://art_review_shop"


func _initialize() -> void:
	print("[play] booting the real main scene")
	var packed := load("res://scenes/core/main.tscn") as PackedScene
	if packed == null:
		print("[play] FAIL no main scene")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _until(func() -> bool: return _is_playing(main), 240)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _step(20)

	var player := _find(main, "Player")
	var probe := _find(main, "InteractionProbe")
	var shop := _find(main, "GeneralStore")
	var counter := _find(main, "ShopInteractable")
	if player == null or probe == null or shop == null or counter == null:
		print("[play] FAIL player=%s probe=%s shop=%s counter=%s"
			% [player, probe, shop, counter])
		quit(1)
		return
	print("[play] found the counter; walking to it")

	# Stand in front of the counter, aim by the vector from the camera to the aim
	# point, and pitch with the sign the camera itself uses. Guessing a heading would
	# pass or fail on the world's rotation, not on the shop.
	var aim: Vector3 = counter.call("get_aim_point")
	player.global_position = Vector3(aim.x, 0.2, aim.z + 1.5)
	await _step(10)
	var camera: Camera3D = probe.call("get_camera")
	var dir := (aim - camera.global_position).normalized()
	player.call("set_yaw", atan2(-dir.x, -dir.z))
	player.get("camera_rig").call("set_pitch",
		atan2(dir.y, Vector2(dir.x, dir.z).length()))
	await _step(8)
	probe.call("update_focus")
	await _step(4)
	if probe.call("get_focus") == null:
		print("[play] FAIL the crosshair never focused the counter")
		quit(1)
		return
	print("[play] crosshair on the counter; the plus is drawn over it")
	await _shot("%s_01_counter.png" % SHOTS)

	# Open it the way the player does.
	await _tap(KEY_E)
	await _step(8)
	var panel := _find(main, "ShopUI")
	if panel == null or not panel.visible:
		print("[play] FAIL E at the counter did not open the panel")
		quit(1)
		return
	print("[play] opened with E; the pause overlay is up behind it")
	await _shot("%s_02_open.png" % SHOTS)

	# W moves the highlight *up*, so from the top row it wraps to the bottom. The
	# screenshot is the point: this is the thing that was not visible before.
	var before: Dictionary = panel.call("selected_entry")
	await _tap(KEY_W)
	await _step(4)
	var after: Dictionary = panel.call("selected_entry")
	print("[play] W: '%s' -> '%s'" % [
		str(before.get("item_id", "")), str(after.get("item_id", "")),
	])
	await _shot("%s_03_wrapped.png" % SHOTS)

	# Two rows up from there, with the arrow keys this time, so both spellings are seen.
	await _tap(KEY_UP)
	await _step(4)
	print("[play] up arrow: now on '%s'"
		% str((panel.call("selected_entry") as Dictionary).get("item_id", "")))
	await _shot("%s_04_arrows.png" % SHOTS)

	# Buy with Enter and check both halves of the trade, and that the highlight stays
	# put. A highlight that jumps back to the top after a purchase makes Enter useless
	# for buying three packets, and no screenshot of a single purchase would show it.
	#
	# The row is chosen by *reading the price off the screen*, the way a player does,
	# rather than by knowing the content. That matters: the first attempt at this
	# confirmed whatever row the arrows happened to leave on, which was a steel axe at
	# 1000g with 500g in the wallet. The refusal was correct — and invisible in a log
	# that only printed gold, which is how a correct refusal looks like a broken panel.
	var state := _find(main, "PlayerState")
	var gold: int = state.get("wallet").gold
	var target := &""
	for _i: int in range(40):
		var entry: Dictionary = panel.call("selected_entry")
		var price := _price_on_screen(panel, entry)
		if StringName(entry.get("kind", &"")) == &"buy" and price <= gold:
			target = StringName(entry.get("item_id", ""))
			break
		await _tap(KEY_S)
		await _step(4)
	if String(target).is_empty():
		print("[play] FAIL nothing on the panel is affordable with %dg" % gold)
		quit(1)
		return

	var gold_before: int = state.get("wallet").gold
	await _tap(KEY_ENTER)
	await _step(8)
	var gold_after: int = state.get("wallet").gold
	var bag: int = state.get("inventory").count(target)
	var still: Dictionary = panel.call("selected_entry")
	print("[play] Enter on '%s': %dg -> %dg, bag has %d, still on '%s'"
		% [target, gold_before, gold_after, bag, str(still.get("item_id", ""))])
	print("[play] the panel says: %s" % _message_on_screen(panel))
	await _shot("%s_05_bought.png" % SHOTS)

	if gold_after >= gold_before:
		print("[play] FAIL Enter on the highlighted row bought nothing")
		quit(1)
		return
	if bag < 1:
		print("[play] FAIL the player was charged and got nothing")
		quit(1)
		return
	if StringName(still.get("item_id", &"")) != target:
		print("[play] FAIL the highlight jumped off '%s' after the purchase" % target)
		quit(1)
		return

	# E again closes. If it bought instead, the player is charged twice per visit.
	await _tap(KEY_E)
	await _step(8)
	if panel.visible:
		print("[play] FAIL E did not close the shop")
		quit(1)
		return
	print("[play] E closed it. OK")
	await _shot("%s_06_closed.png" % SHOTS)
	quit(0)


# --- plumbing ----------------------------------------------------------------


## The price the panel is showing for [param entry], in gold, or -1 if it shows none.
##
## Read off the row's own label rather than looked up in the content, because the
## question a playtest asks is "can a player tell what this costs by looking", and
## asking the content instead would answer a different question that always says yes.
func _price_on_screen(panel: Node, entry: Dictionary) -> int:
	var row: Node = entry.get("row")
	if row == null or not is_instance_valid(row):
		return -1
	for label in _labels(row):
		var text: String = label.text
		if text.ends_with("g") and text.substr(0, text.length() - 1).is_valid_int():
			return text.substr(0, text.length() - 1).to_int()
	return -1


## Everything the panel says underneath the rows.
func _message_on_screen(panel: Node) -> String:
	var message := panel.get_node_or_null(^"Center/Panel/Column/Message") as Label
	return "" if message == null else message.text


func _labels(from: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child in from.get_children():
		if child is Label:
			found.append(child)
		found.append_array(_labels(child))
	return found


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _until(predicate: Callable, limit: int) -> void:
	for _i: int in range(limit):
		if predicate.call():
			return
		await process_frame
	await process_frame


func _is_playing(main: Node) -> bool:
	return main.is_inside_tree()


func _tap(code: int) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("[play] no image for %s" % path)
		return
	var err := image.save_png(path)
	print("[play] %s %s (%dx%d)" % [
		"wrote" if err == OK else "FAILED to write", path,
		image.get_width(), image.get_height(),
	])


func _find(from: Node, want: String) -> Node:
	if from == null:
		return null
	if from.name == want:
		return from
	for child in from.get_children():
		var hit := _find(child, want)
		if hit != null:
			return hit
	return null