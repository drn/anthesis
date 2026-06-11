## Loads and indexes ability data resources from disk.
##
## AbilityRegistry scans a directory for [code].tres[/code] resources, loads
## any that are [AbilityDef], and indexes them by their declared [code]id[/code].
## It is the read-only catalog the rest of the game queries when it needs to
## resolve an ability id to its definition or list available abilities.
##
## Game data lives as resources on disk (never as GDScript constants), so the
## registry is the single seam where that data enters the running game. Missing
## directories are tolerated and simply yield an empty catalog.
##
## Abilities are returned sorted by id for a stable, deterministic hotkey order.
##
## Note: in exported builds [code].tres[/code] files are remapped to
## [code].tres.remap[/code]; this v1 scan handles both name forms and relies on
## [ResourceLoader] to resolve the actual resource.
class_name AbilityRegistry
extends RefCounted

var _abilities: Dictionary = {}


## Scan [param dir] for [AbilityDef] resources to index.
##
## The directory is optional; a missing or unreadable directory contributes
## nothing rather than raising. Resources that are not [AbilityDef], or that
## carry an empty id, are skipped.
func _init(dir := "res://resources/abilities") -> void:
	_scan(dir)


## Return the [AbilityDef] registered under [param id], or [code]null[/code].
func ability(id: StringName) -> AbilityDef:
	return _abilities.get(id, null)


## Return every registered [AbilityDef] sorted by id for stable hotkey order.
func abilities() -> Array[AbilityDef]:
	var ids := ability_ids()
	var out: Array[AbilityDef] = []
	for id in ids:
		out.append(_abilities[id])
	return out


## Return the ids of every registered ability sorted alphabetically.
func ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _abilities.keys():
		ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return ids


func _scan(dir_path: String) -> void:
	for res in _load_resources(dir_path):
		var def := res as AbilityDef
		if def == null or def.id == &"":
			continue
		_abilities[def.id] = def


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
