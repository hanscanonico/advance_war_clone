class_name BuildCommand
extends Command
## Buys a unit at an owned, empty base. The new unit spawns exhausted and
## acts next turn, like Advance Wars.

var team: int
var unit_type: UnitType
var cell: Vector2i
## Populated by apply() so the presentation layer can spawn its sprite.
var built_unit: Unit


func _init(p_team: int, p_unit_type: UnitType, p_cell: Vector2i) -> void:
	team = p_team
	unit_type = p_unit_type
	cell = p_cell


func validate(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	if team != state.current_team:
		return "not this team's turn"
	if unit_type == null:
		return "unknown unit type"
	var terrain := state.map.terrain_at(cell)
	if terrain == null or terrain.id != &"base":
		return "can only build at a base"
	if state.owner_at(cell) != team:
		return "base is not owned"
	if state.unit_at(cell) != null:
		return "base is occupied"
	if state.funds[team] < unit_type.cost:
		return "insufficient funds"
	return ""


func apply(state: GameState) -> void:
	state.funds[team] -= unit_type.cost
	built_unit = Unit.new()
	built_unit.type = unit_type
	built_unit.team = team
	built_unit.cell = cell
	built_unit.acted = true
	state.units.append(built_unit)
