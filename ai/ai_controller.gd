class_name AIController
extends RefCounted
## Plans commands for an AI-controlled team, one command per call. Pure
## simulation logic with no Node dependencies: the battle scene applies and
## animates whatever this returns, exactly like player input would.
## An EndTurnCommand means the AI is done with its turn.
##
## Deliberately "credible, not strong": greedy per-unit utility scoring with
## no lookahead. Deterministic for a given state (ties break by scan order),
## so replays and tests stay stable.

## Scoring weights, tuned by feel. Attack value scales with the target's cost
## and expected damage; captures sit around city-capture value with a large
## bonus for the enemy HQ and for finishing a capture in progress.
const KILL_BONUS := 1.6
const COUNTER_WEIGHT := 0.6
const CAPTURE_SCORE := 900.0
const HQ_CAPTURE_MULTIPLIER := 3.0
const CAPTURE_PROGRESS_BONUS := 45.0  # per point already chipped off
const STEP_COST_PENALTY := 4.0
const RETREAT_HP := 45
const MIN_USEFUL_SCORE := 40.0
const ADVANCE_SCORE := 1.0
## Build preference when enough capture units exist, strongest first.
const BUILD_PRIORITY: Array[StringName] = [&"md_tank", &"tank", &"artillery", &"mech"]
const CAPTURE_UNIT_TARGET := 3


class UnitPlan:
	var command: Command
	var score := -INF


var unit_db: UnitDB


func _init(p_unit_db: UnitDB) -> void:
	unit_db = p_unit_db


## The next best command for the current team: the highest-scored action of
## any ready unit, then production, then end of turn. Every ready unit always
## receives some command (waiting in place at worst), so repeated
## plan-and-apply calls are guaranteed to reach EndTurnCommand.
func plan_next_command(state: GameState) -> Command:
	var best: Command = null
	var best_score := -INF
	for unit in state.units_of(state.current_team):
		if unit.acted:
			continue
		var plan := _best_unit_plan(state, unit)
		if plan.score > best_score:
			best_score = plan.score
			best = plan.command
	if best != null:
		return best
	var build := _plan_build(state)
	if build != null:
		return build
	return EndTurnCommand.new()


func _best_unit_plan(state: GameState, unit: Unit) -> UnitPlan:
	var plan := UnitPlan.new()
	var reachable := MovementResolver.reachable(state, unit)
	_consider_attacks(state, unit, reachable, plan)
	_consider_captures(state, unit, reachable, plan)
	if plan.score < MIN_USEFUL_SCORE:
		plan.command = _advance_command(state, unit, reachable)
		plan.score = ADVANCE_SCORE
	return plan


func _consider_attacks(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange, plan: UnitPlan
) -> void:
	if unit.type.max_range <= 0 or state.damage_chart == null:
		return
	var dests: Array[Vector2i] = []
	if unit.type.min_range > 1:
		dests = [unit.cell]  # indirect units cannot move and fire
	else:
		for cell in reachable.cells():
			if reachable.can_stop_at(cell):
				dests.append(cell)
	for dest in dests:
		for enemy in state.units:
			if enemy.team == unit.team:
				continue
			var dist := absi(enemy.cell.x - dest.x) + absi(enemy.cell.y - dest.y)
			if dist < unit.type.min_range or dist > unit.type.max_range:
				continue
			if not state.damage_chart.can_attack(unit.type.id, enemy.type.id):
				continue
			var forecast := CombatResolver.forecast(state, unit, dest, enemy)
			var step_cost: int = reachable.costs[dest]
			var score: float = _attack_score(unit, enemy, forecast) \
				- STEP_COST_PENALTY * step_cost
			if score > plan.score:
				plan.score = score
				plan.command = AttackCommand.new(unit, reachable.path_to(dest), enemy.cell)


