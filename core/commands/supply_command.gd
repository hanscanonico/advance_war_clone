class_name SupplyCommand
extends Command
## Moves a supply unit (APC), then refills fuel and ammo of every adjacent
## friendly. Adjacent friendlies are also refilled automatically at turn
## start; this action is for mid-turn top-ups.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var move_error := MoveCommand.new(unit, path).validate(state)
	if move_error != "":
		return move_error
	if not unit.type.can_resupply:
		return "unit cannot resupply others"
	if adjacent_friendlies(state, path[path.size() - 1]).is_empty():
		return "no one adjacent to supply"
	return ""


func apply(state: GameState) -> void:
	state.advance_unit(unit, path)
	for friendly in adjacent_friendlies(state, unit.cell):
		friendly.resupply()


## Public so the UI can decide whether to offer the Supply action.
func adjacent_friendlies(state: GameState, from: Vector2i) -> Array[Unit]:
	var result: Array[Unit] = []
	for dir in MovementResolver.DIRECTIONS:
		var other := state.unit_at(from + dir)
		if other != null and other != unit and other.team == unit.team:
			result.append(other)
	return result
