extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	assert_not_null(map, "test map should parse")
	var state := GameState.create(map, unit_db)
	assert_not_null(state, "test state should build")
	return state


func test_infantry_open_field_diamond() -> void:
	var open_field := ".......\n".repeat(7)
	var state := _state("[terrain]\n%s[units]\n1 i 3 3" % open_field)
	var result := MovementResolver.reachable(state, state.units[0])
	# move 3 on cost-1 terrain = manhattan diamond: 2*3*(3+1) + 1 cells
	assert_eq(result.costs.size(), 25)
	assert_true(result.has(Vector2i(0, 3)))
	assert_true(result.has(Vector2i(3, 0)))
	assert_false(result.has(Vector2i(0, 0)))


func test_origin_costs_zero_and_is_stoppable() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 i 1 0")
	var result := MovementResolver.reachable(state, state.units[0])
	assert_eq(result.costs[Vector2i(1, 0)], 0)
	assert_true(result.can_stop_at(Vector2i(1, 0)))


func test_woods_slow_tires() -> void:
	# recon (move 8, tires): plains cost 2, woods cost 3
	var state := _state("[terrain]\n....FF..\n[units]\n1 r 0 0")
	var result := MovementResolver.reachable(state, state.units[0])
	assert_eq(result.costs[Vector2i(3, 0)], 6)
	assert_false(result.has(Vector2i(4, 0)), "entering woods would cost 9 > 8")


func test_roads_speed_up_tires() -> void:
	var state := _state("[terrain]\n========\n[units]\n1 r 0 0")
	var result := MovementResolver.reachable(state, state.units[0])
	assert_eq(result.costs[Vector2i(7, 0)], 7)


func test_enemy_blocks_entry_and_passage() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 2 0")
	var result := MovementResolver.reachable(state, state.units[0])
	assert_true(result.has(Vector2i(1, 0)))
	assert_false(result.has(Vector2i(2, 0)), "enemy cell cannot be entered")
	assert_false(result.has(Vector2i(3, 0)), "cannot pass through an enemy")


func test_friendly_allows_passage_but_not_stopping() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0")
	var result := MovementResolver.reachable(state, state.units[0])
	assert_true(result.has(Vector2i(1, 0)))
	assert_false(result.can_stop_at(Vector2i(1, 0)), "cannot stop on a friendly unit")
	assert_true(result.can_stop_at(Vector2i(2, 0)))
	assert_true(result.has(Vector2i(3, 0)))


func test_mountain_blocks_treads_but_not_boots() -> void:
	var tank_state := _state("[terrain]\n.M.\n[units]\n1 t 0 0")
	var tank_range := MovementResolver.reachable(tank_state, tank_state.units[0])
	assert_false(tank_range.has(Vector2i(1, 0)))
	assert_false(tank_range.has(Vector2i(2, 0)))

	var mech_state := _state("[terrain]\n.M.\n[units]\n1 m 0 0")
	var mech_range := MovementResolver.reachable(mech_state, mech_state.units[0])
	assert_eq(mech_range.costs[Vector2i(1, 0)], 1, "boots cross mountains at cost 1")
	assert_eq(mech_range.costs[Vector2i(2, 0)], 2)


func test_path_to_is_contiguous_and_cheapest() -> void:
	var state := _state("[terrain]\n.....\n.....\n.....\n[units]\n1 i 0 0")
	var result := MovementResolver.reachable(state, state.units[0])
	var path := result.path_to(Vector2i(2, 1))
	assert_eq(path.size(), 4)
	assert_eq(path[0], Vector2i(0, 0))
	assert_eq(path[path.size() - 1], Vector2i(2, 1))
	for i in range(1, path.size()):
		assert_eq((path[i] - path[i - 1]).length_squared(), 1, "steps must be adjacent")


func test_path_to_unreachable_is_empty() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	var result := MovementResolver.reachable(state, state.units[0])
	assert_eq(result.path_to(Vector2i(9, 9)), [] as Array[Vector2i])


# --- the hypothetical allowance ----------------------------------------------


## Lets a caller ask "how far with one more point?" without touching state. The
## AI weighs a power that grants movement with it, since such a power has to be
## judged by the reach it would create rather than the reach without it.
func test_an_extra_allowance_widens_the_fill() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 i 0 0")
	var plain := MovementResolver.reachable(state, state.units[0])
	assert_false(plain.has(Vector2i(4, 0)), "three movement stops short")
	assert_true(MovementResolver.reachable(state, state.units[0], 1).has(Vector2i(4, 0)))


func test_the_allowance_defaults_to_nothing() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 i 0 0")
	var infantry := state.units[0]
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points)
	assert_eq(MovementResolver.move_budget(state, infantry, 2), infantry.type.move_points + 2)


## Fuel caps the total, so the allowance cannot move a unit that has nothing
## left to burn — the same rule the doctrine bonus already answers to.
func test_fuel_still_caps_the_allowance() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 i 0 0")
	state.units[0].fuel = 1
	assert_eq(MovementResolver.move_budget(state, state.units[0], 5), 1)


## Air units cross everything at a flat cost, which is the whole air movement
## model — one row of terrain data rather than a rule in this file. Asserted
## against the terrain a ground unit is stopped by, since that is the difference
## that matters and the one a missing `air` cost would silently remove.
func test_aircraft_cross_ground_that_stops_an_army() -> void:
	var state := _state("[terrain]\n.MMS\n.MMS\n[units]\n1 h 0 0\n1 t 0 1")
	var copter := state.units[0]
	var reachable := MovementResolver.reachable(state, copter)
	assert_true(reachable.can_stop_at(Vector2i(1, 0)), "a helicopter clears a mountain")
	assert_true(reachable.can_stop_at(Vector2i(3, 0)), "and settles over open sea past it")
	var tank := state.units[1]
	assert_false(
		MovementResolver.reachable(state, tank).has(Vector2i(1, 1)),
		"while the tank beside it is stopped by the same ridge"
	)


## And every step costs an aircraft exactly one point, whatever it is over — so a
## plane's range is its move points and nothing about the ground changes it.
func test_terrain_never_slows_an_aircraft() -> void:
	var over_open := _state("[terrain]\n.....\n[units]\n1 h 0 0")
	var over_rough := _state("[terrain]\n.MFMS\n[units]\n1 h 0 0")
	assert_eq(
		MovementResolver.reachable(over_open, over_open.units[0]).cells().size(),
		MovementResolver.reachable(over_rough, over_rough.units[0]).cells().size(),
		"the same helicopter should reach the same number of cells over either strip"
	)
