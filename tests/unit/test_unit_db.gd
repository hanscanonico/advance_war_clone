extends GutTest
## The roster read off disk. Only `all()`'s ordering is pinned here: it is the
## build menu's order, and several units share a price, so a comparator that
## ranked on cost alone would leave those pairs to whatever order the directory
## happened to list — which is not the same between a source run and an export.

var unit_db: UnitDB


func before_each() -> void:
	unit_db = UnitDB.load_default()


func _ids(types: Array[UnitType]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for type in types:
		ids.append(type.id)
	return ids


func test_all_lists_the_whole_roster_cheapest_first() -> void:
	var types := unit_db.all()
	assert_eq(types.size(), unit_db.size(), "every unit on disk is offered")
	for i in range(1, types.size()):
		assert_true(
			types[i - 1].cost <= types[i].cost,
			(
				"%s (%d) should not follow %s (%d)"
				% [types[i].id, types[i].cost, types[i - 1].id, types[i - 1].cost]
			)
		)


## The tie-break, stated as the property that matters: units sharing a price come
## out in a fixed order rather than an arbitrary one.
func test_units_sharing_a_price_are_ordered_by_id() -> void:
	var types := unit_db.all()
	for i in range(1, types.size()):
		if types[i - 1].cost != types[i].cost:
			continue
		assert_true(
			String(types[i - 1].id) < String(types[i].id),
			"%s and %s cost the same and must sort by id" % [types[i - 1].id, types[i].id]
		)


func test_the_order_is_the_same_every_load() -> void:
	assert_eq(_ids(unit_db.all()), _ids(UnitDB.load_default().all()))
