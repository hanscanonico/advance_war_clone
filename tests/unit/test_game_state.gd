extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


## Like TerrainDB, this is a directory scan: the number worth asserting is "every
## resource on disk", since a duplicate id or symbol drops one silently. Adding a
## unit should not mean editing a literal here.
func test_unit_db_registers_every_unit_resource() -> void:
	var dir := DirAccess.open(UnitDB.UNIT_DIR)
	var on_disk := 0
	for file in dir.get_files():
		if file.trim_suffix(".remap").ends_with(".tres"):
			on_disk += 1
	assert_eq(unit_db.size(), on_disk)
	assert_gt(unit_db.size(), 0, "data/units should not be empty")
	assert_eq(unit_db.by_symbol("i").id, &"infantry")
	assert_eq(unit_db.by_id(&"tank").move_points, 6)


func test_create_spawns_starting_units() -> void:
	var map := MapData.parse("[terrain]\n....\n....\n[units]\n1 i 0 0\n2 t 3 1", terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	assert_eq(state.units.size(), 2)
	var infantry := state.unit_at(Vector2i(0, 0))
	assert_eq(infantry.type.id, &"infantry")
	assert_eq(infantry.team, 1)
	assert_eq(infantry.hp, 100)
	assert_false(infantry.acted)
	assert_eq(state.unit_at(Vector2i(3, 1)).type.id, &"tank")
	assert_null(state.unit_at(Vector2i(1, 1)))


func test_units_of_filters_by_team() -> void:
	var map := MapData.parse("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0\n2 i 3 0", terrain_db)
	var state := GameState.create(map, unit_db)
	assert_eq(state.units_of(1).size(), 2)
	assert_eq(state.units_of(2).size(), 1)


func test_remove_unit() -> void:
	var map := MapData.parse("[terrain]\n..\n[units]\n1 i 0 0", terrain_db)
	var state := GameState.create(map, unit_db)
	state.remove_unit(state.units[0])
	assert_eq(state.units.size(), 0)
	assert_null(state.unit_at(Vector2i(0, 0)))


func test_unknown_unit_symbol_fails() -> void:
	var map := MapData.parse("[terrain]\n..\n[units]\n1 z 0 0", terrain_db)
	assert_null(GameState.create(map, unit_db))
	assert_push_error("unknown unit symbol 'z'")


func test_two_units_on_one_cell_fails() -> void:
	var map := MapData.parse("[terrain]\n..\n[units]\n1 i 0 0\n2 i 0 0", terrain_db)
	assert_null(GameState.create(map, unit_db))
	assert_push_error("two starting units")


func test_unit_on_impassable_terrain_fails() -> void:
	var map := MapData.parse("[terrain]\nS.\n[units]\n1 t 0 0", terrain_db)
	assert_null(GameState.create(map, unit_db))
	assert_push_error("cannot stand on")


func test_first_steps_map_builds_a_state() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	assert_eq(state.units.size(), 14)
	assert_eq(state.units_of(1).size(), 7)
	assert_eq(state.units_of(2).size(), 7)


func test_crossfire_map_builds_a_state() -> void:
	var map := MapData.load_from_file("res://maps/crossfire.txt", terrain_db)
	assert_not_null(map)
	assert_eq(map.size(), Vector2i(20, 15))
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	assert_eq(state.units_of(1).size(), 4)
	assert_eq(state.units_of(2).size(), 4)
	assert_eq(map.owner_at(Vector2i(2, 1)), 1)
	assert_eq(map.terrain_at(Vector2i(17, 13)).id, &"hq")
