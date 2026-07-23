class_name BalanceMatchEngine
extends RefCounted
## Plays one headless AI-vs-AI match to a decision, a day cap, or a command cap,
## with an independent planner per side and an optional telemetry recorder.
##
## This is the loop the whole offline toolchain shares: the commander matrix, the
## difficulty ladder and the Balance Lab all run *this*, so a number one of them
## reports means the same thing in the other two. Extracting it is plan D1, and
## the merge bar for the extraction is a fixed-seed byte-diff of the two shipped
## gates' reports — see docs/balance_sim.md.
##
## It calls the same AIController and the same Command objects play does, so a
## match here resolves exactly as one in the battle scene given the same seed.
## Nothing here reads the clock or an unseeded RNG except the planning timer,
## whose output is reported and never fed back into the sim.
##
## Node-free, like core/ and ai/, so GUT drives it directly.

## Match-level safety net: a match that cannot resolve is a bug, and this stops
## the batch rather than the batch stopping the machine. Reaching it is a hard
## failure of a run, never a draw.
const COMMAND_CAP := 3000
## Per-turn safety net, and the one number the harness and the battle scene must
## agree on (plan D7). The scene has always force-ended a turn that ran this long
## so a planner bug could not hang the window; the harness applies the identical
## cut, so a watched match can never be trimmed where its headless row was let
## run. BattleAiRunner reads it from here for that reason — one owner, no drift.
const MAX_COMMANDS_PER_TURN := 300
const DEFAULT_DAYS := 20


## Everything one match needs. Built by the caller so the *planners* stay the
## caller's choice: the commander matrix deliberately hands both seats the same
## AIController instance (as it always has), while the difficulty ladder and the
## Lab give each side its own. That distinction is load-bearing for D1's
## byte-diff, which is why the engine takes planners rather than building them.
class Setup:
	var map: MapData
	var unit_db: UnitDB
	var chart: DamageChart
	var seed_val := 0
	var days_cap := DEFAULT_DAYS
	var command_cap := COMMAND_CAP
	## team -> CommanderType. A team with no entry plays neutral.
	var commanders: Dictionary = {}
	## team -> AIController. Both teams must have one.
	var planners: Dictionary = {}
	## team -> StringName tier id. Labelling only — the tier's whole effect is
	## the profile already baked into that side's planner (difficulty plan D2).
	var tiers: Dictionary = {}
	## Joins this match's timeline rows to its match row. Left empty, one is
	## derived from the spec; a caller that plays the same spec twice — the two
	## seatings of a mirror — must supply its own, or the two would collide.
	var match_id := ""


class Outcome:
	var state: GameState
	## The team that won, decided or scored; 0 only when every tiebreak measure
	## ties, or when the command cap tripped.
	var winner := 0
	var termination := ""
	var day_ended := 0
	var commands := 0
	var rejected := 0
	var cap_stall := false
	var turn_cap_hits := 0
	var powers: Dictionary = {}
	var first_ready: Dictionary = {}
	var first_fired: Dictionary = {}
	var planning_usec: Dictionary = {}
	var planning_turns: Dictionary = {}
	## team -> unit count the match opened with, for the recorder's census.
	var starting_units: Dictionary = {}


