class_name TurnRules
extends RefCounted
## Start-of-turn bookkeeping for the current team: income, paid repairs on
## friendly properties, and readying units. Used by GameState.create for the
## first turn and by EndTurnCommand for every turn after.

const REPAIR_HP := 20  # internal HP (= 2 displayed) per turn on a property


static func begin_turn(state: GameState) -> void:
	var team := state.current_team
	state.funds[team] += state.properties_of(team).size() * GameState.INCOME_PER_PROPERTY
	for unit in state.units_of(team):
		unit.acted = false
		_repair(state, unit)


## +2 displayed HP on a friendly property, paid proportionally to unit cost.
## Skipped (not partial) when funds don't cover the full heal.
static func _repair(state: GameState, unit: Unit) -> void:
	if unit.hp >= 100:
		return
	if state.owner_at(unit.cell) != unit.team:
		return
	var heal := mini(REPAIR_HP, 100 - unit.hp)
	var cost := unit.type.cost * heal / 100
	if state.funds[unit.team] < cost:
		return
	state.funds[unit.team] -= cost
	unit.hp += heal
