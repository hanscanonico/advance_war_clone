extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var ai: AIController


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	ai = AIController.new(unit_db)


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func test_attacks_enemy_in_range() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 g 2 0")
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand, "expected an attack, got %s" % command)
	assert_eq((command as AttackCommand).target_cell, Vector2i(2, 0))
	assert_eq(command.validate(state), "")


func test_prefers_valuable_target() -> void:
	# both the infantry and the artillery are attackable; artillery is worth more
	var state := _state("[terrain]\n....\n[units]\n1 t 1 0\n2 i 0 0\n2 g 2 0")
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand)
	assert_eq((command as AttackCommand).target_cell, Vector2i(2, 0))


func test_captures_nearby_property() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand, "expected a capture, got %s" % command)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path[path.size() - 1], Vector2i(1, 0))
	assert_eq(command.validate(state), "")


func test_prefers_hq_over_city() -> void:
	var state := _state("[terrain]\nQC.\n[owners]\n2 0 0\n[units]\n1 i 2 0")
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path[path.size() - 1], Vector2i(0, 0), "the enemy HQ outranks a city")


func test_continues_capture_in_progress() -> void:
	var state := _state("[terrain]\nCC\n[units]\n1 i 0 0")
	state.capture_progress[Vector2i(0, 0)] = 10
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path, [Vector2i(0, 0)] as Array[Vector2i], "finish the capture underway")


func test_advances_when_out_of_reach() -> void:
	var state := _state("[terrain]\n............\n[units]\n1 t 0 0\n2 g 11 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(6, 0), "move the full 6 toward the enemy")


func test_waits_when_isolated() -> void:
	var state := _state("[terrain]\nS.S.\nSSSS\n[units]\n1 t 1 0\n2 t 3 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand)
	assert_eq((command as MoveCommand).path, [Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(command.validate(state), "", "waiting in place is still a legal action")


func test_indirect_unit_backs_off_into_firing_range() -> void:
	# Artillery (range 2-3) pinned next to a tank can neither fire nor counter,
	# so it must reposition instead of waiting there forever.
	var state := _state("[terrain]\n......\n[units]\n1 g 1 0\n2 t 0 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a reposition, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(3, 0), "stand off at max range")
	assert_eq(command.validate(state), "")


func test_indirect_unit_closes_in_when_out_of_range() -> void:
	var state := _state("[terrain]\n..........\n[units]\n1 g 0 0\n2 t 9 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(5, 0), "spend the full 5 closing in")


func test_ends_turn_when_nothing_left() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	state.units[0].acted = true
	var command := ai.plan_next_command(state)
	assert_true(command is EndTurnCommand)


func test_full_turn_on_real_map_terminates_legally() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 7
	EndTurnCommand.new().apply(state)  # hand the turn to Blue, the AI side
	assert_eq(state.current_team, 2)
	var commands := 0
	var ended := false
	for i in 200:
		var command := ai.plan_next_command(state)
		assert_eq(
			command.validate(state),
			"",
			"AI produced an illegal command on iteration %d: %s" % [i, command]
		)
		command.apply(state)
		commands += 1
		if command is EndTurnCommand:
			ended = true
			break
	assert_true(ended, "AI must reach EndTurnCommand well under the cap")
	assert_lt(commands, 30, "one AI turn should be a handful of commands")
	assert_eq(state.current_team, 1)
