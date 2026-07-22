extends GutTest
## Attribution and reconciliation for the Balance Lab's telemetry recorder.
##
## The recorder classifies every unit that leaves the board by the command that
## caused it (balance plan D3), and a unit vanishing is not always a death: a
## Join merges two units, a Load hides one inside a transport, an empty tank
## strands an aircraft at the start of a turn. Each of those is pinned here, so a
## miscount is a red build rather than a quiet lie in a report someone tunes
## against.
##
## The recorder is Node-free precisely so these can be plain unit tests.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.rng.seed = 1
	return state


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


## Opens a recorder on `state` and returns it, with team 1 and 2 both on Normal.
func _recorder(state: GameState) -> BalanceMatchRecorder:
	var recorder := BalanceMatchRecorder.new()
	recorder.begin_match("test", state, {1: &"normal", 2: &"normal"})
	return recorder


func _apply(recorder: BalanceMatchRecorder, state: GameState, command: Command) -> void:
	assert_eq(command.validate(state), "", "command should be legal")
	recorder.before_apply(state, command)
	command.apply(state)
	recorder.after_apply(state, command)


## Ends the open turn and returns the row it produced.
func _close(recorder: BalanceMatchRecorder, state: GameState) -> Dictionary:
	var before := recorder.rows().size()
	_apply(recorder, state, EndTurnCommand.new())
	assert_eq(recorder.rows().size(), before + 1, "ending a turn should file exactly one row")
	return recorder.rows()[before]


# --- attribution --------------------------------------------------------------


func test_a_kill_is_the_attacker_s_and_a_counter_death_is_its_loss() -> void:
	# Both deaths land in one AttackCommand each, on the same side's turn, and
	# they must not be confused: the target dying is that side's *kill*, its own
	# unit dying to the counter is that side's *loss*.
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n2 i 1 0\n1 m 2 0\n2 t 3 0")
	var tank := state.units[0]
	var enemy_infantry := state.units[1]
	var mech := state.units[2]
	enemy_infantry.hp = 10  # one pip: the tank's shot kills outright
	mech.hp = 10  # and the tank it pokes counters lethally
	var recorder := _recorder(state)
	_apply(recorder, state, AttackCommand.new(tank, _path([Vector2i(0, 0)]), Vector2i(1, 0)))
	_apply(recorder, state, AttackCommand.new(mech, _path([Vector2i(2, 0)]), Vector2i(3, 0)))
	var row := _close(recorder, state)
	assert_eq(row["team"], 1)
	assert_eq(row["killed"], "infantry", "the enemy the tank shot down")
	assert_eq(row["lost"], "mech", "counter-fire kills our own, on our own turn")
	assert_eq(row["killed_value"], enemy_infantry.type.cost)
	assert_eq(row["lost_value"], mech.type.cost)
	assert_eq(row["merged"], 0, "neither death was a merge")
	assert_eq(recorder.unattributed(), 0)


func test_a_join_merge_is_neither_a_kill_nor_a_loss() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0")
	var mover := state.units[0]
	var twin := state.units[1]
	twin.hp = 50  # a full-strength twin refuses the join
	var recorder := _recorder(state)
	_apply(recorder, state, JoinCommand.new(mover, _path([Vector2i(0, 0), Vector2i(1, 0)])))
	var row := _close(recorder, state)
	assert_eq(row["merged"], 1, "the mover left the board without dying")
	assert_eq(row["lost"], "", "a merge is not a loss")
	assert_eq(row["killed"], "", "a merge is not a kill")
	assert_eq(row["unit_count"], 1, "one unit survives the merge")


func test_boarding_a_transport_is_not_a_removal_at_all() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var recorder := _recorder(state)
	_apply(recorder, state, LoadCommand.new(infantry, _path([Vector2i(0, 0), Vector2i(1, 0)])))
	var row := _close(recorder, state)
	assert_eq(row["lost"], "", "a passenger is not a casualty")
	assert_eq(row["merged"], 0)
	assert_eq(row["unit_count"], 2, "the passenger is still one of the team's units")
	assert_eq(recorder.unattributed(), 0)


func test_an_empty_tank_at_turn_start_is_the_owner_s_loss() -> void:
	# A fighter with one point of fuel cannot pay its upkeep, so it falls out of
	# the sky inside the incoming side's start-of-turn tick — a death with no
	# attacker, and one that belongs to the row of the turn it happens in.
	# Blue keeps a second unit so the loss is a loss and not a rout — a routed
	# side ends the match, and then there is no next turn to file a row for.
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0\n2 f 2 1\n2 i 3 1")
	var fighter := state.units[1]
	fighter.fuel = 1
	var recorder := _recorder(state)
	var red_row := _close(recorder, state)  # red's turn ends; blue's tick runs
	assert_eq(red_row["team"], 1)
	assert_eq(red_row["killed"], "", "red did not shoot it down")
	var blue_row := _close(recorder, state)
	assert_eq(blue_row["team"], 2)
	assert_eq(blue_row["lost"], "fighter", "the side that ran it dry owns the loss")
	assert_eq(blue_row["unit_count"], 1, "its surviving infantry")
	assert_eq(recorder.unattributed(), 0)


