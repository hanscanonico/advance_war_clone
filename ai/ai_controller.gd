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

## Difficult's threat map (S1). Built on first use each turn a profile with
## threat awareness is planning, and reused across every command that turn — the
## enemies it reads from cannot move while the AI plays, so one build is honest.
## Stays null on Normal and Easy, which never pay to build it. See _threat_map_for.
var _threat_map: ThreatMap = null
## Signature of the enemy set the cached map was built from; a mismatch (an enemy
## died to a counter, or the turn changed hands) rebuilds it.
var _threat_key: String = ""


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


## Fires the Command Power when the meter is full and the commander says the
## moment is right.
##
## *When* is the commander's business, not the planner's, because the roster
## disagrees about it: an attack power wants a fight this turn, Hold the Line
## wants one next turn, Open the Depots wants a worn-down army and no fight at
## all. CommanderType.wants_power carries that per general — same as every other
## doctrine — so this stays one question and gains no chain of special cases.
## The neutral default is the offensive read the whole roster used to share.
func _plan_power(state: GameState) -> Command:
	var command := PowerCommand.new()
	if command.validate(state) != "":
		return null
	var team := state.current_team
	if not state.commander_of(team).wants_power(state, team):
		return null
	return command


## The enemy units this planner may act on. The AI sees the whole board on
## purpose — an openly-cheating opponent rather than a guessing one — with
## exactly one exception: a unit a doctrine has hidden (Sable Wren's Vanish) is
## hidden from it too, because otherwise an invisibility power is inert in the
## one-player match, which is the only match most people play. Vision answers
## that; visibility is never re-derived here.
static func _visible_enemies(state: GameState, team: int) -> Array[Unit]:
	var enemies: Array[Unit] = []
	for unit in state.units:
		if unit.team == team or unit.carrier != null:
			continue
		if Vision.is_hidden_from(state, team, unit):
			continue
		enemies.append(unit)
	return enemies


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
	var enemies := _visible_enemies(state, unit.team)
	for dest in dests:
		# What firing from this cell costs, whoever the target turns out to be:
		# the walk to it plus the fire it invites next turn. Both depend only on
		# the cell, so they are worked out once per destination — and lazily, so a
		# cell with nothing to shoot at never pays for a threat lookup at all.
		var dest_penalty := -1.0
		for enemy in enemies:
			if not AttackRange.covers(state, unit, dest, enemy.cell):
				continue
			if not state.damage_chart.can_attack(unit.type.id, enemy.type.id):
				continue
			if dest_penalty < 0.0:
				var step_cost: int = reachable.costs[dest]
				dest_penalty = (
					profile.step_cost_penalty * step_cost + _threat_penalty(state, unit, dest)
				)
			var forecast := CombatResolver.forecast(state, unit, dest, enemy)
			var score: float = (
				_attack_score(unit, enemy, forecast)
				+ _focus_bonus(state, unit, enemy, forecast)
				- dest_penalty
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


## S1. What ending on `cell` costs `unit` in expected incoming damage next turn,
## in the same cost-scaled currency an attack's value uses, so it discounts a
## destination's score directly. 0 — and no threat map built — when the profile
## has threat awareness off, which is what keeps Normal and Easy free of it.
func _threat_penalty(state: GameState, unit: Unit, cell: Vector2i) -> float:
	if profile.threat_aversion <= 0.0:
		return 0.0
	var incoming := _threat_map_for(state).incoming_damage(state, unit, cell)
	return profile.threat_aversion * float(unit.type.cost) * incoming / 100.0


## S2. How much more attractive `enemy` is because other ready friendlies could
## still pile onto it this turn — the planner concentrates fire to finish a unit
## rather than scatter it. 0 when focus fire is off, or when this shot already
## kills: there is nothing left to follow up on.
##
## Deliberately a *proportion of this shot's own value* rather than a term of its
## own. An independent bonus scaled by the follow-up damage swamps the score it
## is meant to adjust — a 16,000-cost target the team can surround outranks every
## shot on the board, so the AI walks into bad trades to reach the gang-up. As a
## proportion it can at most double a shot the team can finish, which re-ranks
## comparable attacks and never promotes a bad one. The AI-vs-AI gate measured
## both shapes; the additive one lost games (see docs/difficulty_check.md).
func _focus_bonus(
	state: GameState, unit: Unit, enemy: Unit, forecast: CombatResolver.Forecast
) -> float:
	if profile.focus_fire_bonus <= 0.0:
		return 0.0
	var remaining := enemy.hp - forecast.attack_damage
	if remaining <= 0:
		return 0.0
	var follow_up := mini(remaining, _follow_up_damage(state, unit, enemy))
	if follow_up <= 0:
		return 0.0
	var value := float(enemy.type.cost) * mini(forecast.attack_damage, enemy.hp) / 100.0
	return profile.focus_fire_bonus * value * float(follow_up) / float(remaining)


## Summed forecast damage other ready, un-acted friendlies could deal `enemy`
## this turn. Reach is the same Manhattan over-estimate the commander powers use
## (move budget plus firing range), so no extra flood fill is spent and the worst
## case is crediting a follow-up that terrain would have denied — the failure to
## avoid is missing a real one. Draws no RNG: forecast is luck-free.
func _follow_up_damage(state: GameState, attacker: Unit, enemy: Unit) -> int:
	var total := 0
	for friendly in state.units_of(attacker.team):
		if friendly == attacker or friendly.acted or friendly.carrier != null:
			continue
		if friendly.type.max_range <= 0 or not friendly.has_ammo():
			continue
		if not state.damage_chart.can_attack(friendly.type.id, enemy.type.id):
			continue
		var reach := AttackRange.maximum(state, friendly)
		if not AttackRange.is_indirect(friendly):
			reach += MovementResolver.move_budget(state, friendly)
		if absi(friendly.cell.x - enemy.cell.x) + absi(friendly.cell.y - enemy.cell.y) > reach:
			continue
		var forecast := CombatResolver.forecast(state, friendly, friendly.cell, enemy)
		if forecast.can_attack:
			total += forecast.attack_damage
	return total


## The threat map for the current turn (S1), built on first use and rebuilt only
## when the enemy set changes. During the AI's own turn that means an enemy died
## to a counter; a new turn changes current_team and so the signature too.
func _threat_map_for(state: GameState) -> ThreatMap:
	var enemies := _visible_enemies(state, state.current_team)
	var key := _threat_signature(state.current_team, enemies)
	if _threat_map == null or _threat_key != key:
		_threat_map = ThreatMap.build(state, enemies)
		_threat_key = key
	return _threat_map


static func _threat_signature(team: int, enemies: Array[Unit]) -> String:
	var parts := PackedStringArray()
	parts.append(str(team))
	for enemy in enemies:
		parts.append("%d.%d.%d" % [enemy.team, enemy.cell.x, enemy.cell.y])
	return ",".join(parts)


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
	var best_value := _advance_value(state, unit, unit.cell, goal)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var value := _advance_value(state, unit, cell, goal)
		var cost: int = reachable.costs[cell]
		if value > best_value or (is_equal_approx(value, best_value) and cost < best_cost):
			best_value = value
			best_cost = cost
			best_cell = cell
	return MoveCommand.new(unit, reachable.path_to(best_cell))


## How good ending on `cell` is, higher being better: closeness to the goal
## (negative rank) less the expected incoming damage of standing there (S1),
## discounted by threat_aversion. With threat awareness off this is exactly
## -rank, so the cheaper-of-equal-value tiebreak above reproduces the original
## nearest-cell advance bit for bit — Normal is untouched.
func _advance_value(state: GameState, unit: Unit, cell: Vector2i, goal: AdvanceGoal) -> float:
	var value := -float(_position_rank(state, unit, cell, goal))
	if profile.threat_aversion > 0.0:
		var incoming := _threat_map_for(state).incoming_damage(state, unit, cell)
		value -= profile.threat_aversion * incoming / 100.0
	return value


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
	for other in _visible_enemies(state, unit.team):
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
	if profile.build_reactivity > 0.0:
		var reactive := _reactive_build(state, funds)
		if reactive != null:
			return reactive
	var listed := _static_build(funds)
	if listed != null:
		return listed
	if infantry != null and funds >= infantry.cost:
		return infantry
	return null


## The strongest affordable unit on the profile's build list. The whole of
## Normal's and Easy's buying, and the fallback whenever counter-building has
## nothing to say.
func _static_build(funds: int) -> UnitType:
	for id in profile.build_priority:
		var unit_type := unit_db.by_id(id)
		if unit_type != null and funds >= unit_type.cost:
			return unit_type
	return null


## S3. Picks the affordable combat unit that best answers the enemy's actual,
## cost-weighted roster, blended with the static build_priority order by
## build_reactivity. At reactivity 0 this is never reached (the static list runs
## instead); at 1 the matchup decides outright. Both components are normalised to
## 0..1 so the blend mixes like with like. Only the *choice* changes — the unit
## it returns is built by the same BuildCommand as any other.
##
## Null when there is nothing to react to — no roster in sight, or none of it
## takable damage — and the static list decides instead. Without that, full
## reactivity would score every candidate at zero and buy whichever the database
## happened to list first.
func _reactive_build(state: GameState, funds: int) -> UnitType:
	var candidates: Array[UnitType] = []
	for unit_type in unit_db.all():
		if unit_type.max_range > 0 and funds >= unit_type.cost:
			candidates.append(unit_type)
	if candidates.is_empty():
		return null
	var roster := _enemy_roster(state)
	if roster.is_empty():
		return null
	var max_eff := 0.0
	var effectiveness: Dictionary = {}
	for cand in candidates:
		var value := _effectiveness(state, cand, roster)
		effectiveness[cand.id] = value
		max_eff = maxf(max_eff, value)
	if max_eff <= 0.0:
		return null  # nothing affordable can hurt what is out there; let the list decide
	var priority := profile.build_priority
	var best: UnitType = null
	var best_score := -INF
	for cand in candidates:
		var static_norm := 0.0
		var rank := priority.find(cand.id)
		if rank >= 0:
			static_norm = float(priority.size() - rank) / float(priority.size())
		var eff_norm := float(effectiveness[cand.id]) / max_eff
		var score := (
			(1.0 - profile.build_reactivity) * static_norm + profile.build_reactivity * eff_norm
		)
		if score > best_score:
			best_score = score
			best = cand
	return best


## The visible enemy roster as [cost, type id] pairs, the raw material S3 weighs a
## prospective buy against. Cost-weighted so answering an expensive threat counts
## for more than swatting a cheap one.
func _enemy_roster(state: GameState) -> Array:
	var roster: Array = []
	for enemy in _visible_enemies(state, state.current_team):
		roster.append([enemy.type.cost, enemy.type.id])
	return roster


## Cost-weighted mean base damage `cand` deals across the enemy roster: higher
## means this buy hurts what the enemy actually fields. 0 against an empty roster,
## so early — before contact — S3 falls back to the static order.
func _effectiveness(state: GameState, cand: UnitType, roster: Array) -> float:
	var total_weight := 0.0
	var weighted := 0.0
	for entry in roster:
		var enemy_cost: float = float(entry[0])
		total_weight += enemy_cost
		var damage := state.damage_chart.base_damage(cand.id, entry[1])
		if damage > 0:
			weighted += enemy_cost * damage
	if total_weight <= 0.0:
		return 0.0
	return weighted / total_weight
