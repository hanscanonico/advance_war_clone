class_name BuildCommand
extends Command
## Buys a unit at an owned, empty production property. The new unit spawns
## exhausted and acts next turn, like Advance Wars.
##
## Which property builds what is the terrain's own data (TerrainType.builds), not
## a base-shaped special case here: a port builds hulls and an airport builds
## airframes through this same command, and the build menu and the AI read the
## same list, so none of the three can offer a unit the others refuse.

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
	if terrain == null or terrain.builds.is_empty():
		return "can only build at a base"
	if state.owner_at(cell) != team:
		return "base is not owned"
	if state.unit_at(cell) != null:
		return "base is occupied"
	if not terrain.can_build(unit_type.move_class):
		# Lower-cased to match its siblings above, which are all plain lowercase
		# phrases — and it sidesteps having to pick "a" or "an" per unit name.
		return (
			"%s does not build %s"
			% [terrain.display_name.to_lower(), unit_type.display_name.to_lower()]
		)
	if state.funds[team] < unit_type.cost:
		return "insufficient funds"
	return ""


func apply(state: GameState) -> void:
	state.funds[team] -= unit_type.cost
	built_unit = Unit.create(unit_type, team, cell)
	built_unit.acted = true
	state.units.append(built_unit)
