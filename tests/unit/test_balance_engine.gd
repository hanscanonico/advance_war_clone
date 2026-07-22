extends GutTest
## The Balance Lab's match engine: determinism, the caps, and the day-cap
## tiebreak that turns an unfinished match into a scored one.
##
## Determinism is the property every number the Lab publishes rests on — a
## tuning change has to be attributable to the change and never to noise — so it
## is pinned here rather than assumed from "the RNG is seeded".

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart

## Two mirrored armies with a base each and room to fight: long enough to build,
## trade and capture, small enough to play a few dozen times in a test.
const BOARD := """
[terrain]
QB......
........
..F..F..
........
......BQ
[owners]
1 0 0
1 1 0
2 7 4
2 6 4
[units]
1 i 1 1
1 t 2 1
2 i 6 3
2 t 5 3
"""


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _setup(seed_val: int, days: int = 8) -> BalanceMatchEngine.Setup:
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = MapData.parse(BOARD, terrain_db)
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = seed_val
	setup.days_cap = days
	setup.tiers = {1: &"normal", 2: &"normal"}
	setup.planners = {1: AIController.new(unit_db), 2: AIController.new(unit_db)}
	return setup


## Timeline rows minus the one wall-clock column, which measures how long the
## planner thought and so cannot repeat. Everything else must.
func _comparable(rows: Array[Dictionary]) -> Array:
	var stripped: Array = []
	for row in rows:
		var copy := row.duplicate()
		for column in BalanceMatchRecorder.NONDETERMINISTIC_COLUMNS:
			copy.erase(column)
		stripped.append(copy)
	return stripped


# --- determinism ---------------------------------------------------------------


func test_the_same_spec_replays_identically() -> void:
	var first := BalanceMatchEngine.play(_setup(4242))
	var second := BalanceMatchEngine.play(_setup(4242))
	assert_eq(first.winner, second.winner, "same seed, same winner")
	assert_eq(first.day_ended, second.day_ended)
	assert_eq(first.commands, second.commands, "same seed, same command count")
	assert_eq(first.termination, second.termination)
	assert_eq(
		first.state.units_of(1).size() + first.state.units_of(2).size(),
		second.state.units_of(1).size() + second.state.units_of(2).size()
	)


func test_the_timeline_replays_byte_for_byte() -> void:
	var first := BalanceMatchRecorder.new()
	var second := BalanceMatchRecorder.new()
	BalanceMatchEngine.play(_setup(99), first)
	BalanceMatchEngine.play(_setup(99), second)
	assert_gt(first.rows().size(), 4, "the fixture should play several turns")
	assert_eq(
		_comparable(first.rows()),
		_comparable(second.rows()),
		"every timeline column but planning_ms is a pure function of the spec"
	)
	assert_eq(first.command_log(), second.command_log(), "and so is the command log")


func test_a_different_seed_is_a_different_match() -> void:
	# Not a guarantee about *which* differs — only that the seed reaches the sim
	# at all, which is what a stuck or ignored seed would break.
	var log_a := BalanceMatchRecorder.new()
	var log_b := BalanceMatchRecorder.new()
	BalanceMatchEngine.play(_setup(1), log_a)
	BalanceMatchEngine.play(_setup(2), log_b)
	assert_ne(log_a.command_log(), log_b.command_log(), "the seed must reach combat luck")


# --- the harness's own guarantees ----------------------------------------------


func test_the_planner_never_proposes_an_illegal_command() -> void:
	for seed_val in [7, 21, 404]:
		var outcome := BalanceMatchEngine.play(_setup(seed_val))
		assert_eq(outcome.rejected, 0, "seed %d: the AI and the rules must agree" % seed_val)
		assert_false(outcome.cap_stall, "seed %d: the match must resolve" % seed_val)
		assert_eq(outcome.turn_cap_hits, 0, "seed %d: no turn should overstay" % seed_val)


