class_name LyraQuill
extends CommanderType
## Aurora Compact. Precision: her damage rolls never come up short, so every
## attack lands where the forecast said it would, and she pays for that
## certainty with a thinner margin everywhere else. Perfect Solution removes the
## roll entirely for a turn.
##
## The only doctrine that touches luck. It narrows the range rather than
## replacing the roll, so exactly one number still comes off the seeded RNG per
## attack and a replay recorded on that seed stays in step.

@export var lucky_floor: int = 4
## Negative on purpose: consistency is not free.
@export var defense_pct: int = -5
@export var solution_attack_pct: int = 10


func luck_min(state: GameState, fight: Engagement) -> int:
	if is_active(state, fight.attacker.team):
		return LUCK_MAX  # every roll is the best one
	return lucky_floor


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return defense_pct


func attack_bonus(state: GameState, fight: Engagement) -> int:
	return solution_attack_pct if is_active(state, fight.attacker.team) else 0
