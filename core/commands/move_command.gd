class_name MoveCommand
extends Command
## Moves a unit along a path and exhausts it for this turn.
## A single-cell path (staying put) is the Wait action.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


## Validates everything about moving `unit` along `path` except the
## destination-occupancy rule, which each movement-type command (Move, Load,
## Join) defines for itself. Returns "" when legal.
static func validate_path_steps(
	state: GameState, unit_moving: Unit, unit_path: Array[Vector2i]
) -> String:
	if state.winner != 0:
		return "the match is over"
	if unit_moving.team != state.current_team:
		return "not this team's turn"
	if unit_moving.carrier != null:
		return "unit is being transported"
	if unit_moving.acted:
		return "unit has already acted"
	if unit_path.is_empty() or unit_path[0] != unit_moving.cell:
		return "path must start at the unit's cell"
	var cost := 0
	for i in range(1, unit_path.size()):
		if (unit_path[i] - unit_path[i - 1]).length_squared() != 1:
			return "path is not contiguous"
		var terrain := state.map.terrain_at(unit_path[i])
		if terrain == null:
			return "path leaves the map"
		var step := terrain.move_cost(unit_moving.type.move_class)
		if step == TerrainType.IMPASSABLE:
			return "path crosses impassable terrain"
		var occupant := state.unit_at(unit_path[i])
		if occupant != null and occupant.team != unit_moving.team:
			return "path is blocked by an enemy"
		cost += step
	if cost > unit_moving.type.move_points:
		return "path exceeds movement points"
	if cost > unit_moving.fuel:
		return "not enough fuel"
	return ""


func validate(state: GameState) -> String:
	var steps := MoveCommand.validate_path_steps(state, unit, path)
	if steps != "":
		return steps
	var dest: Vector2i = path[path.size() - 1]
	var dest_occupant := state.unit_at(dest)
	if dest_occupant != null and dest_occupant != unit:
		return "destination is occupied"
	return ""


func apply(state: GameState) -> void:
	state.advance_unit(unit, path)
