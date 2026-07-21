class_name LoadCommand
extends Command
## Moves a unit onto a friendly transport and boards it.
##
## What a transport accepts is its own data (UnitType.cargo_classes) rather than
## one list shared by every carrier: an APC and a T-Copter take infantry, a
## Lander takes what drives, and the difference between them is a .tres field.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var steps := MoveCommand.validate_path_steps(state, unit, path)
	if steps != "":
		return steps
	var dest: Vector2i = path[path.size() - 1]
	var transport := state.unit_at(dest)
	if transport == null or transport == unit or transport.team != unit.team:
		return "no friendly transport at the destination"
	if transport.type.transport_capacity <= 0:
		return "destination unit is not a transport"
	if not transport.type.can_carry(unit.type.move_class):
		return "unit cannot be transported"
	if state.cargo_of(transport).size() >= transport.type.transport_capacity:
		return "transport is full"
	return ""


func apply(state: GameState) -> void:
	var transport := state.unit_at(path[path.size() - 1])
	state.advance_unit(unit, path)
	unit.carrier = transport
