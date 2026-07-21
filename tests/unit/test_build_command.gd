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


func test_unknown_unit_type_rejected() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	var command := BuildCommand.new(1, unit_db.by_id(&"no_such_unit"), Vector2i(0, 0))
	assert_eq(command.validate(state), "unknown unit type")


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


## A base builds what the roster says a base builds. Every land unit names one,
## so this is inert for today's nine — but it is the rule that keeps a ship off a
## land base the day the roster grows one, and it is the same answer the AI's
## candidate filter reads.
func test_a_unit_the_terrain_cannot_produce_is_rejected() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	state.funds[1] = 9999
	var boat := UnitType.new()
	boat.id = &"gunboat"
	boat.display_name = "Gunboat"
	boat.cost = 1000
	boat.built_at = &"port"
	var command := BuildCommand.new(1, boat, Vector2i(0, 0))
	assert_eq(command.validate(state), "can only build at a port")


## The rejection is about the terrain, not about the unit being unusual: the same
## unit at its own site passes every guard it should.
func test_a_unit_at_its_own_build_site_is_accepted() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	state.funds[1] = 9999
	var digger := UnitType.new()
	digger.id = &"digger"
	digger.display_name = "Digger"
	digger.cost = 1000
	digger.built_at = &"base"
	var command := BuildCommand.new(1, digger, Vector2i(0, 0))
	assert_eq(command.validate(state), "")


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
