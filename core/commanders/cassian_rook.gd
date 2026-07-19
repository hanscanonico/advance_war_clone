class_name CassianRook
extends CommanderType
## Aurora Compact. Deployment: his light units outrun everyone and his heavy
## ones hit softer, so he wins by being where the fight is not. Rapid
## Redeployment is the largest movement swing on the roster and deliberately
## costs him the turn's damage to use it — it repositions an army, it does not
## win a fight.

@export var light_ids: Array[StringName] = [&"recon", &"apc"]
@export var light_move_bonus: int = 1
@export var heavy_ids: Array[StringName] = [&"tank", &"md_tank"]
## Negative on purpose: the price of the mobility above.
@export var heavy_attack_pct: int = -10
@export var redeploy_move_bonus: int = 2
## Negative on purpose: a repositioning turn, not an attacking one.
@export var redeploy_attack_pct: int = -20


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := 0
	if fight.attacker.type.id in heavy_ids:
		bonus += heavy_attack_pct
	if is_active(state, fight.attacker.team):
		bonus += redeploy_attack_pct
	return bonus


func move_bonus(state: GameState, unit: Unit) -> int:
	var bonus := light_move_bonus if unit.type.id in light_ids else 0
	if is_active(state, unit.team):
		bonus += redeploy_move_bonus
	return bonus
