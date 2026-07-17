class_name TerrainDB
extends RefCounted
## Registry of all TerrainType resources, indexed by id and by map symbol.

const TERRAIN_DIR := "res://data/terrain"

var _by_id: Dictionary = {}
var _by_symbol: Dictionary = {}


static func load_default() -> TerrainDB:
	var db := TerrainDB.new()
	var dir := DirAccess.open(TERRAIN_DIR)
	if dir == null:
		push_error("TerrainDB: cannot open %s" % TERRAIN_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var terrain: TerrainType = load(TERRAIN_DIR.path_join(name))
		if terrain != null:
			db.register(terrain)
	return db


func register(terrain: TerrainType) -> void:
	if _by_id.has(terrain.id):
		push_error("TerrainDB: duplicate terrain id '%s'" % terrain.id)
		return
	if _by_symbol.has(terrain.symbol):
		push_error("TerrainDB: duplicate terrain symbol '%s'" % terrain.symbol)
		return
	_by_id[terrain.id] = terrain
	_by_symbol[terrain.symbol] = terrain


func by_id(id: StringName) -> TerrainType:
	return _by_id.get(id)


func by_symbol(symbol: String) -> TerrainType:
	return _by_symbol.get(symbol)


func all() -> Array[TerrainType]:
	var result: Array[TerrainType] = []
	for terrain in _by_id.values():
		result.append(terrain)
	return result


func size() -> int:
	return _by_id.size()
