class_name MoveCommand
extends Command
## Moves a unit along a path and exhausts it for this turn.
## A single-cell path (staying put) is the Wait action.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	if unit.acted:
		return "unit has already acted"
	if path.is_empty() or path[0] != unit.cell:
		return "path must start at the unit's cell"
	var cost := 0
	for i in range(1, path.size()):
		if (path[i] - path[i - 1]).length_squared() != 1:
			return "path is not contiguous"
		var terrain := state.map.terrain_at(path[i])
		if terrain == null:
			return "path leaves the map"
		var step := terrain.move_cost(unit.type.move_class)
		if step == TerrainType.IMPASSABLE:
			return "path crosses impassable terrain"
		var occupant := state.unit_at(path[i])
		if occupant != null and occupant.team != unit.team:
			return "path is blocked by an enemy"
		cost += step
	if cost > unit.type.move_points:
		return "path exceeds movement points"
	var dest: Vector2i = path[path.size() - 1]
	var dest_occupant := state.unit_at(dest)
	if dest_occupant != null and dest_occupant != unit:
		return "destination is occupied"
	return ""


func apply(_state: GameState) -> void:
	unit.cell = path[path.size() - 1]
	unit.acted = true
