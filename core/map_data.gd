class_name MapData
extends RefCounted
## Authoritative map state for the simulation: terrain grid plus property
## ownership. The TileMapLayer in the battle scene is painted *from* this;
## it is never the source of truth.
##
## Map text format (see maps/*.txt):
##   # <one-line description>   -- the first comment line; shown in the menu
##   # symmetric               -- optional tag; asserts 180-degree symmetry
##   # any other comment
##   [terrain]
##   <one row of terrain symbols per line, all rows the same width>
##   [owners]
##   <team> <x> <y>       # team is 1-based; only property tiles may be owned
##   [units]
##   <team> <symbol> <x> <y>   # starting units; symbols defined by UnitType
##
## [owners] and [units] must come after [terrain] (they need the bounds).
## Unit symbols are validated later by GameState.create, which has the UnitDB.
## The playability invariants no parser can express — one HQ per team, a base
## each, reachable HQs, and the symmetry the tag above claims — are asserted
## over every shipped map by tests/unit/test_maps.gd.

const NEUTRAL := 0
## Comment line that opts a map into the mirror check in tests/unit/test_maps.gd.
const SYMMETRIC_TAG := "symmetric"

var width := 0
var height := 0
## First comment line: the one-line pitch the map dropdown shows as a tooltip.
var description := ""
## Set by the `# symmetric` tag: this map claims 180-degree rotational symmetry.
var symmetric := false
## Where this map was read from; empty for maps parsed straight from a string.
var source_path := ""
## Raw starting-unit entries: {team: int, symbol: String, cell: Vector2i}.
var starting_units: Array[Dictionary] = []
var _terrain: Array[TerrainType] = []  # row-major, width * height entries
var _owners: Dictionary = {}  # Vector2i -> int (team); missing key = neutral
var _property_cells: Array[Vector2i] = []  # cached by property_cells()
var _property_cells_built := false


static func load_from_file(path: String, db: TerrainDB) -> MapData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("MapData: cannot read map file '%s'" % path)
		return null
	var map := parse(text, db)
	if map != null:
		map.source_path = path
	return map


## Returns null (with a pushed error) on any malformed input.
static func parse(text: String, db: TerrainDB) -> MapData:
	var map := MapData.new()
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			map._read_comment(line.trim_prefix("#").strip_edges())
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


## Every capturable property cell on the map, row-major (computed once on
## demand). Returns a copy, like initial_owners: the cache stays ours.
func property_cells() -> Array[Vector2i]:
	if not _property_cells_built:
		for y in height:
			for x in width:
				if _terrain[y * width + x].is_property:
					_property_cells.append(Vector2i(x, y))
		_property_cells_built = true
	return _property_cells.duplicate()


func size() -> Vector2i:
	return Vector2i(width, height)


## The cell `cell` rotates onto under 180 degrees. Its own inverse, and the one
## definition of "mirrored" the maps and their symmetry lint share.
func mirrored(cell: Vector2i) -> Vector2i:
	return Vector2i(width - 1 - cell.x, height - 1 - cell.y)


## Comments carry two pieces of data: the `# symmetric` tag, and the first
## comment line, which by convention is the map's one-line description.
func _read_comment(comment: String) -> void:
	if comment == SYMMETRIC_TAG:
		symmetric = true
	elif description.is_empty():
		description = comment


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
