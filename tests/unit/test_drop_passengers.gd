extends GutTest
## A drop names which passenger steps off. Judging every drop against the
## first-loaded rider wrongly refused the second one exactly when it was the
## only one that could stand beside the transport — a Lander's two riders need
## not share a move class.

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


func test_drop_judges_each_passenger_not_just_the_first() -> void:
	# A lander beached on a shoal carries a tank (treads, loaded first) and then an
	# infantry (foot). The mountain beside it takes the infantry but not the tank;
	# judging every drop against the first passenger wrongly refused the infantry.
	var state := _state("[terrain]\n._S\nSMS\n[units]\n1 l 1 0")
	var lander := state.units[0]
	var tank := Unit.create(unit_db.by_id(&"tank"), 1, lander.cell)
	tank.carrier = lander
	var infantry := Unit.create(unit_db.by_id(&"infantry"), 1, lander.cell)
	infantry.carrier = lander
	state.units.append(tank)
	state.units.append(infantry)
	assert_eq(state.cargo_of(lander), [tank, infantry] as Array[Unit], "tank is loaded first")
	var path := _path([Vector2i(1, 0)])
	# The named second passenger drops onto the mountain the tank cannot climb.
	var drop_infantry := DropCommand.new(lander, path, Vector2i(1, 1), infantry)
	assert_eq(drop_infantry.validate(state), "")
	# The tank still cannot stand on that mountain, whichever passenger is first.
	assert_eq(
		DropCommand.new(lander, path, Vector2i(1, 1), tank).validate(state),
		"cargo cannot stand there"
	)
	# The first passenger's own path still works: the tank drops onto the plains.
	assert_eq(DropCommand.new(lander, path, Vector2i(0, 0), tank).validate(state), "")
	# A unit this transport is not carrying cannot be selected for a drop.
	var stranger := Unit.create(unit_db.by_id(&"infantry"), 1, Vector2i(0, 0))
	state.units.append(stranger)
	assert_eq(
		DropCommand.new(lander, path, Vector2i(1, 1), stranger).validate(state),
		"unit is not aboard"
	)
	# Applying the infantry drop lands it, exhausted, on the mountain; tank stays.
	drop_infantry.apply(state)
	assert_null(infantry.carrier)
	assert_eq(infantry.cell, Vector2i(1, 1))
	assert_true(infantry.acted)
	assert_eq(state.unit_at(Vector2i(1, 1)), infantry)
	assert_eq(state.cargo_of(lander), [tank] as Array[Unit], "the tank stays aboard")
