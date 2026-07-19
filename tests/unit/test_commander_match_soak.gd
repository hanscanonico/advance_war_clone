extends GutTest
## Plays every commander against another one, AI on both sides, and asserts that
## nothing the planner proposes is ever rejected by the rules.
##
## This exists because it caught a bug that 277 unit tests did not. Every hook
## added over C1-C4 has a call site in the resolvers *and* a second one in
## command validation, and testing a doctrine in isolation proves the first
## without touching the second. MoveCommand worked the movement budget out from
## unit.type.move_points itself, so every commander who granted movement made
## the flood fill offer cells the command then refused — the AI stalled on a
## rejected command, and a player under Coordinated Push would have seen a range
## they could not actually use.
##
## The general shape is the point: a planner proposing an illegal command means
## two places disagree about a rule. Nothing here checks *which* rule, so it
## keeps working as doctrines are added.

## Enough turns for both sides to bank a meter and fire powers repeatedly —
## the interesting window, since a power is when the rules change mid-turn.
const DAYS := 8
const COMMAND_CAP := 2000

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func test_no_pairing_ever_plans_a_command_the_rules_reject() -> void:
	var ids: Array[StringName] = []
	for co in commander_db.all():
		if co.id != CommanderType.NEUTRAL_ID:
			ids.append(co.id)
	assert_gt(ids.size(), 0, "there should be commanders to play")
	var powers_fired := 0
	for i in ids.size():
		# Each general as red once, against the next in the list as blue.
		powers_fired += _play(ids[i], ids[(i + 1) % ids.size()], 1000 + i)
	assert_gt(powers_fired, 0, "the AI should have fired powers over this many turns")


## Returns how many Command Powers went off. Fails the test on the first command
## the rules turn down.
func _play(red: StringName, blue: StringName, rng_seed: int) -> int:
	var map := MapData.load_from_file("res://maps/crossfire.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = rng_seed
	# Half the pairings under fog, so the vision hooks are exercised too.
	state.fog_enabled = rng_seed % 2 == 0
	state.set_commander(1, commander_db.by_id(red))
	state.set_commander(2, commander_db.by_id(blue))
	var ai := AIController.new(unit_db)
	var powers := 0
	var commands := 0
	while state.winner == 0 and state.day <= DAYS and commands < COMMAND_CAP:
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				(
					"%s vs %s (day %d): planner proposed a rejected command: %s"
					% [red, blue, state.day, error]
				)
			)
			return powers
		if command is PowerCommand:
			powers += 1
		command.apply(state)
		commands += 1
	assert_lt(commands, COMMAND_CAP, "%s vs %s should not need this many commands" % [red, blue])
	return powers
