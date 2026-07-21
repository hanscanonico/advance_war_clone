extends GutTest
## What the AI buys, and where. Split from test_ai_controller.gd, which covers
## how it moves and what it shoots.
##
## Production is the part of the planner that grew when the roster stopped being
## one facility's worth of land units: it now walks every property that builds
## anything, ranks candidates across all of them, and will bank a turn rather than
## spend down on something worse. Each of those is a way the AI can look broken —
## a base that eats the treasury before the port is asked, a 28 000 hull nothing
## can ever afford, a lander bought and never used — so each has a test.

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


func test_builds_hulls_at_a_port() -> void:
	var state := _state(
		"[terrain]\nP....\nSSSSS\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0"
	)
	for unit in state.units:
		unit.acted = true
	state.funds[1] = 99999
	var command := ai.plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq((command as BuildCommand).unit_type.domain, UnitType.SEA)
	assert_eq(command.validate(state), "")


## The AI must never buy a transport: it cannot plan load-move-unload across
## turns, and a lander it will not use is 12 000 spent on nothing.
func test_never_buys_a_transport_it_cannot_use() -> void:
	var state := _state(
		"[terrain]\nP....\nSSSSS\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0"
	)
	for unit in state.units:
		unit.acted = true
	for funds in [12000, 18000, 20000, 99999]:
		state.funds[1] = funds
		var command := ai.plan_next_command(state)
		if command is BuildCommand:
			assert_eq(
				(command as BuildCommand).unit_type.transport_capacity,
				0,
				"with %d in the bank the AI bought a transport it cannot plan for" % funds
			)


## A hull low on fuel makes for a port, not the airfield or the city next to it —
## the same domain gate TurnRules applies when it decides who gets refitted.
func test_a_low_hull_heads_for_a_port() -> void:
	var state := _state("[terrain]\nPSSSA\nSSSSS\n[owners]\n1 0 0\n1 4 0\n[units]\n1 c 3 0")
	state.units[0].fuel = 2
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a move, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_lt(path[path.size() - 1].x, 3, "it should be running for the port, not the airfield")


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
