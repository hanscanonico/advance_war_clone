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


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


func test_units_start_with_full_tanks() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0")
	assert_eq(state.units[0].fuel, 70)
	assert_eq(state.units[0].ammo, 9)


func test_movement_spends_fuel_by_terrain_cost() -> void:
	# tank through woods: 2 + 2 internal cost
	var state := _state("[terrain]\n.FF\n[units]\n1 t 0 0")
	MoveCommand.new(state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])).apply(
		state
	)
	assert_eq(state.units[0].fuel, 70 - 4)


func test_fuel_caps_movement_range() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0")
	state.units[0].fuel = 1
	var reachable := MovementResolver.reachable(state, state.units[0])
	assert_true(reachable.has(Vector2i(1, 0)))
	assert_false(reachable.has(Vector2i(2, 0)), "fuel 1 only buys one plains step")


func test_move_without_fuel_rejected() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 i 0 0")
	state.units[0].fuel = 1
	var command := MoveCommand.new(
		state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	)
	assert_eq(command.validate(state), "not enough fuel")


func test_attack_and_counter_consume_ammo() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 T 1 0")
	state.rng.seed = 4
	CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_eq(state.units[0].ammo, 8, "attacker spent one shell")
	assert_eq(state.units[1].ammo, 7, "the counter-attack spent one too")


func test_out_of_ammo_blocks_attack() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.units[0].ammo = 0
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "out of ammo")
	var forecast := CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
	assert_false(forecast.can_attack)


func test_out_of_ammo_defender_cannot_counter() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.rng.seed = 4
	state.units[1].ammo = 0
	var result := CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_false(result.countered)


func test_infinite_ammo_units_never_run_dry() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 i 1 0")
	state.rng.seed = 4
	CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_true(state.units[0].has_ammo())
	assert_eq(state.units[0].ammo, 0, "machine guns track no ammo")


func test_turn_start_resupplies_on_friendly_property() -> void:
	var state := _state("[terrain]\nC.\n[owners]\n1 0 0\n[units]\n1 t 0 0")
	state.units[0].fuel = 5
	state.units[0].ammo = 1
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)  # back to red
	assert_eq(state.units[0].fuel, 70)
	assert_eq(state.units[0].ammo, 9)


func test_turn_start_resupplies_next_to_apc() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 p 0 0\n1 t 1 0")
	state.units[1].fuel = 5
	state.units[1].ammo = 0
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(state.units[1].fuel, 70)
	assert_eq(state.units[1].ammo, 9)


func test_turn_start_resupplies_carried_passenger() -> void:
	# A mech aboard a friendly T-Copter is refilled by its transport at
	# begin_turn, wherever the transport sits; a unit merely beside it is not.
	var state := _state("[terrain]\n...\n[units]\n1 H 0 0\n1 t 1 0\n1 m 2 0")
	var mech := state.units[2]
	mech.carrier = state.units[0]  # aboard the T-Copter
	mech.fuel = 5
	mech.ammo = 0
	var beside := state.units[1]  # adjacent to the transport, on the board
	beside.fuel = 5
	beside.ammo = 1
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)  # back to red; its begin_turn refills passengers
	assert_eq(mech.fuel, 70, "the transport refuels its passenger")
	assert_eq(mech.ammo, 3, "the transport re-ammoes its passenger")
	assert_eq(beside.fuel, 5, "a unit merely beside the transport is untouched")
	assert_eq(beside.ammo, 1, "a unit merely beside the transport is untouched")


func test_no_resupply_in_the_field() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0")
	state.units[0].fuel = 5
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(state.units[0].fuel, 5)


func test_supply_command_refills_adjacent() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 p 0 0\n1 t 1 0")
	state.units[1].fuel = 3
	var command := SupplyCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.units[1].fuel, 70)
	assert_true(state.units[0].acted)


func test_supply_command_needs_someone_in_reach() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 p 0 0")
	var command := SupplyCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "no one in reach to supply")
