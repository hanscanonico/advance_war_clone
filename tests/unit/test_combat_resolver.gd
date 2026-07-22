extends GutTest

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


func test_chart_loads() -> void:
	assert_eq(chart.base_damage(&"tank", &"infantry"), 25)
	assert_eq(chart.base_damage(&"infantry", &"tank"), 5)
	assert_eq(chart.base_damage(&"apc", &"tank"), -1, "APC is unarmed")
	assert_true(chart.can_attack(&"rockets", &"md_tank"))
	assert_false(chart.can_attack(&"apc", &"infantry"))


func test_forecast_full_hp_on_plains() -> void:
	# tank vs infantry on plains (1 star): 25 * 1.0 * 0.9 = 22.5 -> 23
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0")
	var forecast := CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
	assert_true(forecast.can_attack)
	assert_eq(forecast.attack_damage, 23)
	# counter: infantry at 8 HP (77 internal) vs tank on plains:
	# 5 * 0.8 * 0.9 = 3.6 -> 4
	assert_eq(forecast.counter_damage, 4)


func test_forecast_ignores_luck_and_respects_terrain() -> void:
	# road has 0 defense stars: tank vs infantry = flat 25
	var road_state := _state("[terrain]\n==\n[units]\n1 t 0 0\n2 i 1 0")
	var road_forecast := CombatResolver.forecast(
		road_state, road_state.units[0], Vector2i(0, 0), road_state.units[1]
	)
	assert_eq(road_forecast.attack_damage, 25)
	# mountain (4 stars) shields the defender: 25 * 1.0 * 0.6 = 15
	var mountain_state := _state("[terrain]\n.M\n[units]\n1 t 0 0\n2 i 1 0")
	var mountain_forecast := CombatResolver.forecast(
		mountain_state, mountain_state.units[0], Vector2i(0, 0), mountain_state.units[1]
	)
	assert_eq(mountain_forecast.attack_damage, 15)


func test_forecast_damaged_attacker_scales() -> void:
	# tank at 5 displayed HP: 55 * 0.5 * 0.9 = 24.75 -> 25 vs full tank
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.units[0].hp = 50
	var forecast := CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
	assert_eq(forecast.attack_damage, 25)


func test_forecast_unarmed_attacker_cannot_attack() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 p 0 0\n2 i 1 0")
	var forecast := CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
	assert_false(forecast.can_attack)


func test_forecast_no_counter_from_indirect_defender() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 g 1 0")
	var forecast := CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
	assert_true(forecast.can_attack)
	assert_eq(forecast.counter_damage, -1, "artillery never counters")


## forecast() is the convenience for the defender's real cell, so the two must
## agree there or every existing caller has quietly changed answer.
func test_forecast_at_the_defenders_own_cell_matches_forecast() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0")
	var convenience := CombatResolver.forecast(
		state, state.units[0], Vector2i(0, 0), state.units[1]
	)
	var explicit := CombatResolver.forecast_at(
		state, state.units[0], Vector2i(0, 0), state.units[1], state.units[1].cell
	)
	assert_eq(explicit.can_attack, convenience.can_attack)
	assert_eq(explicit.attack_damage, convenience.attack_damage)
	assert_eq(explicit.counter_damage, convenience.counter_damage)


## The point of the explicit cell: the cover the defender *would* have there,
## not the cover it has now.
func test_forecast_at_reads_the_cover_of_the_cell_it_is_given() -> void:
	# The infantry stands on road (0 stars); the mountain beside it is 4.
	var state := _state("[terrain]\n.=M.\n[units]\n1 t 3 0\n2 i 1 0")
	var tank := state.units[0]
	var infantry := state.units[1]
	var on_road := CombatResolver.forecast(state, tank, Vector2i(3, 0), infantry)
	var on_mountain := CombatResolver.forecast_at(
		state, tank, Vector2i(3, 0), infantry, Vector2i(2, 0)
	)
	assert_eq(on_road.attack_damage, 25, "where it actually stands: road, 25 * 1.0")
	assert_eq(on_mountain.attack_damage, 15, "where it is asked about: mountain, 25 * 0.6")


## The counter is a question about distance, so it has to be measured from the
## effective cell too — a defender that could not reach the attacker from where
## it stands may well reach it from the cell being scored.
func test_forecast_at_measures_the_counter_from_the_effective_cell() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n2 i 3 0")
	var tank := state.units[0]
	var infantry := state.units[1]
	var far := CombatResolver.forecast_at(state, tank, Vector2i(0, 0), infantry, Vector2i(3, 0))
	var beside := CombatResolver.forecast_at(state, tank, Vector2i(0, 0), infantry, Vector2i(1, 0))
	assert_eq(far.counter_damage, -1, "three tiles from the tank nothing shoots back")
	# Beside the tank the counter lands: 5 * 0.8 * 0.9 = 3.6 -> 4.
	assert_eq(beside.counter_damage, 4, "asked about the cell beside the tank, it is answered")


