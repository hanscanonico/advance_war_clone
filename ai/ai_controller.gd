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
##
## Every number it weighs lives in an AIProfile resource rather than in this
## file, so tuning and difficulty are data edits. This class decides *how* to
## choose; the profile decides *what it is worth*.


class UnitPlan:
	var command: Command
	var score := -INF


## Where a unit should head when it has nothing better to do. `stand_off` marks
## goals we want to shoot rather than reach, so indirect units stop at range.
class AdvanceGoal:
	var cell: Vector2i
	var stand_off := false


var unit_db: UnitDB
## Every number this planner weighs. Never null: an omitted profile falls back
## to the shipped default, so callers that do not care about tuning — the battle
## scene, most tests — need not mention it.
var profile: AIProfile


func _init(p_unit_db: UnitDB, p_profile: AIProfile = null) -> void:
	unit_db = p_unit_db
	profile = p_profile if p_profile != null else AIProfile.load_default()


## The next best command for the current team: the highest-scored action of
## any ready unit, then production, then end of turn. Every ready unit always
## receives some command (waiting in place at worst), so repeated
## plan-and-apply calls are guaranteed to reach EndTurnCommand.
func plan_next_command(state: GameState) -> Command:
	var power := _plan_power(state)
	if power != null:
		return power
	var best: Command = null
	var best_score := -INF
	for unit in state.units_of(state.current_team):
		if unit.acted or unit.carrier != null:
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


## Fires the Command Power when the meter is full and there is something to
## spend it on: at least one enemy inside the reach of a unit that has not acted.
##
## Deliberately blunt for a first version. Every wave-1 power only helps the turn
## it goes off on, so "there is a fight to have this turn" is correct by
## construction for all of them, and there is nothing to score or look ahead
## through — which keeps the planner deterministic, as the rest of it is.
##
## Reach is Manhattan distance against movement plus firing range, ignoring
## terrain cost. That over-estimates, and deliberately so: the failure it avoids
## is sitting on a full meter all match.
func _plan_power(state: GameState) -> Command:
	var command := PowerCommand.new()
	if command.validate(state) != "":
		return null
	for unit in state.units_of(state.current_team):
		if unit.acted or unit.carrier != null or unit.type.max_range <= 0:
			continue
		var reach := AttackRange.maximum(state, unit)
		if not AttackRange.is_indirect(unit):
			reach += MovementResolver.move_budget(state, unit)
		for enemy in state.units:
			if enemy.team == unit.team or enemy.carrier != null:
				continue
			var dist := absi(enemy.cell.x - unit.cell.x) + absi(enemy.cell.y - unit.cell.y)
			if dist <= reach:
				return command
	return null


func _best_unit_plan(state: GameState, unit: Unit) -> UnitPlan:
	var plan := UnitPlan.new()
	var reachable := MovementResolver.reachable(state, unit)
	_consider_attacks(state, unit, reachable, plan)
	_consider_captures(state, unit, reachable, plan)
	if plan.score < profile.min_useful_score:
		plan.command = _advance_command(state, unit, reachable)
		plan.score = profile.advance_score
	return plan


func _consider_attacks(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange, plan: UnitPlan
) -> void:
	if unit.type.max_range <= 0 or state.damage_chart == null:
		return
	var dests: Array[Vector2i] = []
	if AttackRange.is_indirect(unit):
		dests = [unit.cell]  # indirect units cannot move and fire
	else:
		for cell in reachable.cells():
			if reachable.can_stop_at(cell):
				dests.append(cell)
	for dest in dests:
		for enemy in state.units:
			if enemy.team == unit.team or enemy.carrier != null:
				continue
			if not AttackRange.covers(state, unit, dest, enemy.cell):
				continue
			if not state.damage_chart.can_attack(unit.type.id, enemy.type.id):
				continue
			var forecast := CombatResolver.forecast(state, unit, dest, enemy)
			var step_cost: int = reachable.costs[dest]
			var score: float = (
				_attack_score(unit, enemy, forecast) - profile.step_cost_penalty * step_cost
			)
			if score > plan.score:
				plan.score = score
				plan.command = AttackCommand.new(unit, reachable.path_to(dest), enemy.cell)


