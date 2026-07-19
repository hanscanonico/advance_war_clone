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


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


func test_valid_move_applies() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0")
	var unit := state.units[0]
	var command := MoveCommand.new(unit, _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(unit.cell, Vector2i(2, 0))
	assert_true(unit.acted)


func test_wait_in_place_is_a_single_cell_path() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0")
	var unit := state.units[0]
	var command := MoveCommand.new(unit, _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(unit.cell, Vector2i(0, 0))
	assert_true(unit.acted)


func test_acted_unit_is_rejected() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0")
	var unit := state.units[0]
	unit.acted = true
	var command := MoveCommand.new(unit, _path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_ne(command.validate(state), "")


func test_path_must_start_at_unit_cell() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0")
	var command := MoveCommand.new(state.units[0], _path([Vector2i(1, 0), Vector2i(2, 0)]))
	assert_ne(command.validate(state), "")


func test_non_contiguous_path_is_rejected() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0")
	var command := MoveCommand.new(state.units[0], _path([Vector2i(0, 0), Vector2i(2, 0)]))
	assert_ne(command.validate(state), "")


func test_path_exceeding_movement_is_rejected() -> void:
	# infantry has 3 movement; a 4-step path is too long
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0")
	var command := (
		MoveCommand
		. new(
			state.units[0],
			_path(
				[
					Vector2i(0, 0),
					Vector2i(1, 0),
					Vector2i(2, 0),
					Vector2i(3, 0),
					Vector2i(4, 0),
				]
			)
		)
	)
	assert_ne(command.validate(state), "")


func test_path_through_enemy_is_rejected() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0")
	var command := (
		MoveCommand
		. new(
			state.units[0],
			_path(
				[
					Vector2i(0, 0),
					Vector2i(1, 0),
					Vector2i(2, 0),
				]
			)
		)
	)
	assert_ne(command.validate(state), "")


func test_stopping_on_friendly_is_rejected() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0")
	var command := MoveCommand.new(state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_ne(command.validate(state), "")


func test_impassable_terrain_is_rejected() -> void:
	# tank cannot enter mountains
	var state := _state("[terrain]\n.M\n[units]\n1 t 0 0")
	var command := MoveCommand.new(state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_ne(command.validate(state), "")