## The whole reason the parameter exists: asking about a cell is a pure read.
func test_forecast_at_never_moves_the_defender() -> void:
	var state := _state("[terrain]\n.M..\n[units]\n1 t 0 0\n2 i 3 0")
	var infantry := state.units[1]
	CombatResolver.forecast_at(state, state.units[0], Vector2i(0, 0), infantry, Vector2i(1, 0))
	assert_eq(infantry.cell, Vector2i(3, 0), "the defender was never stood anywhere")
	assert_eq(state.unit_at(Vector2i(3, 0)), infantry, "and the board still finds it there")
	assert_null(state.unit_at(Vector2i(1, 0)), "the measured cell stayed empty")


func test_resolve_luck_bounds_and_hp() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 1234
	var defender := state.units[1]
	var result := CombatResolver.resolve(state, state.units[0], defender)
	assert_between(result.attack_damage, 23, 23 + CombatResolver.LUCK_MAX)
	assert_eq(defender.hp, 100 - result.attack_damage)
	assert_true(result.countered)
	assert_between(result.counter_damage, 4, 4 + CombatResolver.LUCK_MAX)


func test_resolve_is_deterministic_for_same_seed() -> void:
	var damages: Array[int] = []
	for run in 2:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 t 1 0")
		state.rng.seed = 99
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		damages.append(result.attack_damage)
		damages.append(result.counter_damage)
	assert_eq(damages[0], damages[2], "same seed must give the same attack roll")
	assert_eq(damages[1], damages[3], "same seed must give the same counter roll")


func test_resolve_kill_removes_defender_and_skips_counter() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 7
	var defender := state.units[1]
	defender.hp = 10  # any hit kills
	var result := CombatResolver.resolve(state, state.units[0], defender)
	assert_true(result.defender_died)
	assert_false(result.countered)
	assert_eq(defender.hp, 0)
	assert_null(state.unit_at(Vector2i(1, 0)))
	assert_eq(state.units.size(), 1)


func test_resolve_counter_can_kill_attacker() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 m 1 0")
	state.rng.seed = 5
	var attacker := state.units[0]
	attacker.hp = 10  # 1 displayed HP; the mech's counter will kill
	var result := CombatResolver.resolve(state, attacker, state.units[1])
	assert_false(result.defender_died)
	assert_true(result.countered)
	assert_true(result.attacker_died)
	assert_eq(attacker.hp, 0)
	assert_null(state.unit_at(Vector2i(0, 0)))


func test_resolve_no_counter_beyond_adjacency() -> void:
	# artillery fires from range 2; the tank defender cannot counter
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 t 2 0")
	state.rng.seed = 3
	var result := CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_gt(result.attack_damage, 0)
	assert_false(result.countered)


func test_resolve_unarmed_defender_cannot_counter() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 3
	var result := CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_false(result.countered)


## A unit in the air is over the tile rather than on it, so the ground gives it
## nothing. Without this an aircraft parked over a mountain would be the hardest
## target in the game, which is not what a mountain is for.
func test_terrain_gives_aircraft_no_cover() -> void:
	var over_plains := _state("[terrain]\n..\n[units]\n1 a 0 0\n2 h 1 0")
	var over_mountain := _state("[terrain]\n.M\n[units]\n1 a 0 0\n2 h 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(over_plains, over_plains.units[0], Vector2i(0, 0), over_plains.units[1])
			. attack_damage
		),
		(
			CombatResolver
			. forecast(
				over_mountain, over_mountain.units[0], Vector2i(0, 0), over_mountain.units[1]
			)
			. attack_damage
		),
		"a helicopter takes the same damage whatever it happens to be flying over"
	)


## The other half of the same rule: ground units read the terrain exactly as they
## always did, so nothing about the base game's cover changed.
func test_terrain_still_covers_ground_units() -> void:
	var on_plains := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	var in_woods := _state("[terrain]\n.F\n[units]\n1 t 0 0\n2 t 1 0")
	assert_gt(
		(
			CombatResolver
			. forecast(on_plains, on_plains.units[0], Vector2i(0, 0), on_plains.units[1])
			. attack_damage
		),
		(
			CombatResolver
			. forecast(in_woods, in_woods.units[0], Vector2i(0, 0), in_woods.units[1])
			. attack_damage
		),
		"woods should still soften a hit on a tank"
	)
