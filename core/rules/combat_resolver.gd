class_name CombatResolver
extends RefCounted
## Resolves combat. The formula, normative — every general is balance-tested
## against exactly this chain, in exactly this order, with exactly one rounding
## at the end:
##
##   stars  = clamp(cover(defender) + def_co.star_bonus - att_co.star_pierce, 0, 5)
##   att    = 100 + att_co.attack_bonus
##   def    = 100 + def_co.defense_bonus
##   raw    = base(attacker, defender)
##            x att / 100
##            x attacker_displayed_hp / 10
##            x (1 - 0.1 x stars x defender_displayed_hp / 10)
##            x (200 - def) / 100
##   damage = max(0, round(raw))     + luck   [resolve only; forecast omits it]
##
## The (200 - def) / 100 term is the Advance Wars defence shape: +10 defence is
## x0.9 damage taken, -10 is x1.1. With the neutral commander both att and def
## are 100 and the two new terms are exactly 1.0, so a match with no CO resolves
## bit-for-bit as it did before commanders existed.
##
## `cover` is the defender's terrain stars, except that a unit in the air is not
## standing on the tile under it and gets none — see _cover_stars. Ground and sea
## units read the terrain exactly as they always did.
##
## Damage% subtracts internal HP (0-100) directly. Luck comes from the
## GameState's seeded RNG, and its bounds come from the attacking commander, so
## matches stay deterministic and replayable either way.
##
## Both forecast() and resolve() go through _damage_pct, which is what keeps the
## damage preview honest about doctrines for free.

const LUCK_MAX := CommanderType.LUCK_MAX


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
	## Displayed HP (1-10) each side went into the exchange with, snapshotted by
	## `resolve` before a point of it is spent.
	##
	## The only thing in this file that exists for the presentation layer. By the
	## time the battle cut-in is handed a result the command has already applied,
	## so both units hold their *post*-combat HP and the animation has nothing to
	## count down from. Recorded here rather than re-derived there, because the
	## cut-in must replay the exchange and never recompute it — a second opinion
	## on combat is exactly the bug class this repo already paid for once with
	## movement. Nothing in core/ or ai/ reads these.
	var attacker_hp_before := 0
	var defender_hp_before := 0


## Luck-free prediction for the damage preview. `attacker_cell` is the planned
## firing position (the move is usually not committed yet). The counter uses
## the defender's projected post-attack HP, like Advance Wars shows it.
static func forecast(
	state: GameState, attacker: Unit, attacker_cell: Vector2i, defender: Unit
) -> Forecast:
	return forecast_at(state, attacker, attacker_cell, defender, defender.cell)


## The same prediction with the defender's position given explicitly, for a
## caller asking about a cell the defender has not moved to — the AI's threat
## map scoring "how hard am I hit if I stop here?".
##
## Both positions are effective values carried by Engagement, exactly like the
## attacker's planned firing cell, so asking the question moves nothing on the
## board: this is a pure query whatever cell it is asked about.
static func forecast_at(
	state: GameState,
	attacker: Unit,
	attacker_cell: Vector2i,
	defender: Unit,
	defender_cell: Vector2i
) -> Forecast:
	var result := Forecast.new()
	if not attacker.has_ammo():
		return result
	var damage := _damage_pct(
		state,
		Engagement.create(
			attacker,
			attacker_cell,
			attacker.displayed_hp(),
			defender,
			defender_cell,
			defender.displayed_hp()
		)
	)
	if damage < 0:
		return result
	result.can_attack = true
	result.attack_damage = damage
	var hp_after := maxi(0, defender.hp - damage)
	if (
		hp_after > 0
		and _defender_can_counter(state, defender, defender_cell, attacker, attacker_cell)
	):
		result.counter_damage = _damage_pct(
			state,
			Engagement.create(
				defender,
				defender_cell,
				ceili(hp_after / 10.0),
				attacker,
				attacker_cell,
				attacker.displayed_hp(),
				true
			)
		)
	return result


