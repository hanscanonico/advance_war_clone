class_name TurnRules
extends RefCounted
## Start-of-turn bookkeeping for the current team: income, fuel upkeep, resupply,
## paid repairs on friendly properties, and readying units. Used by
## GameState.create for the first turn and by EndTurnCommand after.

const REPAIR_HP := 20  # internal HP (= 2 displayed) per turn on a property


## Every turn is charged the same, day one included. That is what keeps the two
## sides even: create() opens the match with this for the first team, and the
## second team gets its own call through EndTurnCommand before it acts, so both
## have paid exactly once by the time they move. Skipping the opening day would
## have charged the first player one fewer time over any equal count of turns.
static func begin_turn(state: GameState) -> void:
	var team := state.current_team
	_expire_power(state, team)
	state.funds[team] += state.properties_of(team).size() * GameState.INCOME_PER_PROPERTY
	for unit in state.units_of(team):
		unit.acted = false
		if unit.carrier != null:
			continue  # passengers sit tight until dropped, and burn nothing
		_burn_upkeep(unit)
		if _serviced_here(state, unit) or _in_reach_of_supplier(state, unit):
			unit.resupply()
		if _lost_to_empty_tank(state, unit):
			continue  # nothing left to repair
		_repair(state, unit)


## Fuel spent simply by existing, before anything refills it. Zero for ground
## units, which is why a tank parked in a field is the same unit it was in M2, and
## several times the surface rate for a submarine that is under — the clock a dive
## is played against.
static func _burn_upkeep(unit: Unit) -> void:
	unit.fuel = maxi(0, unit.fuel - unit.upkeep())


## An air or sea unit whose tank reached zero is destroyed here, and its cargo
## with it (remove_unit's rule, shared with every other death).
##
## The order in begin_turn is the whole mechanic and none of it is incidental:
## upkeep is charged *before* resupply, so a plane that never lands eventually
## falls; resupply runs before this check, so one that did land is always full
## again and can never die on friendly tarmac; and the check sits before repair
## because there is nothing left to mend. Nothing is banked to either Command
## Power meter — running yourself dry is not an exchange, and paying the other
## side charge for it would make starving your own air force a tactic.
static func _lost_to_empty_tank(state: GameState, unit: Unit) -> bool:
	if not unit.type.lost_when_dry() or unit.fuel > 0:
		return false
	state.remove_unit(unit)
	return true


## Whether the property `unit` stands on is one of ours *and* refits its domain.
## The single answer to that question: repair and resupply both ask it, so no
## property can ever refuel something it refuses to repair.
static func _serviced_here(state: GameState, unit: Unit) -> bool:
	if state.owner_at(unit.cell) != unit.team:
		return false
	return state.map.terrain_at(unit.cell).services_domain(unit.type.domain)


## A ROUND Command Power covers the opponent's turn and runs out the moment its
## owner's next one opens — here, before the turn it no longer applies to does
## anything. OWNER_TURN powers came down earlier, in EndTurnCommand.
static func _expire_power(state: GameState, team: int) -> void:
	var co_state := state.commander_state(team)
	if co_state.power_active and co_state.type.power_duration == CommanderType.Duration.ROUND:
		co_state.power_active = false


## +2 displayed HP on a friendly property that services this unit's domain, paid
## proportionally to unit cost. Skipped (not partial) when funds don't cover the
## full heal.
static func _repair(state: GameState, unit: Unit) -> void:
	if unit.hp >= 100:
		return
	if not _serviced_here(state, unit):
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
