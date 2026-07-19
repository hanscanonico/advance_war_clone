class_name RheaSol
extends CommanderType
## Meridian Coalition. Artillery doctrine: her indirect units hit harder and
## fold faster, so she wants a siege line with something else standing in front
## of it. Grid Saturation pushes that line one tile further out for a turn,
## which is the strongest tempo swing in wave 1 — a range her opponent set up
## against last turn is suddenly wrong.
##
## Keyed on being indirect rather than on unit ids: "artillery and rockets" is
## what the doctrine means today, and a future siege unit should inherit it.

@export var indirect_attack_pct: int = 10
## Negative on purpose: siege guns are soft, and this is what pays for the
## attack bonus above.
@export var indirect_defense_pct: int = -10
@export var saturation_attack_pct: int = 20
@export var saturation_range_bonus: int = 1


func attack_bonus(state: GameState, fight: Engagement) -> int:
	if not AttackRange.is_indirect(fight.attacker):
		return 0
	var bonus := indirect_attack_pct
	if is_active(state, fight.attacker.team):
		bonus += saturation_attack_pct
	return bonus


func defense_bonus(_state: GameState, fight: Engagement) -> int:
	return indirect_defense_pct if AttackRange.is_indirect(fight.defender) else 0


## The extra tile only reaches units that shoot over distance to begin with, so
## it never turns a direct unit into something that outranges a counter.
func range_bonus(state: GameState, unit: Unit) -> int:
	if not is_active(state, unit.team) or not AttackRange.is_indirect(unit):
		return 0
	return saturation_range_bonus