## Expected damage value (target cost x damage fraction, kill-boosted) minus
## discounted counter risk against our own cost.
static func _attack_score(
	unit: Unit, enemy: Unit, forecast: CombatResolver.Forecast
) -> float:
	if not forecast.can_attack:
		return -INF
	var damage := mini(forecast.attack_damage, enemy.hp)
	var value := float(enemy.type.cost) * damage / 100.0
	if forecast.attack_damage >= enemy.hp:
		value *= KILL_BONUS
	var risk := 0.0
	if forecast.counter_damage > 0:
		var counter := mini(forecast.counter_damage, unit.hp)
		risk = float(unit.type.cost) * counter / 100.0 * COUNTER_WEIGHT
		if forecast.counter_damage >= unit.hp:
			risk *= 2.0
	return value - risk


func _consider_captures(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange, plan: UnitPlan
) -> void:
	if not unit.type.can_capture:
		return
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var terrain := state.map.terrain_at(cell)
		if not terrain.is_property or state.owner_at(cell) == unit.team:
			continue
		var score := CAPTURE_SCORE
		if terrain.id == &"hq":
			score *= HQ_CAPTURE_MULTIPLIER
		var points: int = state.capture_progress.get(cell, GameState.CAPTURE_POINTS)
		var step_cost: int = reachable.costs[cell]
		score += (GameState.CAPTURE_POINTS - points) * CAPTURE_PROGRESS_BONUS
		score -= STEP_COST_PENALTY * step_cost
		if score > plan.score:
			plan.score = score
			plan.command = CaptureCommand.new(unit, reachable.path_to(cell))


## Fallback when no attack or capture is worthwhile: close in on a goal.
## Damaged units head for a friendly property (repairs), capture units for
## the nearest non-owned property, everyone else toward the nearest enemy.
## Waits in place when nothing is reachable, so the unit still acts.
func _advance_command(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange
) -> Command:
	var goal := _advance_goal(state, unit)
	var best_cell := unit.cell
	var best_dist := absi(goal.x - unit.cell.x) + absi(goal.y - unit.cell.y)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var dist := absi(goal.x - cell.x) + absi(goal.y - cell.y)
		var cost: int = reachable.costs[cell]
		if dist < best_dist or (dist == best_dist and cost < best_cost):
			best_dist = dist
			best_cost = cost
			best_cell = cell
	return MoveCommand.new(unit, reachable.path_to(best_cell))


func _advance_goal(state: GameState, unit: Unit) -> Vector2i:
	if unit.hp <= RETREAT_HP:
		var owned := state.properties_of(unit.team)
		if not owned.is_empty():
			return _nearest(unit.cell, owned)
	if unit.type.can_capture:
		var capturable: Array[Vector2i] = []
		for cell in state.map.property_cells():
			if state.owner_at(cell) != unit.team:
				capturable.append(cell)
		if not capturable.is_empty():
			return _nearest(unit.cell, capturable)
	var enemy_cells: Array[Vector2i] = []
	for other in state.units:
		if other.team != unit.team:
			enemy_cells.append(other.cell)
	if not enemy_cells.is_empty():
		return _nearest(unit.cell, enemy_cells)
	return unit.cell


static func _nearest(from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	var best_dist := absi(best.x - from.x) + absi(best.y - from.y)
	for cell in cells:
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


## One build per call, at the first empty owned base the funds allow.
func _plan_build(state: GameState) -> Command:
	for cell in state.properties_of(state.current_team):
		if state.map.terrain_at(cell).id != &"base":
			continue
		if state.unit_at(cell) != null:
			continue
		var choice := _pick_build(state)
		if choice == null:
			return null
		return BuildCommand.new(state.current_team, choice, cell)
	return null


## Keep capture units flowing, then buy the strongest affordable vehicle.
func _pick_build(state: GameState) -> UnitType:
	var funds: int = state.funds[state.current_team]
	var infantry := unit_db.by_id(&"infantry")
	var capture_units := 0
	for unit in state.units_of(state.current_team):
		if unit.type.can_capture:
			capture_units += 1
	if capture_units < CAPTURE_UNIT_TARGET and funds >= infantry.cost:
		return infantry
	for id in BUILD_PRIORITY:
		var unit_type := unit_db.by_id(id)
		if unit_type != null and funds >= unit_type.cost:
			return unit_type
	if funds >= infantry.cost:
		return infantry
	return null
