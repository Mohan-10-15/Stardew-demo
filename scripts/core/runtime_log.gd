class_name RuntimeLog
extends RefCounted
## The [Log] autoload, fetched at runtime instead of named at compile time.
##
## ## Why this exists
##
## [code]Log[/code] is an autoload, and in a [code]--script[/code] run the script
## compiles **before** autoloads register. Writing [code]Log.info(...)[/code] anywhere a
## tool's dependency chain can reach is therefore a compile error, not a warning —
## [code]Identifier not found: Log[/code], and the tool never runs.
##
## The documented workaround in `AGENTS.md` is to fetch the node by name from the tree
## root, which is right for an instance method ([method Engine.get_main_loop] is how
## every service here already finds a sibling). It does not reach a **static** registry:
## [ItemRegistry], [CropRegistry] and their siblings are static, content-only and have no
## instance to hang the lookup off, so they had nowhere to put it and quietly became
## unloadable from any tool.
##
## That is not hypothetical. `tools/generate_npc_data.gd` has been broken on `master`:
## [code]NpcData[/code] reaches [ItemRegistry] and [CropRegistry] for its gift rules,
## those registries name [code]Log[/code], and the generator could not compile. The
## generator is the documented way to author villagers, so the fix belongs here rather
## than in a workaround nobody would find.
##
## Silently dropping the message when there is no logger is the point: a tool run has no
## [Log] node, and a tool that cannot print should not fail because of it. Tools that
## want output use [method @GlobalScope.printerr] directly, which is what every
## [code]tools/[/code] script already does.

static func _node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null(^"Log")
	return null


static func info(tag: String, message: String) -> void:
	var node := _node()
	if node != null:
		node.call("info", tag, message)


static func warn(tag: String, message: String) -> void:
	var node := _node()
	if node != null:
		node.call("warn", tag, message)


static func error(tag: String, message: String) -> void:
	var node := _node()
	if node != null:
		node.call("error", tag, message)