class_name AttackRange
extends RefCounted
## How far a unit can shoot, doctrine included. The single authority on it.
##
## Three places used to work this out independently from min_range/max_range:
## AttackCommand's validation, the AI's target search, and the targeting overlay
## the player aims with. That was harmless while the answer was fixed and a
## liability the moment a commander could change it — a range bonus applied to
## two of the three means the rules, the AI and the UI disagree about the same
## shot, and the one that disagrees is whichever was forgotten.
##
## So they all ask here instead. Countering is the deliberate exception; see
## CombatResolver._defender_can_counter.


## The closest tile this unit can fire at. No doctrine changes it: a minimum
## range is the dead zone a weapon cannot shoot inside, not a bonus to hand out.
static func minimum(_state: GameState, unit: Unit) -> int:
	return unit.type.min_range


## The furthest tile this unit can fire at, after its commander's doctrine.
static func maximum(state: GameState, unit: Unit) -> int:
	if unit.type.max_range <= 0:
		return 0  # unarmed: no doctrine may hand an APC a weapon
	return unit.type.max_range + state.commander_of(unit.team).range_bonus(state, unit)


## True when a shot fired from `from` reaches `target`.
static func covers(state: GameState, unit: Unit, from: Vector2i, target: Vector2i) -> bool:
	if unit.type.max_range <= 0:
		return false
	var dist := absi(target.x - from.x) + absi(target.y - from.y)
	return dist >= minimum(state, unit) and dist <= maximum(state, unit)


## True for a unit that shoots over distance: it cannot move and fire, never
## counters, and is never countered. A property of the weapon, so it is read
## from the type and no doctrine turns a direct unit into an indirect one.
static func is_indirect(unit: Unit) -> bool:
	return unit.type.min_range > 1
