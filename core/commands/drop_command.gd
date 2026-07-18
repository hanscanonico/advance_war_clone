class_name DropCommand
extends Command
## Moves a transport, then unloads its passenger onto an adjacent cell.
## The passenger comes out exhausted, like Advance Wars.

var unit: Unit  # the transport
var path: Array[Vector2i]
var drop_cell: Vector2i


func _init(p_unit: Unit, p_path: Array[Vector2i], p_drop_cell: Vector2i) -> void:
	unit = p_unit
	path = p_path
	drop_cell = p_drop_cell


func validate(state: GameState) -> String:
	var move_error := MoveCommand.new(unit, path).validate(state)
	if move_error != "":
		return move_error
	var cargo := state.cargo_of(unit)
	if cargo.is_empty():
		return "nothing to drop"
	var dest: Vector2i = path[path.size() - 1]
	var dist := absi(drop_cell.x - dest.x) + absi(drop_cell.y - dest.y)
	if dist != 1:
		return "drop cell must be adjacent"
	var terrain := state.map.terrain_at(drop_cell)
	if terrain == null or not terrain.is_passable(cargo[0].type.move_class):
		return "cargo cannot stand there"
	var occupant := state.unit_at(drop_cell)
	if occupant != null and occupant != unit:
		return "drop cell is occupied"  # the transport's own vacated cell is fine
	return ""


func apply(state: GameState) -> void:
	var passenger: Unit = state.cargo_of(unit)[0]
	state.advance_unit(unit, path)
	passenger.carrier = null
	passenger.cell = drop_cell
	passenger.acted = true