## Plays `setup` through. `recorder` may be null; when present it is handed every
## command either side of `apply()` and nothing else — it never influences a
## decision, which is what keeps the measured game the shipped one (plan D2).
static func play(setup: Setup, recorder: BalanceMatchRecorder = null) -> Outcome:
	var outcome := Outcome.new()
	# Commanders are handed to create so the opening side's day-1 begin_turn runs
	# against its real doctrine, not neutral — the same asymmetry the battle scene
	# had to fix.
	var state := GameState.create(setup.map, setup.unit_db, setup.chart, setup.commanders)
	if state == null:
		outcome.termination = "invalid_map"
		return outcome
	state.rng.seed = setup.seed_val
	outcome.state = state
	for team in GameState.TEAMS:
		outcome.powers[team] = 0
		outcome.first_ready[team] = -1
		outcome.first_fired[team] = -1
		outcome.starting_units[team] = state.units_of(team).size()
	if recorder != null:
		recorder.begin_match(_match_id(setup), state, setup.tiers)

	var commands_this_turn := 0
	while (
		state.winner == 0 and state.day <= setup.days_cap and outcome.commands < setup.command_cap
	):
		var team := state.current_team
		var co_state := state.commander_state(team)
		if outcome.first_ready[team] < 0 and co_state.is_ready():
			outcome.first_ready[team] = state.day
		var started := Time.get_ticks_usec()
		var planner: AIController = setup.planners[team]
		var command: Command = planner.plan_next_command(state)
		var planning_usec := Time.get_ticks_usec() - started
		_record_time(outcome, team, planning_usec, command is EndTurnCommand)
		if commands_this_turn >= MAX_COMMANDS_PER_TURN and not (command is EndTurnCommand):
			# The scene's cut, applied here too (D7). Not counted as a rejection:
			# the planner did nothing illegal, it simply overstayed.
			outcome.turn_cap_hits += 1
			command = EndTurnCommand.new()
		if command.validate(state) != "":
			outcome.rejected += 1
			command = EndTurnCommand.new()
			if command.validate(state) != "":
				break
		if command is PowerCommand:
			outcome.powers[team] += 1
			if outcome.first_fired[team] < 0:
				outcome.first_fired[team] = state.day
		if recorder != null:
			recorder.before_apply(state, command, planning_usec)
		commands_this_turn = 0 if command is EndTurnCommand else commands_this_turn + 1
		command.apply(state)
		if recorder != null:
			recorder.after_apply(state, command)
		outcome.commands += 1

	if recorder != null:
		recorder.end_match(state)
	outcome.cap_stall = outcome.commands >= setup.command_cap
	outcome.day_ended = state.day
	outcome.winner = state.winner
	# A rule-based AI rarely races to an HQ, so most matches reach the day cap
	# undecided. Rather than throw that data away as a draw, decide day-cap games
	# on score the way Advance Wars ranks a timed match. `termination` still
	# records that it went to the cap, so natural wins and scored wins stay
	# distinguishable in the CSV.
	if outcome.winner == 0 and not outcome.cap_stall:
		outcome.winner = tiebreak(state)
	outcome.termination = termination(state, outcome.cap_stall)
	return outcome


## rout (loser has no units), hq (loser was routed off its HQ but still has
## units), day_cap (reached the day limit; the row's winner was decided on
## score), or command_cap (a match that would not resolve — a bug, and a hard
## failure of the run).
static func termination(state: GameState, cap_stall: bool) -> String:
	if state.winner != 0:
		var loser := swap_team(state.winner)
		return "rout" if state.units_of(loser).is_empty() else "hq"
	if cap_stall:
		return "command_cap"
	return "day_cap"


## Ranks a timed match on properties, then surviving units, then funds — the
## standard Advance Wars timed-match order. 0 only when every measure ties, which
## on a symmetric board is the honest outcome of two identical doctrines playing
## to a standstill.
static func tiebreak(state: GameState) -> int:
	for measure: Array in [
		[state.properties_of(1).size(), state.properties_of(2).size()],
		[state.units_of(1).size(), state.units_of(2).size()],
		[int(state.funds.get(1, 0)), int(state.funds.get(2, 0))],
	]:
		if measure[0] != measure[1]:
			return 1 if measure[0] > measure[1] else 2
	return 0


static func swap_team(team: int) -> int:
	if team == 1:
		return 2
	if team == 2:
		return 1
	return team


## Planning wall-clock per team, a turn counted each time one ends. The only
## number the engine produces that is not reproducible run to run, so it is
## reported and never gated on — it answers the standing "does the extra
## thinking cost a perceptible pause?" watch item for free on every run.
static func _record_time(outcome: Outcome, team: int, usec: int, ended_turn: bool) -> void:
	outcome.planning_usec[team] = int(outcome.planning_usec.get(team, 0)) + usec
	if ended_turn:
		outcome.planning_turns[team] = int(outcome.planning_turns.get(team, 0)) + 1


## A stable, readable key joining a timeline row to its match row. Derived from
## the spec, never from a counter or a clock, so the same batch rerun writes the
## same ids and two runs can be diffed line for line.
static func _match_id(setup: Setup) -> String:
	if setup.match_id != "":
		return setup.match_id
	var name := setup.map.source_path.get_file().trim_suffix(".txt")
	if name == "":
		name = "map"
	var sides: Array[String] = []
	for team in GameState.TEAMS:
		var co: CommanderType = setup.commanders.get(team)
		var co_id := String(co.id) if co != null else String(CommanderType.NEUTRAL_ID)
		sides.append("%s-%s" % [co_id, setup.tiers.get(team, Difficulty.DEFAULT_ID)])
	return "%s|%s|%s|%d" % [name, sides[0], sides[1], setup.seed_val]
