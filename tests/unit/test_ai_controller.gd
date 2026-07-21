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


func test_builds_infantry_when_short_on_capture_units() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0\n[units]\n1 i 1 0")
	state.units[0].acted = true
	var command := ai.plan_next_command(state)  # funds: 1000 day-1 income
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq((command as BuildCommand).unit_type.id, &"infantry")
	assert_eq(command.validate(state), "")


func test_builds_tank_with_funds_and_enough_capture_units() -> void:
	var state := _state("[terrain]\nB....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0")
	for unit in state.units:
		unit.acted = true
	state.funds[1] = 7000
	var command := ai.plan_next_command(state)
	assert_true(command is BuildCommand)
	assert_eq((command as BuildCommand).unit_type.id, &"tank")


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


# --- production across facilities --------------------------------------------


func test_builds_aircraft_at_an_airport() -> void:
	var state := _state("[terrain]\nA....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0")
	for unit in state.units:
		unit.acted = true
	state.funds[1] = 99999
	var command := ai.plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq((command as BuildCommand).unit_type.domain, UnitType.AIR)
	assert_eq(command.validate(state), "")


## The planner walks every facility, not just the first. An airport it cannot
## afford must not stop the base beside it from producing — that stall would look
## exactly like an AI that has given up.
func test_an_unaffordable_airport_does_not_block_the_base_beside_it() -> void:
	var state := _state("[terrain]\nAB...\n[owners]\n1 0 0\n1 1 0\n[units]\n1 i 4 0")
	state.units[0].acted = true
	state.funds[1] = 1000  # an infantry's worth, and nothing that flies
	var command := ai.plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq((command as BuildCommand).cell, Vector2i(1, 0), "the base, not the airfield")
	assert_eq((command as BuildCommand).unit_type.id, &"infantry")


## Nothing in the standard build priority can shoot upward, so answering aircraft
## is asked about separately — an AI that skipped it would bank funds while
## bombers worked its army over.
func test_buys_an_air_answer_when_the_enemy_is_flying() -> void:
	var state := _state(
		"[terrain]\nB....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0\n2 b 4 0"
	)
	for unit in state.units_of(1):
		unit.acted = true
	state.funds[1] = 99999
	var command := ai.plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	var bought: UnitType = (command as BuildCommand).unit_type
	assert_true(
		chart.can_attack(bought.id, &"bomber"),
		"bought a %s, which cannot reach the bomber overhead" % bought.id
	)


## And stops once it has enough of them, rather than buying anti-air forever.
func test_stops_buying_air_answers_once_covered() -> void:
	var state := _state(
		(
			"[terrain]\nB......\n[owners]\n1 0 0\n"
			+ "[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0\n1 a 4 0\n1 a 5 0\n2 b 6 0"
		)
	)
	for unit in state.units_of(1):
		unit.acted = true
	state.funds[1] = 99999
	var command := ai.plan_next_command(state)
	assert_true(command is BuildCommand)
	assert_eq(
		(command as BuildCommand).unit_type.id,
		&"md_tank",
		"two anti-air guns already cover the sky; back to the priority list"
	)


# --- fuel awareness ----------------------------------------------------------


## A plane low on fuel breaks off for somewhere that refits it. A city will not,
## so heading there would be a retreat to nowhere.
func test_a_low_aircraft_heads_for_an_airfield_not_a_city() -> void:
	var state := _state("[terrain]\nA...C\n[owners]\n1 0 0\n1 4 0\n[units]\n1 h 3 0")
	var copter := state.units[0]
	copter.fuel = 2
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a move, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_lt(
		path[path.size() - 1].x,
		copter.cell.x,
		"it should be heading toward the airfield, not the city"
	)


## With a full tank the same helicopter has no reason to break off.
func test_a_fuelled_aircraft_ignores_the_airfield() -> void:
	var state := _state("[terrain]\nA....\n[owners]\n1 0 0\n[units]\n1 h 3 0\n2 i 4 0")
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand, "a full copter should go hunting, not home")
