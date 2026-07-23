class_name SupplyCommand
extends Command
## Moves a supply unit (APC), then refills fuel and ammo of every friendly in
## reach. Friendlies in reach are also refilled automatically at turn start;
## this action is for mid-turn top-ups.
##
## "In reach" is one tile for most commanders and two for Gideon Holt, so the
## radius comes from the hook rather than from a hardcoded adjacency check —
## here and in TurnRules, the only two places supply is worked out.

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
	if friendlies_in_reach(state, path[path.size() - 1]).is_empty():
		return "no one in reach to supply"
	return ""


func apply(state: GameState) -> void:
	ambushed = state.advance_unit(unit, path)
	if ambushed:
		return  # stopped short by a hidden enemy; no top-up this turn
	for friendly in friendlies_in_reach(state, unit.cell):
		friendly.resupply()


## Friendlies this unit could refill standing on `from`. Public so the UI can
## decide whether to offer the Supply action at all.
func friendlies_in_reach(state: GameState, from: Vector2i) -> Array[Unit]:
	var result: Array[Unit] = []
	var radius := state.commander_of(unit.team).supply_range(state, unit)
	for other in state.units_of(unit.team):
		if other == unit or other.carrier != null:
			continue  # passengers are refilled by their transport at begin_turn (TurnRules), not beside it
		var dist := absi(other.cell.x - from.x) + absi(other.cell.y - from.y)
		if dist >= 1 and dist <= radius:
			result.append(other)
	return result
