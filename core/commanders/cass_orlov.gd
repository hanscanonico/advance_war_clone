class_name CassOrlov
extends CommanderType
## Iron Dominion. A finisher: she is paid to close out wounded units and paid
## for it in her own durability, so her army trades well and holds badly. No
## Escape widens the definition of "wounded" from nearly-dead to merely hurt,
## which is what turns a good turn into a rout.

## Enemies at or below this displayed HP are worth the passive bonus.
@export var finish_hp: int = 5
@export var finish_attack_pct: int = 15
## Negative on purpose: what the bonus above costs her.
@export var defense_pct: int = -10
## No Escape counts anything short of full health as damaged.
@export var no_escape_hp: int = 9
@export var no_escape_attack_pct: int = 30
@export var no_escape_ids: Array[StringName] = [&"recon", &"tank"]
@export var no_escape_move_bonus: int = 1


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := 0
	if fight.defender_hp <= finish_hp:
		bonus += finish_attack_pct
	if _is_active(state, fight.attacker.team) and fight.defender_hp <= no_escape_hp:
		bonus += no_escape_attack_pct
	return bonus


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return defense_pct


func move_bonus(state: GameState, unit: Unit) -> int:
	if not _is_active(state, unit.team) or unit.type.id not in no_escape_ids:
		return 0
	return no_escape_move_bonus
