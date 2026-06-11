## Loads and indexes item and recipe data resources from disk.
##
## ItemRegistry scans two directories for [code].tres[/code] resources, loads
## any that are [ItemDef] or [Recipe], and indexes them by their declared
## [code]id[/code]. It is the read-only catalog the rest of the game queries
## when it needs to resolve an item id to its definition or list craftable
## recipes.
##
## Game data lives as resources on disk (never as GDScript constants), so the
## registry is the single seam where that data enters the running game. Missing
## directories are tolerated and simply yield an empty catalog.
##
## Note: in exported builds [code].tres[/code] files are remapped to
## [code].tres.remap[/code]; this v1 scan handles both name forms and relies on
## [ResourceLoader] to resolve the actual resource.
class_name ItemRegistry
extends RefCounted

var _items: Dictionary = {}
var _recipes: Dictionary = {}
## Preserves discovery order so callers get a stable recipe list.
var _recipe_order: Array[StringName] = []
var _item_order: Array[StringName] = []


## Scan [param items_dir] and [param recipes_dir] for resources to index.
##
## Both directories are optional; a missing or unreadable directory contributes
## nothing rather than raising. Resources that are not [ItemDef]/[Recipe], or
## that carry an empty id, are skipped.
func _init(items_dir := "res://resources/items", recipes_dir := "res://resources/recipes") -> void:
	_scan_items(items_dir)
	_scan_recipes(recipes_dir)


## Return the [ItemDef] registered under [param id], or [code]null[/code].
func item(id: StringName) -> ItemDef:
	return _items.get(id, null)


## Return every registered [Recipe] in discovery order.
func recipes() -> Array[Recipe]:
	var out: Array[Recipe] = []
	for id in _recipe_order:
		out.append(_recipes[id])
	return out


## Return the [Recipe] registered under [param id], or [code]null[/code].
func recipe(id: StringName) -> Recipe:
	return _recipes.get(id, null)


## Return the ids of every registered item in discovery order.
func item_ids() -> Array[StringName]:
	return _item_order.duplicate()


func _scan_items(dir_path: String) -> void:
	for res in _load_resources(dir_path):
		var def := res as ItemDef
		if def == null or def.id == &"":
			continue
		if not _items.has(def.id):
			_item_order.append(def.id)
		_items[def.id] = def


func _scan_recipes(dir_path: String) -> void:
	for res in _load_resources(dir_path):
		var rec := res as Recipe
		if rec == null or rec.id == &"":
			continue
		if not _recipes.has(rec.id):
			_recipe_order.append(rec.id)
		_recipes[rec.id] = rec


## Load every [code].tres[/code] resource directly under [param dir_path].
##
## Returns an empty array when the directory does not exist. Remapped
## ([code].tres.remap[/code]) names are normalized back to their source path so
## [ResourceLoader] can resolve them in exported builds.
func _load_resources(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var res_path := _resolve_resource_path(dir_path, file_name)
			if res_path != "":
				var res := ResourceLoader.load(res_path)
				if res != null:
					out.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


## Map a directory entry to a loadable resource path, or "" if not a resource.
func _resolve_resource_path(dir_path: String, file_name: String) -> String:
	var base := dir_path.path_join(file_name)
	if file_name.ends_with(".tres"):
		return base
	if file_name.ends_with(".tres.remap"):
		# Strip the ".remap" suffix to recover the logical resource path.
		return base.left(base.length() - ".remap".length())
	return ""
