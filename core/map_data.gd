class_name MapData
extends RefCounted
## Authoritative map state for the simulation: terrain grid plus property
## ownership. The TileMapLayer in the battle scene is painted *from* this;
## it is never the source of truth.
##
## Map text format (see maps/*.txt):
##   # comment
##   [terrain]
##   <one row of terrain symbols per line, all rows the same width>
##   [owners]
##   <team> <x> <y>       # team is 1-based; only property tiles may be owned
##   [units]
##   <team> <symbol> <x> <y>   # starting units; symbols defined by UnitType
##
## [owners] and [units] must come after [terrain] (they need the bounds).
## Unit symbols are validated later by GameState.create, which has the UnitDB.

const NEUTRAL := 0

var width := 0
var height := 0
## Raw starting-unit entries: {team: int, symbol: String, cell: Vector2i}.
var starting_units: Array[Dictionary] = []
var _terrain: Array[TerrainType] = []  # row-major, width * height entries
var _owners: Dictionary = {}  # Vector2i -> int (team); missing key = neutral


static func load_from_file(path: String, db: TerrainDB) -> MapData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("MapData: cannot read map file '%s'" % path)
		return null
	return parse(text, db)


## Returns null (with a pushed error) on any malformed input.
static func parse(text: String, db: TerrainDB) -> MapData:
	var map := MapData.new()
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("["):
			section = line
			continue
		match section:
			"[terrain]":
				if not map._append_terrain_row(line, db):
					return null
			"[owners]":
				if not map._set_owner_from_line(line):
					return null
			"[units]":
				if not map._append_unit_from_line(line):
					return null
			_:
				push_error("MapData: line outside a known section: '%s'" % line)
				return null
	if map.width == 0 or map.height == 0:
		push_error("MapData: map has no terrain rows")
		return null
	return map


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func terrain_at(cell: Vector2i) -> TerrainType:
	if not in_bounds(cell):
		return null
	return _terrain[cell.y * width + cell.x]


func owner_at(cell: Vector2i) -> int:
	return _owners.get(cell, NEUTRAL)


## Copy of the starting ownership for GameState; runtime capture never
## mutates the map itself.
func initial_owners() -> Dictionary:
	return _owners.duplicate()


func size() -> Vector2i:
	return Vector2i(width, height)


func _append_terrain_row(line: String, db: TerrainDB) -> bool:
	if width == 0:
		width = line.length()
	elif line.length() != width:
		push_error("MapData: row %d is %d wide, expected %d" % [height, line.length(), width])
		return false
	for symbol in line:
		var terrain := db.by_symbol(symbol)
		if terrain == null:
			push_error("MapData: unknown terrain symbol '%s' in row %d" % [symbol, height])
			return false
		_terrain.append(terrain)
	height += 1
	return true


func _set_owner_from_line(line: String) -> bool:
	var parts := line.split(" ", false)
	if parts.size() != 3:
		push_error("MapData: bad owner line '%s' (expected: team x y)" % line)
		return false
	var team := int(parts[0])
	var cell := Vector2i(int(parts[1]), int(parts[2]))
	if team <= 0:
		push_error("MapData: owner team must be >= 1 in '%s'" % line)
		return false
	if not in_bounds(cell):
		push_error("MapData: owner cell %s out of bounds" % cell)
		return false
	if not terrain_at(cell).is_property:
		push_error("MapData: cell %s is not a property, cannot be owned" % cell)
		return false
	_owners[cell] = team
	return true


func _append_unit_from_line(line: String) -> bool:
	var parts := line.split(" ", false)
	if parts.size() != 4:
		push_error("MapData: bad unit line '%s' (expected: team symbol x y)" % line)
		return false
	var team := int(parts[0])
	var cell := Vector2i(int(parts[2]), int(parts[3]))
	if team <= 0:
		push_error("MapData: unit team must be >= 1 in '%s'" % line)
		return false
	if not in_bounds(cell):
		push_error("MapData: unit cell %s out of bounds" % cell)
		return false
	starting_units.append({"team": team, "symbol": parts[1], "cell": cell})
	return true
