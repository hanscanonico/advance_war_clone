extends GutTest
## AI vs AI on every shipped map: the proof that a board is *playable*, not
## merely parseable.
##
## test_commander_match_soak.gd established the shape and why it pays — an
## AI-vs-AI match is the one test that runs the planner, the resolvers and
## command validation against each other, and it caught a movement bug that 277
## unit tests missed. That file varies the commander over a fixed fixture map;
## this one holds the commanders neutral and varies the map, so the board is the
## only thing under test.
##
## It is the dynamic half of a question test_maps.gd answers statically. The
## lint catches an HQ walled off behind sea by reading the grid. This catches
## the version no static check sees: a board the AI can cross on paper and then
## does nothing on.

## Long enough for both sides to bank income, build, and meet in the middle on
## the largest board, without making the suite pay for a full match per map.
const DAYS := 10
## Commands one turn can plausibly need, per map cell. A stall shows up as a
## planner that keeps proposing without the day ever ending, so the cap only has
## to be above "a real match" — it is a deadlock detector, not a budget.
const COMMANDS_PER_CELL := 4
const MIN_COMMAND_CAP := 400

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func test_the_ai_can_play_every_shipped_map() -> void:
	var paths := MapCatalog.paths()
	assert_gt(paths.size(), 0, "maps/ should ship at least one map")
	for i in paths.size():
		# Alternating seeds put half the roster under fog, so the vision hooks
		# are exercised on real boards rather than only on the fixture map.
		_soak(paths[i], 500 + i)


## Plays one map out with neutral commanders on both sides. Fails on the first
## command the rules turn down, on a run that never ends, and on a run that ends
## with the board untouched.
func _soak(path: String, rng_seed: int) -> void:
	var name := path.get_file()
	var map := MapData.load_from_file(path, terrain_db)
	assert_not_null(map, "%s should parse" % name)
	if map == null:
		return
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = rng_seed
	state.fog_enabled = rng_seed % 2 == 0
	var cap := maxi(MIN_COMMAND_CAP, map.width * map.height * COMMANDS_PER_CELL)
	var ai := AIController.new(unit_db)
	var started := Time.get_ticks_msec()
	var commands := 0
	while state.winner == 0 and state.day <= DAYS and commands < cap:
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				(
					(
						"%s (day %d, fog %s): the planner proposed a command the rules "
						% [name, state.day, state.fog_enabled]
					)
					+ "reject: %s. Two places disagree about a rule on this board." % error
				)
			)
			return
		command.apply(state)
		commands += 1
	var elapsed := Time.get_ticks_msec() - started
	gut.p("%-16s %4d commands, %5d ms, fog %s" % [name, commands, elapsed, state.fog_enabled])
	assert_lt(
		commands,
		cap,
		(
			"%s: %d days of AI vs AI hit the command cap, so the match never " % [name, DAYS]
			+ "progressed — most likely the planner is looping on this board"
		)
	)
	# A board where the AI can reach nothing passes "no stall" while doing
	# nothing at all, so the run has to have moved the game somewhere.
	assert_true(
		state.winner != 0 or _properties_changed(state, map),
		(
			"%s: %d days went by with no property changing hands and no winner. " % [name, DAYS]
			+ "The AI can move here but cannot get anywhere — check that cities "
			+ "sit within reach of each side's opening."
		)
	)


## True once runtime ownership has diverged from the map's starting ownership —
## somebody captured something.
func _properties_changed(state: GameState, map: MapData) -> bool:
	var initial := map.initial_owners()
	for cell: Vector2i in state.property_owners:
		if int(state.property_owners[cell]) != int(initial.get(cell, MapData.NEUTRAL)):
			return true
	return false
