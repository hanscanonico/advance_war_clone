extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	return state


func test_day_one_income_for_first_player() -> void:
	# red owns HQ + city = 2 properties -> 2000 on creation
	var state := _state("[terrain]\nQC.C\n[owners]\n1 0 0\n1 1 0\n2 3 0\n[units]\n1 i 2 0")
	assert_eq(state.current_team, 1)
	assert_eq(state.day, 1)
	assert_eq(state.funds[1], 2000)
	assert_eq(state.funds[2], 0, "the second player is paid when their turn starts")


func test_end_turn_rotates_and_pays_next_team() -> void:
	var state := _state("[terrain]\nQ.C\n[owners]\n1 0 0\n2 2 0\n[units]\n1 i 1 0")
	var command := EndTurnCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.current_team, 2)
	assert_eq(state.day, 1, "day advances only when the rotation wraps")
	assert_eq(state.funds[2], 1000)
	command.apply(state)
	assert_eq(state.current_team, 1)
	assert_eq(state.day, 2)
	assert_eq(state.funds[1], 2000, "1000 on day 1 plus 1000 on day 2")


func test_end_turn_readies_only_new_team() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 i 0 0\n2 i 2 0")
	state.units[0].acted = true
	state.units[1].acted = true
	EndTurnCommand.new().apply(state)
	assert_true(state.units[0].acted, "red stays exhausted during blue's turn")
	assert_false(state.units[1].acted)


func test_turn_ownership_blocks_off_turn_commands() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 i 0 0\n2 i 2 0")
	var blue := state.units[1]
	var command := MoveCommand.new(blue, [Vector2i(2, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(command.validate(state), "not this team's turn")
	EndTurnCommand.new().apply(state)
	assert_eq(command.validate(state), "")


func test_repair_on_friendly_property_costs_funds() -> void:
	# tank (7000) at 80 internal HP on an owned city: heal 20 for 1400
	var state := _state("[terrain]\nQC\n[owners]\n1 0 0\n1 1 0\n[units]\n1 t 1 0")
	state.units[0].hp = 80
	state.funds[1] = 0
	EndTurnCommand.new().apply(state)  # to blue
	EndTurnCommand.new().apply(state)  # back to red: income 2000, then repair
	assert_eq(state.units[0].hp, 100)
	assert_eq(state.funds[1], 2000 - 1400)


func test_repair_skipped_when_broke() -> void:
	var state := _state("[terrain]\n.B\n[owners]\n1 1 0\n[units]\n1 T 1 0")
	state.units[0].hp = 10
	state.funds[1] = 0
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)  # red income: 1000 < md tank heal cost 3200
	assert_eq(state.units[0].hp, 10)


func test_no_repair_on_neutral_or_enemy_property() -> void:
	var state := _state("[terrain]\nCQ\n[owners]\n2 1 0\n[units]\n1 i 0 0")
	state.units[0].hp = 50
	state.funds[1] = 9999
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(state.units[0].hp, 50)


func test_end_turn_rejected_after_victory() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	state.winner = 1
	assert_ne(EndTurnCommand.new().validate(state), "")
