extends GutTest
## AI vs AI on the air board, played long enough that aircraft actually arrive.
##
## The unit tests around it each check one rule in one place. This is the test
## that checks they agree: air movement lives in terrain data, production in
## TerrainType.builds *and* BuildCommand.validate *and* the planner, refit and the
## crash in TurnRules, targeting in the damage chart. Every one of those is read
## from more than one layer, and the failure mode when two of them drift is not a
## wrong number — it is the planner proposing a command the rules then refuse,
## which no single-layer test can see. That is precisely the bug an earlier soak
## caught after 277 unit tests missed it.
##
## test_map_soak.gd plays every board for ten days, which proves each is
## navigable but ends before anyone can afford a 20 000 airframe. This one plays
## the one board built for aircraft, for long enough that they fly.
##
## What it deliberately does *not* assert is anything about the route a plane
## takes. Whether the AI happens to fly one over a mountain in a given match is
## emergent, and a gate that depends on it fails for reasons that have nothing to
## do with what it guards. That air units cross ground others cannot is a rule,
## so it is pinned as one, deterministically, in test_movement_resolver.gd.

## Long enough for four properties of income to buy airframes and for those to
## reach the far side and start running low. Roughly twice the general soak.
const DAYS := 24
const MAP_PATH := "res://maps/jet_stream.txt"
## A deadlock detector rather than a budget; see test_map_soak.gd.
const COMMAND_CAP := 4000

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func test_the_ai_fights_an_air_war_without_the_rules_refusing_it() -> void:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	assert_not_null(map, "%s should parse" % MAP_PATH)
	if map == null:
		return
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 909
	var ai := AIController.new(unit_db)
	var commands := 0
	var aircraft_seen := 0
	while state.winner == 0 and state.day <= DAYS and commands < COMMAND_CAP:
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				(
					(
						"day %d: the planner proposed a command the rules reject: %s. "
						% [state.day, error]
					)
					+ "Two layers disagree about a rule on this board."
				)
			)
			return
		command.apply(state)
		commands += 1
		if (
			command is BuildCommand
			and (command as BuildCommand).built_unit.type.domain == UnitType.AIR
		):
			aircraft_seen += 1
	gut.p(
		(
			"jet_stream.txt   %d commands, day %d, %d aircraft built, winner %d"
			% [commands, state.day, aircraft_seen, state.winner]
		)
	)
	assert_lt(commands, COMMAND_CAP, "the match never progressed — the planner is probably looping")
	assert_gt(
		aircraft_seen,
		0,
		(
			"%d days of income on an airfield board and nothing was ever built at one. " % DAYS
			+ "Production, the build list or the AI's facility handling has come apart."
		)
	)
