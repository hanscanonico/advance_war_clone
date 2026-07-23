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
##
## Step cost and the movement budget both come from MovementResolver, never from
## the terrain or the unit type directly. That is not a stylistic preference:
## the flood fill is what produced the path being checked here, so anything this
## works out for itself is a second opinion, and a doctrine that changes movement
## makes the two disagree — the range overlay offers a cell and the command then
## refuses it.
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
	# Only enemies the mover can see block the path here. A hidden one is left to
	# spring the ambush on apply; refusing the command would betray its position,
	# turning validation into a free fog probe (see GameState.advance_unit).
	var visible: Dictionary = (
		Vision.visible_cells(state, unit_moving.team) if state.fog_enabled else {}
	)
	var cost := 0
	for i in range(1, unit_path.size()):
		if (unit_path[i] - unit_path[i - 1]).length_squared() != 1:
			return "path is not contiguous"
		var terrain := state.map.terrain_at(unit_path[i])
		if terrain == null:
			return "path leaves the map"
		var step := MovementResolver.step_cost(state, unit_moving, terrain)
		if step == TerrainType.IMPASSABLE:
			return "path crosses impassable terrain"
		var occupant := state.unit_at(unit_path[i])
		if (
			occupant != null
			and occupant.team != unit_moving.team
			and Vision.can_see_unit(state, unit_moving.team, occupant, visible)
		):
			return "path is blocked by an enemy"
		cost += step
	# Fuel first, because the budget below is already capped by it — asking the
	# other way round would report a dry tank as a path that is simply too long.
	if cost > unit_moving.fuel:
		return "not enough fuel"
	if cost > MovementResolver.move_budget(state, unit_moving):
		return "path exceeds movement points"
	return ""


func validate(state: GameState) -> String:
	var steps := MoveCommand.validate_path_steps(state, unit, path)
	if steps != "":
		return steps
	var dest: Vector2i = path[path.size() - 1]
	var dest_occupant := state.unit_at(dest)
	if dest_occupant != null and dest_occupant != unit:
		# A friendly (always seen) blocks; a hidden enemy is left to spring the
		# ambush on apply rather than refused, which would reveal it. A visible
		# enemy never reaches here — validate_path_steps already caught it.
		var visible: Dictionary = Vision.visible_cells(state, unit.team) if state.fog_enabled else {}
		if (
			dest_occupant.team == unit.team
			or Vision.can_see_unit(state, unit.team, dest_occupant, visible)
		):
			return "destination is occupied"
	return ""


func apply(state: GameState) -> void:
	ambushed = state.advance_unit(unit, path)