# --- the row's own arithmetic -------------------------------------------------


func test_a_build_is_spend_production_and_a_closing_funds_balance() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0\n[units]\n1 i 1 0")
	state.funds[1] = 5000
	var recorder := _recorder(state)
	var infantry_type := unit_db.by_symbol("i")
	_apply(recorder, state, BuildCommand.new(1, infantry_type, Vector2i(0, 0)))
	var row := _close(recorder, state)
	assert_eq(row["built"], "infantry")
	assert_eq(row["built_value"], infantry_type.cost)
	assert_eq(row["spent"], infantry_type.cost)
	assert_eq(
		int(row["funds_start"]) - int(row["spent"]),
		int(row["funds_end"]),
		"funds_start - spent = funds_end is the row's own closure"
	)


func test_repeated_builds_of_one_type_are_tallied_with_a_count() -> void:
	var state := _state("[terrain]\nB.B.\n[owners]\n1 0 0\n1 2 0\n[units]\n1 i 1 0")
	state.funds[1] = 9000
	var recorder := _recorder(state)
	var infantry_type := unit_db.by_symbol("i")
	_apply(recorder, state, BuildCommand.new(1, infantry_type, Vector2i(0, 0)))
	_apply(recorder, state, BuildCommand.new(1, infantry_type, Vector2i(2, 0)))
	var row := _close(recorder, state)
	assert_eq(row["built"], "infantry x2", "the same type twice is one entry with a count")
	assert_eq(row["built_value"], infantry_type.cost * 2)


func test_only_a_completed_capture_counts() -> void:
	# One infantry needs two turns on a city, so the first turn chips and the
	# second flips it — and only the second is a capture.
	var state := _state("[terrain]\nC.\n[units]\n1 i 1 0")
	var infantry := state.units[0]
	var recorder := _recorder(state)
	_apply(recorder, state, CaptureCommand.new(infantry, _path([Vector2i(1, 0), Vector2i(0, 0)])))
	var first := _close(recorder, state)
	assert_eq(first["captures"], 0, "chipping at a property is not yet a capture")
	_close(recorder, state)  # blue's turn
	_apply(recorder, state, CaptureCommand.new(infantry, _path([Vector2i(0, 0)])))
	var second := _close(recorder, state)
	assert_eq(second["captures"], 1, "the turn it flips is the turn it counts")
	assert_eq(second["properties"], 1)


func test_army_value_prorates_by_hp() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0")
	var tank := state.units[0]
	tank.hp = 50
	var recorder := _recorder(state)
	var row := _close(recorder, state)
	assert_eq(
		row["army_value"],
		tank.type.cost / 2,
		"a half-strength tank is worth half a tank, not a whole one"
	)


func test_the_first_row_opens_on_the_day_one_tick() -> void:
	# GameState.create runs the opening side's tick before any recorder exists,
	# so the match's first row has to pick it up from the board.
	var state := _state("[terrain]\nCC\n[owners]\n1 0 0\n1 1 0\n[units]\n1 i 0 0")
	var recorder := _recorder(state)
	var row := _close(recorder, state)
	assert_eq(row["day"], 1)
	assert_eq(row["income"], 2 * GameState.INCOME_PER_PROPERTY, "two cities, one tick")
	assert_eq(row["funds_start"], 2 * GameState.INCOME_PER_PROPERTY)


# --- reconciliation ------------------------------------------------------------


func test_reconcile_closes_over_a_match_with_a_kill_a_build_and_a_merge() -> void:
	var state := _state(
		"[terrain]\nB...\n....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n2 i 3 1"
	)
	state.funds[1] = 5000
	var starting := {1: 2, 2: 1}
	var mover := state.units[0]
	var twin := state.units[1]
	twin.hp = 40
	var recorder := _recorder(state)
	_apply(recorder, state, BuildCommand.new(1, unit_db.by_symbol("i"), Vector2i(0, 0)))
	_apply(recorder, state, JoinCommand.new(mover, _path([Vector2i(1, 0), Vector2i(2, 0)])))
	_close(recorder, state)
	_close(recorder, state)
	assert_eq(
		recorder.reconcile(state, starting),
		"",
		"the census must close: 2 started + 1 built - 1 merged = 2 on the board"
	)
	assert_eq(state.units_of(1).size(), 2)


func test_reconcile_reports_a_census_that_does_not_close() -> void:
	# Lie to the recorder about what the match started with; the closure must
	# notice rather than publish a number nobody can trust.
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	var recorder := _recorder(state)
	_close(recorder, state)
	assert_ne(recorder.reconcile(state, {1: 99, 2: 0}), "", "a wrong census must be reported")
