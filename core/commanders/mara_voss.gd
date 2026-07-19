class_name MaraVoss
extends CommanderType
## Iron Dominion. A defensive doctrine in an aggressive faction: her direct
## units punish being attacked and are mediocre at starting fights, so she wants
## the opponent to come to her. Hold the Line is the only ROUND power on the
## roster — it has to survive her own end of turn to cover the turn it exists to
## defend against.
##
## The first doctrine to read Engagement.is_counter, which is why the flag is on
## the exchange rather than inferred by the resolver.

@export var counter_attack_pct: int = 20
## Negative on purpose: she is paid to receive attacks, not to open them.
@export var initiate_attack_pct: int = -10
@export var hold_defense_pct: int = 30
@export var hold_counter_pct: int = 40


## Indirect units never counter at all, so neither half applies to them.
func attack_bonus(state: GameState, fight: Engagement) -> int:
	if AttackRange.is_indirect(fight.attacker):
		return 0
	if not fight.is_counter:
		return initiate_attack_pct
	var bonus := counter_attack_pct
	if is_active(state, fight.attacker.team):
		bonus += hold_counter_pct
	return bonus


func defense_bonus(state: GameState, fight: Engagement) -> int:
	return hold_defense_pct if is_active(state, fight.defender.team) else 0
