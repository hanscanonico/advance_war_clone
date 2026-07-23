class_name DropCommand
extends Command
## Moves a transport, then unloads its passenger onto an adjacent cell.
## The passenger comes out exhausted, like Advance Wars.
##
## Two terrain rules, and they are different questions. The cargo has to be able
## to *stand* where it lands, which every transport shares; and the transport has
## to be somewhere it can unload *from*, which is only the Lander's problem — a
## landing craft beaches on a shoal or ties up at a port, and cannot tip a tank
## over the side mid-ocean. Both come from data, so neither is a special case.

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
	if not unit.type.can_unload_from(state.map.terrain_at(dest).id):
		return "cannot unload here"
	var dist := absi(drop_cell.x - dest.x) + absi(drop_cell.y - dest.y)
	if dist != 1:
		return "drop cell must be adjacent"
	var terrain := state.map.terrain_at(drop_cell)
	if terrain == null or not terrain.is_passable(cargo[0].type.move_class):
		return "cargo cannot stand there"
	var occupant := state.unit_at(drop_cell)
	if occupant != null and occupant != unit:
		# The transport's own vacated cell is fine, and a hidden enemy is left to
		# foil the drop on apply rather than refused, which would reveal it; a
		# friendly or a visible enemy still blocks.
		var visible: Dictionary = Vision.visible_cells(state, unit.team) if state.fog_enabled else {}
		if (
			occupant.team == unit.team
			or Vision.can_see_unit(state, unit.team, occupant, visible)
		):
			return "drop cell is occupied"
	return ""


func apply(state: GameState) -> void:
	var passenger: Unit = state.cargo_of(unit)[0]
	ambushed = state.advance_unit(unit, path)
	# The move can stop short of where the drop was planned, or the drop cell can
	# turn out to hold a hidden enemy: either way the passenger stays aboard.
	if ambushed or state.unit_at(drop_cell) != null:
		ambushed = true
		return
	passenger.carrier = null
	passenger.cell = drop_cell
	passenger.acted = true
