extends GutTest

const SAMPLE := """
# tiny test map
[terrain]
SSSS
S.QS
SC=S
SSSS
[owners]
1 2 1
"""

var db: TerrainDB


func before_each() -> void:
	db = TerrainDB.load_default()


func test_dimensions() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_eq(map.width, 4)
	assert_eq(map.height, 4)
	assert_eq(map.size(), Vector2i(4, 4))


func test_terrain_at() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_eq(map.terrain_at(Vector2i(0, 0)).id, &"sea")
	assert_eq(map.terrain_at(Vector2i(1, 1)).id, &"plains")
	assert_eq(map.terrain_at(Vector2i(2, 1)).id, &"hq")
	assert_eq(map.terrain_at(Vector2i(1, 2)).id, &"city")
	assert_eq(map.terrain_at(Vector2i(2, 2)).id, &"road")


func test_owners() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_eq(map.owner_at(Vector2i(2, 1)), 1)
	assert_eq(map.owner_at(Vector2i(1, 2)), MapData.NEUTRAL)


func test_out_of_bounds() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_false(map.in_bounds(Vector2i(-1, 0)))
	assert_false(map.in_bounds(Vector2i(4, 0)))
	assert_false(map.in_bounds(Vector2i(0, 4)))
	assert_true(map.in_bounds(Vector2i(3, 3)))
	assert_null(map.terrain_at(Vector2i(-1, 0)))


func test_ragged_rows_rejected() -> void:
	assert_null(MapData.parse("[terrain]\nSS\nSSS", db))
	assert_push_error("row 1 is 3 wide, expected 2")


func test_unknown_symbol_rejected() -> void:
	assert_null(MapData.parse("[terrain]\nSX", db))
	assert_push_error("unknown terrain symbol 'X'")


func test_empty_map_rejected() -> void:
	assert_null(MapData.parse("# nothing here", db))
	assert_push_error("map has no terrain rows")


func test_owner_on_non_property_rejected() -> void:
	var text := "[terrain]\n.Q\n[owners]\n1 0 0"
	assert_null(MapData.parse(text, db))
	assert_push_error("is not a property")


func test_owner_out_of_bounds_rejected() -> void:
	var text := "[terrain]\n.Q\n[owners]\n1 5 0"
	assert_null(MapData.parse(text, db))
	assert_push_error("out of bounds")


# String→int coercion reads "x" as 0, so a coordinate typo like `1 x 0` would
# silently place the owner at column 0 — in bounds and a property on this board —
# instead of failing the way every other malformed line does. A non-numeric
# coordinate has to take the same loud error path; a negative one stays numeric
# and keeps failing on the bounds check as before.
func test_owner_non_numeric_coordinate_rejected() -> void:
	assert_not_null(MapData.parse("[terrain]\nCC\n[owners]\n1 0 0", db), "valid line still parses")
	assert_null(MapData.parse("[terrain]\nCC\n[owners]\n1 x 0", db))
	assert_push_error("owner cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\nCC\n[owners]\n1 1 y", db))
	assert_push_error("owner cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\nCC\n[owners]\n1 0 -1", db))
	assert_push_error("owner cell (0, -1) out of bounds")


func test_units_section_parsed() -> void:
	var text := "[terrain]\n....\n[units]\n1 i 0 0\n2 t 3 0"
	var map := MapData.parse(text, db)
	assert_not_null(map)
	assert_eq(map.starting_units.size(), 2)
	assert_eq(map.starting_units[0], {"team": 1, "symbol": "i", "cell": Vector2i(0, 0)})
	assert_eq(map.starting_units[1], {"team": 2, "symbol": "t", "cell": Vector2i(3, 0)})


func test_bad_unit_line_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0", db))
	assert_push_error("bad unit line")


func test_unit_out_of_bounds_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 5 0", db))
	assert_push_error("unit cell (5, 0) out of bounds")


# Same String→int coercion trap as owners: `1 i x 0` would coerce to column 0 and
# spawn a unit where none was written, while a negative coordinate stays numeric
# and keeps failing on the bounds check as before.
func test_unit_non_numeric_coordinate_rejected() -> void:
	assert_not_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 0", db), "valid line still parses")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i x 0", db))
	assert_push_error("unit cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 y", db))
	assert_push_error("unit cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 -1", db))
	assert_push_error("unit cell (0, -1) out of bounds")


func test_unit_bad_team_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n0 i 1 0", db))
	assert_push_error("unit team must be >= 1")


func test_loads_first_steps_map() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", db)
	assert_not_null(map)
	assert_eq(map.size(), Vector2i(20, 15))
	assert_eq(map.terrain_at(Vector2i(2, 2)).id, &"hq")
	assert_eq(map.owner_at(Vector2i(2, 2)), 1)
	assert_eq(map.terrain_at(Vector2i(17, 11)).id, &"hq")
	assert_eq(map.owner_at(Vector2i(17, 11)), 2)
	assert_eq(map.terrain_at(Vector2i(16, 8)).id, &"city")
	assert_eq(map.owner_at(Vector2i(16, 8)), MapData.NEUTRAL, "cities start neutral")
	# borders are sea
	assert_eq(map.terrain_at(Vector2i(0, 0)).id, &"sea")
	assert_eq(map.terrain_at(Vector2i(19, 14)).id, &"sea")
