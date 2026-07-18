class_name LoadCommand
extends Command
## Moves a foot/boot unit onto a friendly transport and boards it.

const TRANSPORTABLE: Array[StringName] = [TerrainType.FOOT, TerrainType.BOOT]

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var steps := MoveCommand.validate_path_steps(state, unit, path)
	if steps != "":
		return steps
	if unit.type.move_class not in TRANSPORTABLE:
		return "unit cannot be transported"
	var dest: Vector2i = path[path.size() - 1]
	var transport := state.unit_at(dest)
	if transport == null or transport == unit or transport.team != unit.team:
		return "no friendly transport at the destination"
	if transport.type.transport_capacity <= 0:
		return "destination unit is not a transport"
	if state.cargo_of(transport).size() >= transport.type.transport_capacity:
		return "transport is full"
	return ""


func apply(state: GameState) -> void:
	var transport := state.unit_at(path[path.size() - 1])
	state.advance_unit(unit, path)
	unit.carrier = transport
