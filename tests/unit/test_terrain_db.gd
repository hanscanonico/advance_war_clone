extends GutTest

var db: TerrainDB


func before_each() -> void:
	db = TerrainDB.load_default()


func test_loads_all_terrains() -> void:
	assert_eq(db.size(), 9)


func test_lookup_by_symbol() -> void:
	assert_eq(db.by_symbol(".").id, &"plains")
	assert_eq(db.by_symbol("Q").display_name, "HQ")
	assert_null(db.by_symbol("?"))


func test_lookup_by_id() -> void:
	assert_eq(db.by_id(&"woods").defense_stars, 2)
	assert_null(db.by_id(&"nonexistent"))


func test_sea_impassable_for_all_ground_classes() -> void:
	var sea := db.by_id(&"sea")
	for move_class: StringName in [
		TerrainType.FOOT, TerrainType.BOOT, TerrainType.TIRES, TerrainType.TREADS,
	]:
		assert_false(sea.is_passable(move_class), "sea should block %s" % move_class)
		assert_eq(sea.move_cost(move_class), TerrainType.IMPASSABLE)


func test_mountain_costs() -> void:
	var mountain := db.by_id(&"mountain")
	assert_eq(mountain.move_cost(TerrainType.FOOT), 2)
	assert_eq(mountain.move_cost(TerrainType.BOOT), 1)
	assert_false(mountain.is_passable(TerrainType.TIRES))
	assert_false(mountain.is_passable(TerrainType.TREADS))


func test_woods_slow_vehicles() -> void:
	var woods := db.by_id(&"woods")
	assert_eq(woods.move_cost(TerrainType.TIRES), 3)
	assert_eq(woods.move_cost(TerrainType.TREADS), 2)
	assert_eq(woods.move_cost(TerrainType.FOOT), 1)


func test_properties_flagged() -> void:
	for id: StringName in [&"city", &"base", &"hq"]:
		assert_true(db.by_id(id).is_property, "%s should be a property" % id)
		assert_true(db.by_id(id).team_tinted)
	assert_false(db.by_id(&"plains").is_property)


func test_defense_stars() -> void:
	assert_eq(db.by_id(&"road").defense_stars, 0)
	assert_eq(db.by_id(&"plains").defense_stars, 1)
	assert_eq(db.by_id(&"city").defense_stars, 3)
	assert_eq(db.by_id(&"hq").defense_stars, 4)
	assert_eq(db.by_id(&"mountain").defense_stars, 4)
