class_name AlinaWard
extends CommanderType
## Meridian Coalition. Combined arms: her units hit harder when they fight
## alongside a different kind of unit, so her strength is a mixed, coordinated
## line rather than a stack of the same thing. Coordinated Push then moves that
## whole line at once.

## Percentage points added when a friendly of another movement class stands next
## to the firing unit.
@export var combined_arms_pct: int = 10
@export var push_attack_pct: int = 10
@export var push_defense_pct: int = 10
@export var push_move_bonus: int = 1


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := 0
	if _has_mixed_neighbour(state, fight.attacker, fight.attacker_cell):
		bonus += combined_arms_pct
	if _is_active(state, fight.attacker.team):
		bonus += push_attack_pct
	return bonus


func defense_bonus(state: GameState, fight: Engagement) -> int:
	return push_defense_pct if _is_active(state, fight.defender.team) else 0


func move_bonus(state: GameState, unit: Unit) -> int:
	return push_move_bonus if _is_active(state, unit.team) else 0


## A friendly of a *different* movement class on one of the four cells around
## `from`, which is where the shot is fired from — during a damage preview that
## is where the unit is about to stand, not where it is. The unit itself is
## therefore skipped: it is still sitting on its old cell, and finding itself
## there would never count anyway (same team, same class).
func _has_mixed_neighbour(state: GameState, unit: Unit, from: Vector2i) -> bool:
	for dir in MovementResolver.DIRECTIONS:
		var other := state.unit_at(from + dir)
		if other == null or other == unit or other.team != unit.team:
			continue
		if other.type.move_class != unit.type.move_class:
			return true
	return false
