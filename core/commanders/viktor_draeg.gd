class_name ViktorDraeg
extends CommanderType
## Iron Dominion. Armour doctrine, paid for at the bottom of the roster: his
## tanks hit noticeably harder and his foot units noticeably softer, so he wants
## an expensive army and punishes a cheap one. Armoured Breakthrough turns that
## armour loose for a turn, terrain cover included.

@export var armour_ids: Array[StringName] = [&"tank", &"md_tank"]
@export var armour_attack_pct: int = 15
@export var foot_ids: Array[StringName] = [&"infantry", &"mech"]
## Negative on purpose: the price of the armour bonus above.
@export var foot_attack_pct: int = -10
## The class Breakthrough moves and un-covers. Everything else sits it out.
@export var breakthrough_class: StringName = TerrainType.TREADS
@export var breakthrough_move_bonus: int = 1
@export var breakthrough_star_pierce: int = 1


func attack_bonus(_state: GameState, fight: Engagement) -> int:
	var id := fight.attacker.type.id
	if id in armour_ids:
		return armour_attack_pct
	if id in foot_ids:
		return foot_attack_pct
	return 0


## One terrain defence star ignored while Breakthrough runs — CombatResolver
## clamps the result at 0, so piercing a road's cover is simply no gain.
func star_pierce(state: GameState, fight: Engagement) -> int:
	if not is_active(state, fight.attacker.team):
		return 0
	return breakthrough_star_pierce if fight.attacker.type.move_class == breakthrough_class else 0


func move_bonus(state: GameState, unit: Unit) -> int:
	if not is_active(state, unit.team):
		return 0
	return breakthrough_move_bonus if unit.type.move_class == breakthrough_class else 0
