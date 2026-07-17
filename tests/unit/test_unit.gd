extends GutTest


func _unit_with_hp(hp: int) -> Unit:
	var unit := Unit.new()
	unit.hp = hp
	return unit


func test_displayed_hp_rounds_up() -> void:
	assert_eq(_unit_with_hp(100).displayed_hp(), 10)
	assert_eq(_unit_with_hp(95).displayed_hp(), 10)
	assert_eq(_unit_with_hp(91).displayed_hp(), 10)
	assert_eq(_unit_with_hp(90).displayed_hp(), 9)
	assert_eq(_unit_with_hp(11).displayed_hp(), 2)
	assert_eq(_unit_with_hp(10).displayed_hp(), 1)
	assert_eq(_unit_with_hp(1).displayed_hp(), 1)
	assert_eq(_unit_with_hp(0).displayed_hp(), 0)