func test_the_telemetry_reconciles_against_the_board_it_describes() -> void:
	for seed_val in [11, 55, 900]:
		var recorder := BalanceMatchRecorder.new()
		var outcome := BalanceMatchEngine.play(_setup(seed_val), recorder)
		assert_eq(
			recorder.reconcile(outcome.state, outcome.starting_units),
			"",
			"seed %d: the timeline must add up to the final board" % seed_val
		)
		assert_eq(recorder.unattributed(), 0, "seed %d: every removal is explained" % seed_val)


func test_one_recorder_carries_a_batch_and_reconciles_each_match_apart() -> void:
	var recorder := BalanceMatchRecorder.new()
	for seed_val in [3, 4]:
		var outcome := BalanceMatchEngine.play(_setup(seed_val), recorder)
		assert_eq(recorder.reconcile(outcome.state, outcome.starting_units), "")
	var ids: Dictionary = {}
	for row in recorder.rows():
		ids[row["match_id"]] = true
	assert_gt(recorder.rows().size(), 0)
	assert_eq(ids.size(), 2, "two seeds, two derived ids — rows stay joinable to their match")


func test_every_played_turn_gets_exactly_one_row_per_side() -> void:
	var recorder := BalanceMatchRecorder.new()
	var outcome := BalanceMatchEngine.play(_setup(1234), recorder)
	var seen: Dictionary = {}
	for row in recorder.rows():
		var key := "%d/%d" % [row["day"], row["team"]]
		assert_false(seen.has(key), "day %s appears twice" % key)
		seen[key] = true
		assert_gt(int(row["commands"]), 0, "a filed row is a turn that was played")
	assert_true(outcome.day_ended >= 1)


# --- scoring -------------------------------------------------------------------


func test_a_day_cap_match_is_scored_on_properties_then_units_then_funds() -> void:
	var state := GameState.create(MapData.parse(BOARD, terrain_db), unit_db, chart)
	# create() runs the opening side's income tick and only its own, so red is up
	# a turn's funds before anyone has moved. Level that first: this test is about
	# the ranking, not about who ticked.
	state.funds[2] = state.funds[1]
	assert_eq(BalanceMatchEngine.tiebreak(state), 0, "a symmetric board opens level")
	state.funds[1] += 1
	assert_eq(BalanceMatchEngine.tiebreak(state), 1, "funds break a total tie")
	state.units.erase(state.units_of(2)[0])
	assert_eq(BalanceMatchEngine.tiebreak(state), 1, "and surviving units outrank funds")
	state.funds[1] = state.funds[2]
	state.units.erase(state.units_of(1)[0])
	state.units.erase(state.units_of(1)[0])
	assert_eq(BalanceMatchEngine.tiebreak(state), 2, "units decide when funds are level")
	# The base red opened owning: handing it over puts blue ahead on properties,
	# which outranks the units red still has.
	state.set_owner(Vector2i(1, 0), 2)
	state.units.append(Unit.create(unit_db.by_symbol("i"), 1, Vector2i(3, 1)))
	state.units.append(Unit.create(unit_db.by_symbol("i"), 1, Vector2i(4, 1)))
	assert_eq(BalanceMatchEngine.tiebreak(state), 2, "properties rank first of all")


func test_termination_names_how_the_match_ended() -> void:
	var state := GameState.create(MapData.parse(BOARD, terrain_db), unit_db, chart)
	assert_eq(BalanceMatchEngine.termination(state, false), "day_cap")
	assert_eq(BalanceMatchEngine.termination(state, true), "command_cap")
	state.winner = 1
	assert_eq(BalanceMatchEngine.termination(state, false), "hq", "the loser still has units")
	for unit in state.units_of(2):
		state.units.erase(unit)
	assert_eq(BalanceMatchEngine.termination(state, false), "rout")


func test_a_short_day_cap_stops_the_match_there() -> void:
	var outcome := BalanceMatchEngine.play(_setup(5, 3))
	assert_eq(outcome.termination, "day_cap")
	assert_lt(outcome.day_ended, 6, "the cap should bind well before the fixture resolves")
