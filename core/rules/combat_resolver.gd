class_name CombatResolver
extends RefCounted
## Resolves combat per the plan's formula:
##
##   damage% = base(attacker, defender)
##             x attacker_displayed_hp / 10
##             x (1 - 0.1 x terrain_stars x defender_displayed_hp / 10)
##             + luck(0..9)          [resolve only; forecast omits luck]
##
## Damage% subtracts internal HP (0-100) directly. Luck comes from the
## GameState's seeded RNG so matches stay deterministic and replayable.

const LUCK_MAX := 9


class Forecast:
	var can_attack := false
	var attack_damage := 0
	## -1 when no counter is possible (defender dead, indirect, unarmed
	## against the attacker, or the attacker fires from beyond range 1).
	var counter_damage := -1


class CombatResult:
	var attack_damage := 0
	var countered := false
	var counter_damage := 0
	var defender_died := false
	var attacker_died := false


## Luck-free prediction for the damage preview. `attacker_cell` is the planned
## firing position (the move is usually not committed yet). The counter uses
## the defender's projected post-attack HP, like Advance Wars shows it.
static func forecast(
	state: GameState, attacker: Unit, attacker_cell: Vector2i, defender: Unit
) -> Forecast:
	var result := Forecast.new()
	var damage := _damage_pct(
		state, attacker.type, attacker.displayed_hp(),
		defender.type, defender.displayed_hp(), defender.cell
	)
	if damage < 0:
		return result
	result.can_attack = true
	result.attack_damage = damage
	var hp_after := maxi(0, defender.hp - damage)
	if hp_after > 0 and _defender_can_counter(state, defender, attacker, attacker_cell):
		result.counter_damage = _damage_pct(
			state, defender.type, ceili(hp_after / 10.0),
			attacker.type, attacker.displayed_hp(), attacker_cell
		)
	return result


## Applies the attack (with luck), then the counter-attack if the defender
## survives and can reach. Dead units are removed from the state.
static func resolve(state: GameState, attacker: Unit, defender: Unit) -> CombatResult:
	var result := CombatResult.new()
	var base := _damage_pct(
		state, attacker.type, attacker.displayed_hp(),
		defender.type, defender.displayed_hp(), defender.cell
	)
	if base < 0:
		push_error("CombatResolver: %s cannot attack %s" % [attacker.type.id, defender.type.id])
		return result
	result.attack_damage = base + state.rng.randi_range(0, LUCK_MAX)
	defender.hp = maxi(0, defender.hp - result.attack_damage)
	if defender.hp == 0:
		result.defender_died = true
		state.remove_unit(defender)
		return result
	if not _defender_can_counter(state, defender, attacker, attacker.cell):
		return result
	var counter_base := _damage_pct(
		state, defender.type, defender.displayed_hp(),
		attacker.type, attacker.displayed_hp(), attacker.cell
	)
	if counter_base < 0:
		return result
	result.countered = true
	result.counter_damage = counter_base + state.rng.randi_range(0, LUCK_MAX)
	attacker.hp = maxi(0, attacker.hp - result.counter_damage)
	if attacker.hp == 0:
		result.attacker_died = true
		state.remove_unit(attacker)
	return result


static func _defender_can_counter(
	state: GameState, defender: Unit, attacker: Unit, attacker_cell: Vector2i
) -> bool:
	if defender.type.max_range != 1:
		return false  # unarmed and indirect units never counter
	var dist := absi(attacker_cell.x - defender.cell.x) + absi(attacker_cell.y - defender.cell.y)
	if dist != 1:
		return false  # an indirect attacker fires from beyond counter reach
	return state.damage_chart.can_attack(defender.type.id, attacker.type.id)


static func _damage_pct(
	state: GameState, att_type: UnitType, att_hp: int,
	def_type: UnitType, def_hp: int, def_cell: Vector2i
) -> int:
	var base := state.damage_chart.base_damage(att_type.id, def_type.id)
	if base < 0:
		return -1
	var stars := state.map.terrain_at(def_cell).defense_stars
	var raw := base * (att_hp / 10.0) * (1.0 - 0.1 * stars * def_hp / 10.0)
	return maxi(0, roundi(raw))
