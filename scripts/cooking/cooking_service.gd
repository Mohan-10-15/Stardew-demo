class_name CookingService
extends Node
## Cooking at the farmhouse stove. Recipes are data; this node checks the bag,
## removes ingredients and adds the dish, publishing distinct outcomes.

const SERVICE_GROUP := &"cooking_service"
const DIR := "res://resources/cooking/recipes/"

static var _recipes: Dictionary = {}


static func find(start: Node) -> CookingService:
	if start == null:
		return null
	if start is CookingService:
		return start as CookingService
	for child: Node in start.get_children():
		var found := find(child)
		if found != null:
			return found
	return null


static func all_recipes() -> Array[CookingRecipe]:
	ensure_loaded()
	var out: Array[CookingRecipe] = []
	for item: Variant in _recipes.values():
		if item is CookingRecipe:
			out.append(item)
	return out


static func recipe_for(id: StringName) -> CookingRecipe:
	ensure_loaded()
	return _recipes.get(id) as CookingRecipe


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
		if entry.ends_with(".tres"):
			var data := ResourceLoader.load("%s%s" % [DIR, entry]) as CookingRecipe
			if data != null and data.is_valid():
				_recipes[data.id] = data
		entry = dir.get_next()
	dir.list_dir_end()


func _ready() -> void:
	add_to_group(SERVICE_GROUP)


func can_cook(id: StringName) -> StringName:
	var recipe := recipe_for(id)
	if recipe == null:
		return &"no_recipe"
	var bag := _bag()
	if bag == null:
		return &"no_player_state"
	for item_id: Variant in recipe.ingredients:
		if int(bag.call("count", StringName(str(item_id)))) < int(recipe.ingredients[item_id]):
			return &"missing_ingredients"
	return &""


func cook(id: StringName) -> bool:
	var reason := can_cook(id)
	var bus := _bus()
	if reason != &"":
		if bus != null:
			bus.cook_failed.emit(id, reason)
		return false
	var recipe := recipe_for(id)
	var bag := _bag()
	for item_id: Variant in recipe.ingredients:
		bag.call("remove", StringName(str(item_id)), int(recipe.ingredients[item_id]))
	bag.call("add", recipe.output_id, 1)
	if bus != null:
		bus.dish_cooked.emit(id, recipe.output_id)
	return true


func _bag() -> Object:
	var state := _find_named(get_tree().get_root(), "PlayerState")
	return state.get("inventory") as Object if state != null else null


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
