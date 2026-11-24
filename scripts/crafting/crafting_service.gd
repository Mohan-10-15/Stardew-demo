class_name CraftingService
extends Node
## Turns bag contents into other bag contents. The rules are Recipe resources;
## this node only checks, removes and adds, then publishes one of two events.

const SERVICE_GROUP := &"crafting_service"
const DIR := "res://resources/crafting/recipes/"

static var _recipes: Dictionary = {}


static func find(start: Node) -> CraftingService:
	if start == null:
		return null
	if start is CraftingService:
		return start as CraftingService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


static func all_recipes() -> Array[Recipe]:
	ensure_loaded()
	var out: Array[Recipe] = []
	for item: Variant in _recipes.values():
		if item is Recipe:
			out.append(item)
	out.sort_custom(func(a: Recipe, b: Recipe) -> bool: return String(a.id) < String(b.id))
	return out


static func recipe_for(id: StringName) -> Recipe:
	ensure_loaded()
	return _recipes.get(id) as Recipe


static func clear_cache() -> void:
	_recipes.clear()


static func ensure_loaded() -> void:
	if not _recipes.is_empty():
		return
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if ResourceFiles.is_resource(entry):
			var recipe := ResourceLoader.load(ResourceFiles.path_for(DIR, entry)) as Recipe
			if recipe != null and recipe.is_valid():
				_recipes[recipe.id] = recipe
		entry = dir.get_next()
	dir.list_dir_end()


func _ready() -> void:
	add_to_group(SERVICE_GROUP)


func can_craft(recipe_id: StringName) -> StringName:
	var recipe := recipe_for(recipe_id)
	if recipe == null:
		return &"no_recipe"
	var bag := _bag()
	if bag == null:
		return &"no_player_state"
	for id: Variant in recipe.ingredients:
		var need := int(recipe.ingredients[id])
		if int(bag.call("count", StringName(str(id)))) < need:
			return &"missing_ingredients"
	return &""


func craft(recipe_id: StringName) -> bool:
	var reason := can_craft(recipe_id)
	var bus := _bus()
	if reason != &"":
		if bus != null:
			bus.craft_failed.emit(recipe_id, reason)
		return false
	var recipe := recipe_for(recipe_id)
	var bag := _bag()
	for id: Variant in recipe.ingredients:
		bag.call("remove", StringName(str(id)), int(recipe.ingredients[id]))
	bag.call("add", recipe.output_id, recipe.output_count)
	if bus != null:
		bus.craft_succeeded.emit(recipe_id, recipe.output_id, recipe.output_count)
	return true


func _bag() -> Object:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	if state == null:
		return null
	return state.get("inventory") as Object


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


static func _find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
