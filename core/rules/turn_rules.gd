class_name TurnRules
extends RefCounted
## Start-of-turn bookkeeping for the current team: income, resupply, paid
## repairs on friendly properties, and readying units. Used by
## GameState.create for the first turn and by EndTurnCommand after.

const REPAIR_HP := 20  # internal HP (= 2 displayed) per turn on a property


static func begin_turn(state: GameState) -> void:
	var team := state.current_team
	_expire_power(state, team)
	state.funds[team] += state.properties_of(team).size() * GameState.INCOME_PER_PROPERTY
	for unit in state.units_of(team):
		unit.acted = false
		if unit.carrier != null:
			continue  # passengers sit tight until dropped
		if state.owner_at(unit.cell) == unit.team or _in_reach_of_supplier(state, unit):
			unit.resupply()
		_repair(state, unit)


## A ROUND Command Power covers the opponent's turn and runs out the moment its
## owner's next one opens — here, before the turn it no longer applies to does
## anything. OWNER_TURN powers came down earlier, in EndTurnCommand.
static func _expire_power(state: GameState, team: int) -> void:
	var co_state := state.commander_state(team)
	if co_state.power_active and co_state.type.power_duration == CommanderType.Duration.ROUND:
		co_state.power_active = false


## +2 displayed HP on a friendly property, paid proportionally to unit cost.
## Skipped (not partial) when funds don't cover the full heal.
static func _repair(state: GameState, unit: Unit) -> void:
	if unit.hp >= 100:
		return
	if state.owner_at(unit.cell) != unit.team:
		return
	var heal := mini(REPAIR_HP, 100 - unit.hp)
	var full_price := unit.type.cost * heal / 100
	var cost := full_price * state.commander_of(unit.team).repair_cost_pct(state, unit) / 100
	if state.funds[unit.team] < cost:
		return
	state.funds[unit.team] -= cost
	unit.hp += heal


## A supply unit close enough to reach `unit`. How close is its commander's
## call — Gideon Holt's APCs work at two tiles — so the radius is asked for
## rather than assumed to be adjacency.
static func _in_reach_of_supplier(state: GameState, unit: Unit) -> bool:
	for other in state.units_of(unit.team):
		if other == unit or other.carrier != null or not other.type.can_resupply:
			continue
		var dist := absi(other.cell.x - unit.cell.x) + absi(other.cell.y - unit.cell.y)
		if dist <= state.commander_of(other.team).supply_range(state, other):
			return true
	return false
