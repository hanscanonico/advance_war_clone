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


func test_load_boards_the_transport() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var apc := state.units[1]
	var command := LoadCommand.new(infantry, _path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(infantry.carrier, apc)
	assert_eq(infantry.cell, apc.cell)
	assert_true(infantry.acted)
	assert_eq(state.unit_at(Vector2i(1, 0)), apc, "cell lookups see the transport")
	assert_eq(state.cargo_of(apc), [infantry] as Array[Unit])


func test_load_rejects_vehicles_and_full_or_enemy_transports() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n1 p 1 0\n1 i 2 0\n2 p 3 0")
	var tank := state.units[0]
	var apc := state.units[1]
	var infantry := state.units[2]
	assert_eq(
		LoadCommand.new(tank, _path([Vector2i(0, 0), Vector2i(1, 0)])).validate(state),
		"unit cannot be transported"
	)
	infantry.carrier = apc
	infantry.cell = apc.cell
	var second := Unit.create(unit_db.by_id(&"infantry"), 1, Vector2i(2, 0))
	state.units.append(second)
	assert_eq(
		LoadCommand.new(second, _path([Vector2i(2, 0), Vector2i(1, 0)])).validate(state),
		"transport is full"
	)
	assert_eq(
		LoadCommand.new(second, _path([Vector2i(2, 0), Vector2i(3, 0)])).validate(state),
		"path is blocked by an enemy",
		"enemy transports cannot even be entered"
	)


func test_cargo_rides_with_the_transport() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var apc := state.units[1]
	LoadCommand.new(infantry, _path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	apc.acted = false
	MoveCommand.new(apc, _path([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])).apply(state)
	assert_eq(infantry.cell, Vector2i(3, 0))
	assert_eq(infantry.carrier, apc)


func test_drop_unloads_exhausted_passenger() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var apc := state.units[1]
	LoadCommand.new(infantry, _path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	apc.acted = false
	var command := DropCommand.new(apc, _path([Vector2i(1, 0), Vector2i(2, 0)]), Vector2i(3, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_null(infantry.carrier)
	assert_eq(infantry.cell, Vector2i(3, 0))
	assert_true(infantry.acted)
	assert_eq(state.unit_at(Vector2i(3, 0)), infantry)


func test_drop_rejections() -> void:
	var state := _state("[terrain]\n..S.\n[units]\n1 p 1 0\n1 i 0 0")
	var apc := state.units[0]
	var infantry := state.units[1]
	assert_eq(
		DropCommand.new(apc, _path([Vector2i(1, 0)]), Vector2i(0, 0)).validate(state),
		"nothing to drop"
	)
	infantry.carrier = apc
	infantry.cell = apc.cell
	assert_eq(
		DropCommand.new(apc, _path([Vector2i(1, 0)]), Vector2i(2, 0)).validate(state),
		"cargo cannot stand there",
		"sea is no place for infantry"
	)
	assert_eq(
		DropCommand.new(apc, _path([Vector2i(1, 0)]), Vector2i(3, 0)).validate(state),
		"drop cell must be adjacent"
	)


func test_transport_death_takes_cargo_and_counts_for_rout() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 4
	var apc := state.units[1]
	var passenger := Unit.create(unit_db.by_id(&"infantry"), 2, apc.cell)
	passenger.carrier = apc
	state.units.append(passenger)
	apc.hp = 10  # any hit kills
	var result := CombatResolver.resolve(state, state.units[0], apc)
	assert_true(result.defender_died)
	assert_false(state.units.has(passenger), "cargo dies with its transport")
	assert_eq(state.winner, 1, "the drowned passenger was Blue's last unit")


func test_join_merges_and_removes_the_mover() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n1 t 2 0")
	var mover := state.units[0]
	var target := state.units[1]
	mover.hp = 40
	mover.ammo = 5
	target.hp = 50
	target.ammo = 6
	var command := JoinCommand.new(mover, _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(state.units.has(mover))
	assert_eq(target.hp, 90)
	assert_eq(target.ammo, 9, "ammo caps at the type maximum")
	assert_true(target.acted)
	assert_eq(state.winner, 0, "a merge is not a death")


func test_join_rejections() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n1 t 1 0\n1 r 2 0\n2 t 3 0")
	var mover := state.units[0]
	assert_eq(
		JoinCommand.new(mover, _path([Vector2i(0, 0), Vector2i(1, 0)])).validate(state),
		"target is at full strength"
	)
	state.units[2].hp = 50
	assert_ne(
		JoinCommand.new(mover, _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])).validate(
			state
		),
		"",
		"different unit types cannot join"
	)


func test_ai_ignores_carried_units() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 p 0 0\n1 i 1 0\n2 t 2 0")
	var infantry := state.units[1]
	infantry.carrier = state.units[0]
	infantry.cell = state.units[0].cell
	state.units[0].acted = true
	var ai := AIController.new(unit_db)
	var command := ai.plan_next_command(state)
	assert_true(command is EndTurnCommand, "a carried unit must not be planned for")
