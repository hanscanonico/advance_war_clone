extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	return state


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


func test_capture_chips_points_by_displayed_hp() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.capture_progress[Vector2i(1, 0)], 10)
	assert_eq(state.owner_at(Vector2i(1, 0)), MapData.NEUTRAL)
	assert_true(state.units[0].acted)


func test_capture_completes_and_flips_owner() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0")
	state.capture_progress[Vector2i(0, 0)] = 10
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.owner_at(Vector2i(0, 0)), 1)
	assert_false(state.capture_progress.has(Vector2i(0, 0)))


func test_damaged_unit_captures_slower() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0")
	state.units[0].hp = 45  # 5 displayed
	CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)])).apply(state)
	assert_eq(state.capture_progress[Vector2i(0, 0)], 15)


func test_hq_capture_wins_the_match() -> void:
	var state := _state("[terrain]\nQ.\n[owners]\n2 0 0\n[units]\n1 i 0 0\n2 i 1 0")
	state.capture_progress[Vector2i(0, 0)] = 5
	CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)])).apply(state)
	assert_eq(state.owner_at(Vector2i(0, 0)), 1)
	assert_eq(state.winner, 1)


func test_leaving_property_resets_progress() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0")
	CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)])).apply(state)
	assert_eq(state.capture_progress[Vector2i(0, 0)], 10)
	state.units[0].acted = false
	MoveCommand.new(state.units[0], _path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	assert_false(state.capture_progress.has(Vector2i(0, 0)))


func test_capturer_death_resets_progress() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0\n2 i 1 0")
	CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)])).apply(state)
	state.remove_unit(state.units[0])
	assert_false(state.capture_progress.has(Vector2i(0, 0)))


func test_non_capture_unit_rejected() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 t 0 0")
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "unit cannot capture")


func test_own_property_rejected() -> void:
	var state := _state("[terrain]\nC.\n[owners]\n1 0 0\n[units]\n1 i 0 0")
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "property already owned")


func test_non_property_rejected() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "destination is not a property")


func test_result_snapshot_on_partial_capture() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0")
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	command.apply(state)
	# A fresh 20-point property, 10 removed by a full-HP infantry: still theirs.
	assert_eq(command.result.points_before, 20)
	assert_eq(command.result.points_after, 10)
	assert_eq(command.result.owner_before, MapData.NEUTRAL)
	assert_false(command.result.captured)


func test_result_snapshot_on_completing_capture() -> void:
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0")
	state.capture_progress[Vector2i(0, 0)] = 10
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	command.apply(state)
	assert_eq(command.result.points_before, 10)
	assert_eq(command.result.points_after, 0)
	assert_eq(command.result.owner_before, MapData.NEUTRAL)
	assert_true(command.result.captured)


func test_result_points_after_clamped_on_overshoot() -> void:
	# 5 points left, a full-HP infantry removes 10: the finishing turn removes
	# only the 5 that were there, so the meter drains by 5, not 10.
	var state := _state("[terrain]\nC.\n[units]\n1 i 0 0")
	state.capture_progress[Vector2i(0, 0)] = 5
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	command.apply(state)
	assert_eq(command.result.points_before, 5)
	assert_eq(command.result.points_after, 0)
	assert_true(command.result.captured)
	assert_eq(command.result.points_before - command.result.points_after, 5)


func test_result_owner_before_is_the_dislodged_enemy() -> void:
	# Blue owns the city; a red infantry finishes taking it. owner_before is Blue,
	# so the cut-in shows Blue's colours right up to the flip.
	var state := _state("[terrain]\nC.\n[owners]\n2 0 0\n[units]\n1 i 0 0")
	state.capture_progress[Vector2i(0, 0)] = 8
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	command.apply(state)
	assert_eq(command.result.owner_before, 2)
	assert_true(command.result.captured)
	assert_eq(state.owner_at(Vector2i(0, 0)), 1)


func test_result_captured_on_hq_win() -> void:
	var state := _state("[terrain]\nQ.\n[owners]\n2 0 0\n[units]\n1 i 0 0\n2 i 1 0")
	state.capture_progress[Vector2i(0, 0)] = 5
	var command := CaptureCommand.new(state.units[0], _path([Vector2i(0, 0)]))
	command.apply(state)
	assert_true(command.result.captured)
	assert_eq(command.result.owner_before, 2)
	assert_eq(state.winner, 1)