## Expected damage value (target cost x damage fraction, kill-boosted) minus
## discounted counter risk against our own cost.
func _attack_score(unit: Unit, enemy: Unit, forecast: CombatResolver.Forecast) -> float:
	if not forecast.can_attack:
		return -INF
	var damage := mini(forecast.attack_damage, enemy.hp)
	var value := float(enemy.type.cost) * damage / 100.0
	if forecast.attack_damage >= enemy.hp:
		value *= profile.kill_bonus
	var risk := 0.0
	if forecast.counter_damage > 0:
		var counter := mini(forecast.counter_damage, unit.hp)
		risk = float(unit.type.cost) * counter / 100.0 * profile.counter_weight
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
		var score := profile.capture_score
		if terrain.id == &"hq":
			score *= profile.hq_capture_multiplier
		var points: int = state.capture_progress.get(cell, GameState.CAPTURE_POINTS)
		var step_cost: int = reachable.costs[cell]
		score += (GameState.CAPTURE_POINTS - points) * profile.capture_progress_bonus
		score -= profile.step_cost_penalty * step_cost
		if score > plan.score:
			plan.score = score
			plan.command = CaptureCommand.new(unit, reachable.path_to(cell))


## Fallback when no attack or capture is worthwhile: take the best position
## relative to a goal. Waits in place when nothing better is reachable, so the
## unit still acts.
func _advance_command(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange
) -> Command:
	var goal := _advance_goal(state, unit)
	var best_cell := unit.cell
	var best_rank := _position_rank(state, unit, unit.cell, goal)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var rank := _position_rank(state, unit, cell, goal)
		var cost: int = reachable.costs[cell]
		if rank < best_rank or (rank == best_rank and cost < best_cost):
			best_rank = rank
			best_cost = cost
			best_cell = cell
	return MoveCommand.new(unit, reachable.path_to(best_cell))


## How good a destination is, lower being better. Direct units just close in on
## the goal. Indirect units want it inside their firing ring instead, ideally at
## maximum standoff, so they never strand themselves inside their minimum range
## where they can neither fire nor counter.
##
## The ring comes from AttackRange, so a commander who extends it (Rhea Sol)
## moves the AI's preferred standoff with it rather than leaving the planner
## hugging a range it no longer has.
static func _position_rank(state: GameState, unit: Unit, cell: Vector2i, goal: AdvanceGoal) -> int:
	var dist := absi(goal.cell.x - cell.x) + absi(goal.cell.y - cell.y)
	if not goal.stand_off:
		return dist
	var low := AttackRange.minimum(state, unit)
	var high := AttackRange.maximum(state, unit)
	var out_of_ring := high - low + 1
	if dist > high:
		return out_of_ring + dist - high
	if dist < low:
		return out_of_ring + low - dist
	return high - dist


## Damaged units head for a friendly property (repairs), capture units for the
## nearest non-owned property, everyone else toward the nearest enemy — which
## indirect units approach only as far as their firing ring.
func _advance_goal(state: GameState, unit: Unit) -> AdvanceGoal:
	var goal := AdvanceGoal.new()
	goal.cell = unit.cell
	if unit.hp <= profile.retreat_hp:
		var owned := state.properties_of(unit.team)
		if not owned.is_empty():
			goal.cell = _nearest(unit.cell, owned)
			return goal
	if unit.type.can_capture:
		var capturable: Array[Vector2i] = []
		for cell in state.map.property_cells():
			if state.owner_at(cell) != unit.team:
				capturable.append(cell)
		if not capturable.is_empty():
			goal.cell = _nearest(unit.cell, capturable)
			return goal
	var enemy_cells: Array[Vector2i] = []
	for other in state.units:
		if other.team != unit.team and other.carrier == null:
			enemy_cells.append(other.cell)
	if not enemy_cells.is_empty():
		goal.cell = _nearest(unit.cell, enemy_cells)
		goal.stand_off = AttackRange.is_indirect(unit)
	return goal


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
	if infantry != null and capture_units < profile.capture_unit_target and funds >= infantry.cost:
		return infantry
	for id in profile.build_priority:
		var unit_type := unit_db.by_id(id)
		if unit_type != null and funds >= unit_type.cost:
			return unit_type
	if infantry != null and funds >= infantry.cost:
		return infantry
	return null
