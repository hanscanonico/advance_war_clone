extends GutTest
## The hook layer itself: that the neutral commander really is neutral, and that
## the damage formula's golden values do not move.
##
## This file is the R1 guard. Every general is balance-tested against the chain
## in CombatResolver's header, so a reordered multiplier or a second rounding has
## to fail here before it can quietly re-balance twelve doctrines at once.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func _fight(attacker: Unit, defender: Unit) -> Engagement:
	return Engagement.create(
		attacker,
		attacker.cell,
		attacker.displayed_hp(),
		defender,
		defender.cell,
		defender.displayed_hp()
	)


# --- the neutral commander ---------------------------------------------------


func test_teams_start_neutral() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	for team in GameState.TEAMS:
		assert_eq(state.commander_of(team).id, CommanderType.NEUTRAL_ID)
		assert_false(state.commander_of(team).has_power())
		assert_false(state.power_active(team))
		assert_eq(state.commander_state(team).charge, 0)


func test_neutral_hooks_return_the_pre_commander_rules() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var tank := state.units[0]
	var infantry := state.units[1]
	var co := state.commander_of(1)
	var fight := _fight(tank, infantry)
	assert_eq(co.attack_bonus(state, fight), 0)
	assert_eq(co.defense_bonus(state, fight), 0)
	assert_eq(co.star_bonus(state, fight), 0)
	assert_eq(co.star_pierce(state, fight), 0)
	assert_eq(co.luck_min(state, fight), 0)
	assert_eq(co.luck_max(state, fight), 9)
	assert_eq(co.move_bonus(state, tank), 0)
	assert_eq(co.range_bonus(state, tank), 0)
	assert_eq(co.vision_bonus(state, tank), 0)
	assert_eq(co.enemy_vision_bonus(state, tank), 0)
	assert_false(co.sees_into_woods(state, tank))
	assert_false(co.hides_unit(state, tank))
	assert_eq(co.capture_bonus_pct(state, tank), 0)
	assert_eq(co.supply_range(state, tank), 1)
	assert_eq(co.repair_cost_pct(state, tank), 100)
	var plains := terrain_db.by_symbol(".")
	assert_eq(co.terrain_cost(state, tank, plains, 1), 1, "neutral passes the base cost through")


## Golden values, hand-computed from the formula in CombatResolver's header with
## att = def = 100. These are the numbers every doctrine's percentage points
## are applied on top of; if one of them moves, the whole roster re-balances.
func test_golden_damage_matrix_for_the_neutral_commander() -> void:
	# map, attacker, defender, expected damage
	var cases: Array = [
		# tank -> infantry, base 25
		["[terrain]\n==\n[units]\n1 t 0 0\n2 i 1 0", 25],  # 0 stars: 25 * 1.0
		["[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", 23],  # plains 1*: 25 * 0.9 = 22.5
		["[terrain]\n.F\n[units]\n1 t 0 0\n2 i 1 0", 20],  # woods 2*: 25 * 0.8
		["[terrain]\n.C\n[units]\n1 t 0 0\n2 i 1 0", 18],  # city 3*: 25 * 0.7 = 17.5
		["[terrain]\n.M\n[units]\n1 t 0 0\n2 i 1 0", 15],  # mountain 4*: 25 * 0.6
		# infantry -> tank, base 5
		["[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0", 5],  # plains 1*: 5 * 0.9 = 4.5
	]
	for case: Array in cases:
		var state := _state(case[0])
		var forecast := CombatResolver.forecast(
			state, state.units[0], state.units[0].cell, state.units[1]
		)
		assert_eq(forecast.attack_damage, case[1], "%s" % case[0])


## Damage scales on *displayed* HP, and a damaged defender hides behind terrain
## less well. Pinned here because both terms sit inside the same multiplier
## chain the doctrines hook into.
func test_golden_damage_matrix_for_damaged_units() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.units[0].hp = 50  # 5 displayed
	# 25 * 0.5 * (1 - 0.1 * 1 * 1.0) = 11.25 -> 11
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		11
	)
	state.units[0].hp = 100
	state.units[1].hp = 50  # 5 displayed: terrain shields it half as well
	# 25 * 1.0 * (1 - 0.1 * 1 * 0.5) = 23.75 -> 24
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		24
	)


## The plan's C1 acceptance criterion: a match nobody picked a commander for
## must play exactly as it did before commanders existed. Same seed and the same
## commands have to land on the same board, down to HP and funds.
func test_a_no_commander_match_is_unchanged() -> void:
	var first := _play_scripted_match()
	var second := _play_scripted_match()
	for key: String in first:
		assert_eq(first[key], second[key], "same seed + same commands must agree on %s" % key)
	# Recorded from the pre-commander rules. A doctrine leaking into a neutral
	# match — a hook called on the wrong side, a stray multiplier — moves these.
	assert_eq(first["red_hp"], 89, "red tank HP after the exchange")
	assert_eq(first["blue_hp"], 81, "blue infantry HP after the exchange")
	assert_eq(first["day"], 2)
	assert_eq(first["red_funds"], 2000, "two properties, two turns of income")


## Fixed seed, fixed command list: attack, end turn, end turn.
func _play_scripted_match() -> Dictionary:
	var state := _state("[terrain]\n.C.\n.C.\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 424242
	state.set_owner(Vector2i(1, 0), 1)
	state.set_owner(Vector2i(1, 1), 1)
	AttackCommand.new(state.units[0], [Vector2i(0, 0)], Vector2i(1, 0)).apply(state)
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	return {
		"red_hp": state.units_of(1)[0].hp,
		"blue_hp": state.units_of(2)[0].hp,
		"day": state.day,
		"red_funds": state.funds[1],
	}


# --- the commander database --------------------------------------------------


func test_db_always_answers_with_a_commander() -> void:
	var db := CommanderDB.load_default()
	assert_true(db.has(CommanderType.NEUTRAL_ID), "neutral is always registered")
	assert_eq(db.by_id(&"alina_ward").display_name, "Alina Ward")
	assert_eq(
		db.by_id(&"a_general_who_was_cut").id,
		CommanderType.NEUTRAL_ID,
		"an unknown id falls back to neutral so an old save still loads"
	)


func test_every_shipped_commander_is_well_formed() -> void:
	var db := CommanderDB.load_default()
	for co in db.all():
		if co.id == CommanderType.NEUTRAL_ID:
			continue
		assert_ne(co.display_name, "", "%s needs a name" % co.id)
		assert_ne(co.faction, "", "%s needs a faction" % co.id)
		assert_ne(co.power_name, "", "%s needs a power name" % co.id)
		assert_gt(co.power_cost, 0, "%s needs a power cost" % co.id)
