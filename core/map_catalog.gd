class_name MapCatalog
extends RefCounted
## The shipped map roster: which files under maps/ are maps, what they are
## called, and the order the menu offers them in.
##
## Adding a map is still dropping a .txt in maps/ — nothing here lists them by
## hand. The point of the class is that the menu, the map lint and the per-map
## AI soak all discover the roster through one function instead of three
## DirAccess loops that can drift apart.
##
## Node-free like the rest of core/, so tests read exactly what the menu reads.

const MAPS_DIR := "res://maps"


## Every shipped map, alphabetically by filename — a stable order that does not
## depend on the filesystem's. `ordered()` is what the menu shows.
static func paths() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		push_error("MapCatalog: cannot open %s" % MAPS_DIR)
		return result
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list .txt files with a .remap suffix.
		var map_file := file.trim_suffix(".remap")
		if not map_file.ends_with(".txt"):
			continue
		result.append(MAPS_DIR.path_join(map_file))
	return result


## The roster parsed, smallest board first, so the menu's default (item 0) is
## the quickest match rather than whichever filename sorts first alphabetically.
## Ties break on filename, so the order is derived from data and still stable.
## Maps that fail to parse are dropped with a pushed error rather than taking
## the menu down with them.
static func ordered(db: TerrainDB) -> Array[MapData]:
	var maps: Array[MapData] = []
	for path in paths():
		var map := MapData.load_from_file(path, db)
		if map != null:
			maps.append(map)
	maps.sort_custom(_smaller_first)
	return maps


## The dropdown label for a map path: "first_steps.txt" -> "First Steps".
static func display_name(path: String) -> String:
	return path.get_file().trim_suffix(".txt").capitalize()


static func _smaller_first(a: MapData, b: MapData) -> bool:
	var area_a := a.width * a.height
	var area_b := b.width * b.height
	if area_a != area_b:
		return area_a < area_b
	return a.source_path < b.source_path
