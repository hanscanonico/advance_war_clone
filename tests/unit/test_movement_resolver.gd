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
	var state := _state("[terrain]\n.......\n.......\n.......\n.......\n.......\n.......\n.......\n[units]\n1 i 3 3")
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
