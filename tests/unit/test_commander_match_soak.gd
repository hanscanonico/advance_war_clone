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

## A fixture rather than a shipped map, because the per-commander assertion
## below needs every gate to be *openable* from the starting position instead of
## by luck of the advance heuristic:
##
## - contested cities inside an infantry's first move, for Popular Uprising and
##   Ghost March, which wait on ground rather than on a fight;
## - woods under a starting unit on each side, because Vanish does nothing with
##   nobody in cover and so refuses to fire — on crossfire.txt no unit starts on
##   woods, which left Sable Wren passing only if the AI happened to route a
##   unit through an F tile;
## - both armies inside each other's reach on day one, which is what opens the
##   offensive gates, banks meters through trading, and wears units down far
##   enough for Open the Depots.
##
## 180-degree rotationally symmetric, (x, y) -> (11 - x, 8 - y), so neither side
## gets a terrain or income edge.
const MAP := """
[terrain]
............
.Q.C...F....
.B..F.......
.....F......
............
......F.....
.......F..B.
....F...C.Q.
............
[owners]
1 1 1
1 1 2
2 10 7
2 10 6
[units]
1 i 4 2
1 m 5 3
1 t 4 3
1 r 3 2
2 i 7 6
2 m 6 5
2 t 7 5
2 r 8 6
"""

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
	var fired: Dictionary = {}
	for id in ids:
		fired[id] = 0
	for i in ids.size():
		# Each general as red once, against the next in the list as blue — so
		# every one of them plays two pairings, one from each side.
		_play(ids[i], ids[(i + 1) % ids.size()], 1000 + i, fired)
	# Per commander, not summed. A sum passes while a general banks a full meter
	# all match and never spends it, which is exactly the bug that hid behind it:
	# every wave-2 power was gated on an offensive opening its owner may never
	# get. If a doctrine's timing hook goes wrong, this is what notices.
	for id in ids:
		assert_gt(
			int(fired[id]),
			0,
			(
				"%s banked a meter for %d days and never spent it. Either its " % [id, DAYS]
				+ "wants_power gate regressed — test_power_gating.gd checks each "
				+ "gate directly and will say which — or MAP above no longer "
				+ "sets up the situation that gate waits for."
			)
		)


## Plays one pairing out, tallying each fired power against the commander who
## fired it. Fails the test on the first command the rules turn down.
func _play(red: StringName, blue: StringName, rng_seed: int, fired: Dictionary) -> void:
	var map := MapData.parse(MAP, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = rng_seed
	# Half the pairings under fog, so the vision hooks are exercised too.
	state.fog_enabled = rng_seed % 2 == 0
	state.set_commander(1, commander_db.by_id(red))
	state.set_commander(2, commander_db.by_id(blue))
	var ai := AIController.new(unit_db)
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
			return
		if command is PowerCommand:
			var who: StringName = red if state.current_team == 1 else blue
			fired[who] = int(fired[who]) + 1
		command.apply(state)
		commands += 1
	assert_lt(commands, COMMAND_CAP, "%s vs %s should not need this many commands" % [red, blue])
