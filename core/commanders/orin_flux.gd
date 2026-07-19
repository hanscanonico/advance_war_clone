class_name OrinFlux
extends CommanderType
## Aurora Compact. Intelligence: he sees further than anyone and, for a round,
## makes sure nobody else does. Signal Jam is the only power that reaches across
## the table, and it uses both halves of the power machinery — a one-shot strip
## of fuel and ammo, and an ongoing debuff that lasts until the jamming lifts.
##
## ROUND duration, so "enemy vision -1 until their next turn" means what it says:
## it has to still be running while the opponent plays.

@export var scout_ids: Array[StringName] = [&"recon", &"apc"]
@export var scout_vision_bonus: int = 1
@export var jam_vision_penalty: int = -1
@export var jam_fuel_loss: int = 10
@export var jam_ammo_loss: int = 1


func vision_bonus(_state: GameState, unit: Unit) -> int:
	return scout_vision_bonus if unit.type.id in scout_ids else 0


## Asked of *his* commander about an enemy unit, which is what makes this the
## one hook a doctrine uses to reach the other side of the board. Vision floors
## the total at 0, so a jammed scout goes blind rather than inside-out.
func enemy_vision_bonus(state: GameState, unit: Unit) -> int:
	return jam_vision_penalty if is_active(state, _opponent_of(unit.team)) else 0


func on_power_activated(state: GameState, team: int) -> void:
	for unit in state.units:
		if unit.team == team:
			continue
		unit.fuel = maxi(0, unit.fuel - jam_fuel_loss)
		if unit.type.max_ammo > 0:
			unit.ammo = maxi(0, unit.ammo - jam_ammo_loss)


## Whose commander is being asked about `team`'s units. Two-sided today; the
## first team that is not this one, so a third side would not silently break it.
func _opponent_of(team: int) -> int:
	for other in GameState.TEAMS:
		if other != team:
			return other
	return team