## Applies the attack (with luck), then the counter-attack if the defender
## survives and can reach. Dead units are removed from the state, and both sides
## bank Command Power charge for the HP that changed hands.
static func resolve(state: GameState, attacker: Unit, defender: Unit) -> CombatResult:
	var result := CombatResult.new()
	var fight := Engagement.create(
		attacker,
		attacker.cell,
		attacker.displayed_hp(),
		defender,
		defender.cell,
		defender.displayed_hp()
	)
	# Taken off the Engagement, not the units: those are the effective values the
	# formula below is about to be resolved with, so the snapshot can never drift
	# from the exchange it describes.
	result.attacker_hp_before = fight.attacker_hp
	result.defender_hp_before = fight.defender_hp
	var base := _damage_pct(state, fight)
	if base < 0:
		push_error("CombatResolver: %s cannot attack %s" % [attacker.type.id, defender.type.id])
		return result
	if attacker.type.max_ammo > 0:
		attacker.ammo = maxi(0, attacker.ammo - 1)
	result.attack_damage = base + _luck(state, fight)
	# Banked before the unit is removed: a kill charges for the HP it actually
	# took off, not for the overkill the roll happened to produce.
	state.bank_losses(defender, mini(result.attack_damage, defender.hp), attacker.team)
	defender.hp = maxi(0, defender.hp - result.attack_damage)
	if defender.hp == 0:
		result.defender_died = true
		_bank_cargo_losses(state, defender, attacker.team)
		state.remove_unit(defender)
		return result
	if not _defender_can_counter(state, defender, defender.cell, attacker, attacker.cell):
		return result
	var counter := Engagement.create(
		defender,
		defender.cell,
		defender.displayed_hp(),
		attacker,
		attacker.cell,
		attacker.displayed_hp(),
		true
	)
	var counter_base := _damage_pct(state, counter)
	if counter_base < 0:
		return result
	if defender.type.max_ammo > 0:
		defender.ammo = maxi(0, defender.ammo - 1)
	result.countered = true
	result.counter_damage = counter_base + _luck(state, counter)
	state.bank_losses(attacker, mini(result.counter_damage, attacker.hp), defender.team)
	attacker.hp = maxi(0, attacker.hp - result.counter_damage)
	if attacker.hp == 0:
		result.attacker_died = true
		_bank_cargo_losses(state, attacker, defender.team)
		state.remove_unit(attacker)
	return result


## Cargo that drowns with its transport banks the same as if each passenger had
## been killed in the open: the value basis is the passenger's remaining HP
## fraction of its cost, split by the same loser/dealer rates bank_losses gives
## the transport itself. Recurses because remove_unit's erase does — an old save
## may nest transports even though the load commands now refuse it. This runs
## before remove_unit so cargo_of can still see the passengers, and stays here in
## the resolver where every other charge accrual lives; the fuel-crash death in
## turn_rules erases cargo without a fight and deliberately banks nothing.
static func _bank_cargo_losses(state: GameState, transport: Unit, dealer_team: int) -> void:
	for passenger in state.cargo_of(transport):
		state.bank_losses(passenger, passenger.hp, dealer_team)
		_bank_cargo_losses(state, passenger, dealer_team)


static func _defender_can_counter(
	state: GameState,
	defender: Unit,
	defender_cell: Vector2i,
	attacker: Unit,
	attacker_cell: Vector2i
) -> bool:
	# Deliberately the unit type's own range rather than AttackRange: countering
	# is adjacency, and a doctrine that extends how far a unit can *initiate*
	# must not turn an indirect into something that shoots back. Only the
	# distance is decided here, though — whether the shot is possible at all is
	# AttackRange's, below.
	if defender.type.max_range != 1:
		return false  # unarmed and indirect units never counter
	if not defender.has_ammo():
		return false
	if defender.dived:
		return false  # a submarine that is hiding does not give itself away
	var dist := absi(attacker_cell.x - defender_cell.x) + absi(attacker_cell.y - defender_cell.y)
	if dist != 1:
		return false  # an indirect attacker fires from beyond counter reach
	# The same authority the opening shot went through, which is what gives the
	# dive its edge: a submerged attacker is countered only by a hunter that can
	# reach under the surface, and shrugged at by everything else.
	return AttackRange.can_engage(state, defender, attacker)


## One luck roll, from the attacking commander's range. Always exactly one draw
## from the match RNG whatever the range, so a doctrine that narrows luck cannot
## put a replay out of step with the seed it was recorded on.
static func _luck(state: GameState, fight: Engagement) -> int:
	var att_co := state.commander_of(fight.attacker.team)
	var low := att_co.luck_min(state, fight)
	return state.rng.randi_range(low, maxi(low, att_co.luck_max(state, fight)))


## The terrain cover the defender actually gets. A unit in the air is over the
## tile rather than on it, so mountains and woods do nothing for it — the one
## place the formula asks what a defender *is* instead of only where it stands.
##
## Deliberately only the terrain half: a commander's star_bonus is still added on
## top by the caller, so a doctrine that hardens its army hardens its planes with
## it. What the ground gives is the part a plane is not entitled to.
static func _cover_stars(state: GameState, fight: Engagement) -> int:
	if fight.defender.type.domain == UnitType.AIR:
		return 0
	return state.map.terrain_at(fight.defender_cell).defense_stars


static func _damage_pct(state: GameState, fight: Engagement) -> int:
	var base := state.damage_chart.base_damage(fight.attacker.type.id, fight.defender.type.id)
	if base < 0:
		return -1
	var att_co := state.commander_of(fight.attacker.team)
	var def_co := state.commander_of(fight.defender.team)
	var stars := clampi(
		(
			_cover_stars(state, fight)
			+ def_co.star_bonus(state, fight)
			- att_co.star_pierce(state, fight)
		),
		0,
		CommanderType.MAX_STARS
	)
	var att := 100 + att_co.attack_bonus(state, fight)
	var def := 100 + def_co.defense_bonus(state, fight)
	var raw := (
		base
		* (att / 100.0)
		* (fight.attacker_hp / 10.0)
		* (1.0 - 0.1 * stars * fight.defender_hp / 10.0)
		* ((200 - def) / 100.0)
	)
	return maxi(0, roundi(raw))
