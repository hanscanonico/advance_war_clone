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


func test_build_spawns_exhausted_unit_and_charges() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	# owned base pays 1000 on day 1
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.funds[1], 0)
	assert_eq(state.units.size(), 1)
	var unit := state.unit_at(Vector2i(0, 0))
	assert_eq(unit.type.id, &"infantry")
	assert_true(unit.acted, "new units act next turn")
	assert_eq(command.built_unit, unit)


func test_insufficient_funds_rejected() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	var command := BuildCommand.new(1, unit_db.by_id(&"md_tank"), Vector2i(0, 0))
	assert_eq(command.validate(state), "insufficient funds")


func test_unowned_base_rejected() -> void:
	var state := _state("[terrain]\nB.\n")
	state.funds[1] = 9999
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(command.validate(state), "base is not owned")


func test_non_base_rejected() -> void:
	var state := _state("[terrain]\nC.\n[owners]\n1 0 0")
	state.funds[1] = 9999
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(command.validate(state), "can only build at a base")


func test_occupied_base_rejected() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0\n[units]\n1 i 0 0")
	state.funds[1] = 9999
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(command.validate(state), "base is occupied")


func test_off_turn_build_rejected() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n2 0 0")
	state.funds[2] = 9999
	var command := BuildCommand.new(2, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(command.validate(state), "not this team's turn")


func test_rout_by_combat_sets_winner() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 11
	var blue := state.units[1]
	blue.hp = 10  # last blue unit; any hit kills
	CombatResolver.resolve(state, state.units[0], blue)
	assert_eq(state.winner, 1)
