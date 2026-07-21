extends GutTest

var db: TerrainDB


func before_each() -> void:
	db = TerrainDB.load_default()


## The database is a directory scan, so the number worth pinning is "all of
## them", not a literal. Registration drops a terrain silently on a duplicate id
## or symbol, and that is the failure this catches; spelling the count out here
## would only be a chore every time the roster grows.
func test_loads_every_terrain_resource() -> void:
	assert_eq(db.size(), _resource_count(TerrainDB.TERRAIN_DIR))
	assert_gt(db.size(), 0, "data/terrain should not be empty")


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
		TerrainType.FOOT,
		TerrainType.BOOT,
		TerrainType.TIRES,
		TerrainType.TREADS,
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


## Every terrain admits aircraft at cost 1: that one row of data, and nothing in
## the movement resolver, is the whole air movement model. A terrain added
## without it would quietly become a hole in the sky.
func test_every_terrain_is_flyable_at_cost_one() -> void:
	for terrain in db.all():
		assert_eq(
			terrain.move_cost(TerrainType.AIR),
			1,
			"%s should cost an aircraft exactly one point to cross" % terrain.id
		)


## Which property builds what, and which refits what, is terrain data — the
## facilities the base game shipped with have to keep saying what they always
## meant, or every land unit quietly loses production and repair.
func test_land_properties_build_and_service_the_ground_army() -> void:
	var base := db.by_id(&"base")
	for move_class: StringName in [
		TerrainType.FOOT, TerrainType.BOOT, TerrainType.TIRES, TerrainType.TREADS
	]:
		assert_true(base.can_build(move_class), "a base should build %s units" % move_class)
	assert_false(base.can_build(TerrainType.AIR), "a base should not build aircraft")
	for id: StringName in [&"city", &"base", &"hq"]:
		assert_true(db.by_id(id).services_domain(UnitType.LAND), "%s should refit vehicles" % id)
		assert_false(db.by_id(id).services_domain(UnitType.AIR), "%s should not refit air" % id)
	for id: StringName in [&"city", &"hq"]:
		assert_true(db.by_id(id).builds.is_empty(), "%s should not be a factory" % id)


func test_airport_builds_and_services_only_aircraft() -> void:
	var airport := db.by_id(&"airport")
	assert_true(airport.is_property, "an airport should be capturable and pay income")
	assert_true(airport.can_build(TerrainType.AIR))
	assert_false(airport.can_build(TerrainType.TREADS), "an airport should not build tanks")
	assert_true(airport.services_domain(UnitType.AIR))
	assert_false(airport.services_domain(UnitType.LAND), "tanks refit at a city, not a hangar")
	assert_true(
		airport.is_passable(TerrainType.FOOT), "ground units should be able to walk onto the field"
	)


## Reads data/terrain the way TerrainDB does, so the count is derived rather than
## restated.
func _resource_count(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return -1
	var count := 0
	for file in dir.get_files():
		if file.trim_suffix(".remap").ends_with(".tres"):
			count += 1
	return count
