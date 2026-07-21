extends GutTest
## AI vs AI on the naval board, played long enough that fleets are built and meet.
##
## It is also the suite's mixed-domain soak, because The Straits has a base, an
## airport *and* a port on each side: an army, an air force and a fleet all
## planned by the same planner against each other, which is the only place the
## three domains' rules meet outside the balance runner.
##
## The sibling of test_air_war_soak.gd, and there for the same reason: naval rules
## live in more than one layer each — passability in terrain data and in
## MovementResolver's fill and in MoveCommand's re-validation of the path it
## produced; production in TerrainType.builds and BuildCommand and the planner;
## refit in TurnRules. When two of those drift the symptom is not a wrong number
## but a planner proposing a command the rules refuse, and no single-layer test
## sees it.
##
## It also guards the map's own premise. The Straits is built so that two fleets
## can actually reach each other — the strait is one body of water, and the land
## wraps around both ends rather than being joined by a bridge that would cut it
## in half. That is a property of the board, not of the code, so it is checked
## here: if an edit to the map severs the channel, the fleets stop meeting and
## this notices.

const DAYS := 24
const MAP_PATH := "res://maps/the_straits.txt"
const COMMAND_CAP := 4000

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func test_the_ai_fights_a_naval_war_without_the_rules_refusing_it() -> void:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	assert_not_null(map, "%s should parse" % MAP_PATH)
	if map == null:
		return
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 4242
	var ai := AIController.new(unit_db)
	var commands := 0
	var hulls_built := 0
	var naval_attacks := 0
	var dives := 0
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
		if command is AttackCommand and _is_naval_exchange(state, command as AttackCommand):
			naval_attacks += 1
		if command is DiveCommand:
			dives += 1
		command.apply(state)
		commands += 1
		if (
			command is BuildCommand
			and (command as BuildCommand).built_unit.type.domain == UnitType.SEA
		):
			hulls_built += 1
	gut.p(
		(
			"the_straits.txt  %d commands, day %d, %d hulls, %d naval exchanges, %d dives"
			% [commands, state.day, hulls_built, naval_attacks, dives]
		)
	)
	assert_lt(commands, COMMAND_CAP, "the match never progressed — the planner is probably looping")
	assert_gt(
		hulls_built,
		0,
		(
			"%d days on a board with a port each and no hull was ever laid down. " % DAYS
			+ "Production, the port's build list or the AI's facility handling has come apart."
		)
	)
	assert_gt(
		naval_attacks,
		0,
		(
			"the fleets never fired on each other in %d days. Either the strait has " % DAYS
			+ "been severed into two basins, or ships have stopped being able to reach "
			+ "one another — both are map or movement failures a passing soak would hide."
		)
	)


## True when a sea unit is on at least one side of the exchange — enough to show
## the fleets are meeting something, whether that is each other or the coast.
func _is_naval_exchange(state: GameState, attack: AttackCommand) -> bool:
	var target := state.unit_at(attack.target_cell)
	if target == null:
		return false
	return attack.unit.type.domain == UnitType.SEA or target.type.domain == UnitType.SEA
