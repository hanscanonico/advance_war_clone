class_name GameState
extends RefCounted
## Authoritative battle state: the map plus all units.
## Scenes render from this; commands mutate it. No Node dependencies.

var map: MapData
var units: Array[Unit] = []


## Builds the starting state from a parsed map. Returns null (with a pushed
## error) if any starting unit is invalid.
static func create(p_map: MapData, unit_db: UnitDB) -> GameState:
	var state := GameState.new()
	state.map = p_map
	for entry: Dictionary in p_map.starting_units:
		var type: UnitType = unit_db.by_symbol(entry.symbol)
		if type == null:
			push_error("GameState: unknown unit symbol '%s'" % entry.symbol)
			return null
		var cell: Vector2i = entry.cell
		if state.unit_at(cell) != null:
			push_error("GameState: two starting units on cell %s" % cell)
			return null
		if not p_map.terrain_at(cell).is_passable(type.move_class):
			push_error("GameState: %s cannot stand on %s at %s"
				% [type.id, p_map.terrain_at(cell).id, cell])
			return null
		var unit := Unit.new()
		unit.type = type
		unit.team = entry.team
		unit.cell = cell
		state.units.append(unit)
	return state


func unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if unit.cell == cell:
			return unit
	return null


func units_of(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.team == team:
			result.append(unit)
	return result


func remove_unit(unit: Unit) -> void:
	units.erase(unit)
