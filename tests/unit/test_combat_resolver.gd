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
	var forecast := CombatResolver.forecast(
		state, state.units[0], Vector2i(0, 0), state.units[1]
	)
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
	var forecast := CombatResolver.forecast(
		state, state.units[0], Vector2i(0, 0), state.units[1]
	)
	assert_eq(forecast.attack_damage, 25)


func test_forecast_unarmed_attacker_cannot_attack() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 p 0 0\n2 i 1 0")
	var forecast := CombatResolver.forecast(
		state, state.units[0], Vector2i(0, 0), state.units[1]
	)
	assert_false(forecast.can_attack)


func test_forecast_no_counter_from_indirect_defender() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 g 1 0")
	var forecast := CombatResolver.forecast(
		state, state.units[0], Vector2i(0, 0), state.units[1]
	)
	assert_true(forecast.can_attack)
	assert_eq(forecast.counter_damage, -1, "artillery never counters")


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
