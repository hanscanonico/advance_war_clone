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


# --- production facilities ---------------------------------------------------
#
# Which property builds what is terrain data, and this command, the build menu
# and the AI all read the same list. These pin the command's half of that.


func test_airport_builds_aircraft() -> void:
	var state := _state("[terrain]\nA.\n[owners]\n1 0 0")
	state.funds[1] = 99999
	var command := BuildCommand.new(1, unit_db.by_id(&"fighter"), Vector2i(0, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.unit_at(Vector2i(0, 0)).type.id, &"fighter")


func test_a_base_cannot_build_aircraft() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	state.funds[1] = 99999
	var command := BuildCommand.new(1, unit_db.by_id(&"bomber"), Vector2i(0, 0))
	assert_eq(command.validate(state), "base does not build bomber")


func test_an_airport_cannot_build_ground_units() -> void:
	var state := _state("[terrain]\nA.\n[owners]\n1 0 0")
	state.funds[1] = 99999
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(command.validate(state), "airport does not build infantry")


## Missiles are a ground unit despite existing to shoot at aircraft, so a base
## builds them and an airport does not. Easy to get backwards in data.
func test_missiles_are_built_at_a_base() -> void:
	var state := _state("[terrain]\nBA\n[owners]\n1 0 0\n1 1 0")
	state.funds[1] = 99999
	assert_eq(BuildCommand.new(1, unit_db.by_id(&"missiles"), Vector2i(0, 0)).validate(state), "")
	assert_ne(BuildCommand.new(1, unit_db.by_id(&"missiles"), Vector2i(1, 0)).validate(state), "")
