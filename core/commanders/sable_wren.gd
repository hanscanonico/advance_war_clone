class_name SableWren
extends CommanderType
## Verdant League. Ambush doctrine: her army is worth more in cover than in the
## open, to the point of being punished for using roads. Vanish makes that cover
## absolute for a round.
##
## Vanish is the reworked version (decision D4). As originally written — "units
## in Woods can only be revealed from an adjacent tile" — it was a no-op, because
## Vision already hides *everyone's* woods units from non-adjacent viewers. So it
## became true invisibility: while the power runs her woods units are hidden even
## from an adjacent enemy, and the only thing that finds one is trying to move
## into its cell, which the movement rules already refuse.
##
## ROUND duration, unlike every other wave-2 power. An ambush that expired at the
## end of her own turn would never be there when the opponent walked into it.

@export var woods_star_bonus: int = 1
## Negative on purpose: the price of the cover bonus is being caught in the open.
@export var road_defense_pct: int = -10
@export var cover_terrain: StringName = &"woods"
@export var road_terrain: StringName = &"road"
@export var ambush_attack_pct: int = 40


func star_bonus(state: GameState, fight: Engagement) -> int:
	return woods_star_bonus if _terrain_at(state, fight.defender_cell) == cover_terrain else 0


func defense_bonus(state: GameState, fight: Engagement) -> int:
	return road_defense_pct if _terrain_at(state, fight.defender_cell) == road_terrain else 0


## The ambush itself. "First attack from Woods" and "an attack from Woods" are
## the same thing in practice — a unit acts once per turn — so this does not
## carry per-unit state it would then have to save and restore.
func attack_bonus(state: GameState, fight: Engagement) -> int:
	if not is_active(state, fight.attacker.team):
		return 0
	return ambush_attack_pct if _terrain_at(state, fight.attacker_cell) == cover_terrain else 0


func hides_unit(state: GameState, unit: Unit) -> bool:
	return is_active(state, unit.team) and _terrain_at(state, unit.cell) == cover_terrain


func _terrain_at(state: GameState, cell: Vector2i) -> StringName:
	var terrain := state.map.terrain_at(cell)
	return terrain.id if terrain != null else &""
