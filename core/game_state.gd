class_name GameState
extends RefCounted
## Authoritative battle state: the map, all units, property ownership, funds,
## and whose turn it is. Scenes render from this; commands mutate it.
## No Node dependencies.

const TEAMS: Array[int] = [1, 2]
const CAPTURE_POINTS := 20
const INCOME_PER_PROPERTY := 1000

var map: MapData
var units: Array[Unit] = []
var damage_chart: DamageChart
## Match RNG (combat luck). Set `rng.seed` explicitly for deterministic
## tests and replays; the battle scene randomizes it.
var rng := RandomNumberGenerator.new()

var current_team: int = 1
var day: int = 1
var funds: Dictionary = {}  # team -> int
## Runtime property ownership (Vector2i -> team). Starts from the map's
## [owners] section; capture changes it here, never in MapData.
var property_owners: Dictionary = {}
## In-progress captures: property cell -> capture points remaining.
## Cleared when the capturing unit leaves the cell or dies.
var capture_progress: Dictionary = {}
## 0 while the match runs; the winning team once decided.
var winner: int = 0


## Builds the starting state from a parsed map. Returns null (with a pushed
## error) if any starting unit is invalid. The damage chart is optional for
## states that never resolve combat (e.g. movement-only tests).
static func create(
	p_map: MapData, unit_db: UnitDB, p_damage_chart: DamageChart = null
) -> GameState:
	var state := GameState.new()
	state.map = p_map
	state.damage_chart = p_damage_chart
	state.property_owners = p_map.initial_owners()
	for team in TEAMS:
		state.funds[team] = 0
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
		state.units.append(Unit.create(type, entry.team, cell))
	TurnRules.begin_turn(state)  # day-1 income for the first player
	return state


func unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if unit.carrier == null and unit.cell == cell:
			return unit
	return null


func units_of(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.team == team:
			result.append(unit)
	return result


## Units riding inside the given transport.
func cargo_of(transport: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.carrier == transport:
			result.append(unit)
	return result


func remove_unit(unit: Unit) -> void:
	# Cargo goes down with its transport.
	for passenger in cargo_of(unit):
		remove_unit(passenger)
	units.erase(unit)
	# A dying unit abandons any capture in progress.
	capture_progress.erase(unit.cell)
	_check_rout(unit.team)


func owner_at(cell: Vector2i) -> int:
	return property_owners.get(cell, MapData.NEUTRAL)


func set_owner(cell: Vector2i, team: int) -> void:
	property_owners[cell] = team


func properties_of(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in property_owners:
		if property_owners[cell] == team:
			cells.append(cell)
	cells.sort()
	return cells


## Commits a unit's move along `path`: an abandoned capture on the vacated cell
## resets to the full point count, fuel is spent per terrain cost, cargo rides
## along, and the unit is exhausted. Sole move-commit entry point, shared by
## every movement-type command's apply.
func advance_unit(unit: Unit, path: Array[Vector2i]) -> void:
	var dest: Vector2i = path[path.size() - 1]
	if dest != path[0]:
		capture_progress.erase(path[0])
	var fuel_spent := 0
	for i in range(1, path.size()):
		fuel_spent += map.terrain_at(path[i]).move_cost(unit.type.move_class)
	unit.fuel = maxi(0, unit.fuel - fuel_spent)
	unit.cell = dest
	unit.acted = true
	for passenger in cargo_of(unit):
		passenger.cell = dest


func next_team() -> int:
	var index := TEAMS.find(current_team)
	return TEAMS[(index + 1) % TEAMS.size()]


func _check_rout(dead_team: int) -> void:
	if winner != 0 or not units_of(dead_team).is_empty():
		return
	for team in TEAMS:
		if team != dead_team:
			winner = team
			return
