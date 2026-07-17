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


func test_move_and_fire_applies() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n2 i 2 0")
	state.rng.seed = 42
	var tank := state.units[0]
	var infantry := state.units[1]
	var command := AttackCommand.new(tank, _path([Vector2i(0, 0), Vector2i(1, 0)]), Vector2i(2, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(tank.cell, Vector2i(1, 0))
	assert_true(tank.acted)
	assert_not_null(command.result)
	assert_lt(infantry.hp, 100)


func test_fire_in_place_applies() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 42
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(state.units[0].acted)


func test_target_out_of_range_rejected() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 2 0")
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(2, 0))
	assert_ne(command.validate(state), "")


func test_friendly_target_rejected() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 i 1 0")
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_ne(command.validate(state), "")


func test_empty_target_cell_rejected() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0")
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_ne(command.validate(state), "")


func test_unarmed_unit_rejected() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 p 0 0\n2 i 1 0")
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "unit is unarmed")


func test_indirect_cannot_move_and_fire() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 t 3 0")
	var command := AttackCommand.new(
		state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0)]), Vector2i(3, 0)
	)
	assert_eq(command.validate(state), "indirect units cannot move and fire")


func test_indirect_fires_within_ring() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 t 2 0")
	state.rng.seed = 8
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(2, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(command.result.countered, "no counter against ranged fire")


func test_indirect_minimum_range_enforced() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 g 0 0\n2 t 1 0")
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "target out of range")


func test_acted_unit_rejected_via_move_rules() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.units[0].acted = true
	var command := AttackCommand.new(state.units[0], _path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_ne(command.validate(state), "")
