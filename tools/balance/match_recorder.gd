class_name BalanceMatchRecorder
extends RefCounted
## Turn-by-turn telemetry for a Balance Lab match, and the optional per-command
## log beside it.
##
## It **observes** (plan D2). Nothing under core/ or ai/ gained a signal, a hook
## or a field for it: the recorder is handed each command just before and just
## after `apply()` — which the harness already brokers — and reads public
## GameState. What the Lab measures is therefore bit-for-bit the shipped game,
## and the tool cannot bend the game toward being measurable.
##
## Node-free on purpose, so GUT drives it directly (plan §8).
##
## ## Grain
##
## One row per **played turn**: match x day x side. A row covers everything from
## that side's start-of-turn tick to its own EndTurnCommand, so every event in
## the match lands in exactly one row. The tick is the seam that matters — a
## side's income, its paid repairs and any unit that dies with a dry tank all
## happen inside the *previous* side's EndTurnCommand.apply(), and they belong to
## the incoming side's row, which is why the row is opened in `after_apply` of
## that command rather than before it.
##
## ## Attribution (plan D3)
##
## A unit leaving the board is not always a death. Removals are diffed against a
## live set and then classified by *the command that caused them*:
##
##   - AttackCommand  — the target dying, or the attacker dying to counter-fire;
##                      cargo goes down with its transport either way
##   - EndTurnCommand — an air or sea unit whose tank ran dry in the start-of-turn
##                      tick (Orin Flux's jam can cause this a turn later)
##   - JoinCommand    — the mover merges into its twin: it left the board and
##                      nothing died, so it is counted apart from both kills and
##                      losses and the reconciliation still closes
##   - LoadCommand    — not a removal at all: a passenger keeps its place in
##                      `state.units` with `carrier` set, which is precisely why
##                      diffing the *unit list* is honest where diffing
##                      `unit_at()` would not be
##
## Anything else that removes a unit lands in `unattributed`, which
## `reconcile()` gates on — a miscount is a red build, not a quiet lie in the
## data.

## Keys of the per-turn row, in CSV column order.
const TIMELINE_COLUMNS: Array[String] = [
	"match_id",
	"day",
	"team",
	"commander",
	"tier",
	"funds_start",
	"income",
	"spent",
	"funds_end",
	"built",
	"built_value",
	"killed",
	"lost",
	"killed_value",
	"lost_value",
	"merged",
	"unit_count",
	"army_value",
	"properties",
	"captures",
	"power_charge",
	"power_fired",
	"commands",
	"planning_ms",
]

## The one wall-clock column. Everything else in a timeline row is a pure
## function of (map, seed, side specs), so a rerun reproduces it byte for byte;
## this one measures how long the planner thought and cannot. Determinism checks
## compare rows with it excluded — see tests/unit/test_balance_engine.gd.
const NONDETERMINISTIC_COLUMNS: Array[String] = ["planning_ms"]


## One turn being accumulated. Plain fields rather than a Dictionary so a typo'd
## key is a parse error instead of a silently absent column.
class TurnRow:
	var day := 0
	var team := 0
	var commander := ""
	var tier := ""
	var funds_start := 0
	var income := 0
	var spent := 0
	var built: Dictionary = {}  # unit id -> count
	var built_value := 0
	var killed: Dictionary = {}
	var killed_value := 0
	var lost: Dictionary = {}
	var lost_value := 0
	## Units that left the board without dying (a Join merge). Not a kill and not
	## a loss; carried so the reconciliation can close.
	var merged := 0
	var captures := 0
	var power_fired := false
	var commands := 0
	var planning_usec := 0


var _match_id := ""
var _tiers: Dictionary = {}  # team -> String
var _rows: Array[Dictionary] = []
var _command_log: Array[Dictionary] = []
var _log_commands := true
## Live units, by reference. A Dictionary rather than an Array: membership is
## asked once per unit per command, and the board can hold dozens.
var _live: Dictionary = {}
var _turn: TurnRow = null
var _seq := 0
var _unattributed := 0
## Where the match in progress starts, so one recorder can carry a whole batch
## and still reconcile each match against its own board.
var _match_row_start := 0
var _match_unattributed_start := 0
## Captured in before_apply because after the apply the answers are gone.
var _incoming_team := 0
var _incoming_funds := 0
var _capture_cell := Vector2i.ZERO
var _capture_owner_before := 0


## `log_commands` off keeps the per-command JSONL out of memory entirely, which
## is what makes a thousand-match sweep affordable.
func _init(log_commands: bool = true) -> void:
	_log_commands = log_commands


# --- lifecycle ---------------------------------------------------------------


## Opens the match and its first turn. Called after GameState.create, whose own
## start-of-turn tick has already run for the opening side — so the funds on the
## board *are* that tick, every side having started the match at zero.
func begin_match(match_id: String, state: GameState, tiers: Dictionary) -> void:
	_match_id = match_id
	_tiers = tiers.duplicate()
	_seq = 0
	_match_row_start = _rows.size()
	_match_unattributed_start = _unattributed
	_live.clear()
	for unit in state.units:
		_live[unit] = true
	var team := state.current_team
	_open_turn(state, int(state.funds.get(team, 0)))


func before_apply(state: GameState, command: Command, planning_usec: int = 0) -> void:
	if _turn == null:
		return
	_turn.commands += 1
	_turn.planning_usec += planning_usec
	if command is CaptureCommand:
		var capture := command as CaptureCommand
		_capture_cell = capture.path[capture.path.size() - 1]
		_capture_owner_before = state.owner_at(_capture_cell)
	elif command is EndTurnCommand:
		# The row closes on the side's own EndTurnCommand — before the apply, so
		# it reports the board that side is handing over, not the one the next
		# side's income tick has already changed.
		_incoming_team = state.next_team()
		_incoming_funds = int(state.funds.get(_incoming_team, 0))
		_close_turn(state)


func after_apply(state: GameState, command: Command) -> void:
	var removed := _removed_units(state)
	if command is EndTurnCommand:
		# The incoming side's tick has now run inside apply(): income, paid
		# repairs, and any unit lost to a dry tank. All of it is the *incoming*
		# side's, so its row opens before the removals are attributed.
		_open_turn(state, int(state.funds.get(state.current_team, 0)) - _incoming_funds)
	_attribute(removed, command)
	_refresh_live(state)
	if command is BuildCommand:
		_record_build(command as BuildCommand)
	elif command is CaptureCommand:
		_record_capture(state)
	elif command is PowerCommand and _turn != null:
		_turn.power_fired = true
	if _log_commands:
		_command_log.append(_log_entry(state, command))
	_seq += 1


## Closes whatever turn is still open. A match ends mid-turn (a rout or an HQ
## taken) or immediately after an EndTurnCommand opened a turn the day cap will
## not let anyone play — the latter has no commands in it and is dropped, so
## "one row per *played* turn" stays literally true.
func end_match(state: GameState) -> void:
	if _turn == null:
		return
	if _turn.commands == 0:
		_turn = null
		return
	_close_turn(state)


# --- output ------------------------------------------------------------------


func rows() -> Array[Dictionary]:
	return _rows


func command_log() -> Array[Dictionary]:
	return _command_log


## Removals no command explained. Non-zero means the recorder has fallen behind
## the rules — a new command that kills, most likely — and the run must fail
## rather than publish numbers nobody can trust.
func unattributed() -> int:
	return _unattributed


## Proves the timeline adds up against the board it describes, for the match that
## just ended. Returns "" when it does, otherwise the first discrepancy found.
##
## Two independent closures, because they fail differently: the funds arithmetic
## catches a spend the recorder missed, and the unit census catches a death it
## misfiled. `starting` is the per-team unit count the match opened with.
##
## Run per match rather than once per batch, so a failure names the match that
## broke instead of the batch that contains it.
func reconcile(state: GameState, starting: Dictionary) -> String:
	if _unattributed > _match_unattributed_start:
		return "%d unattributed unit removal(s)" % (_unattributed - _match_unattributed_start)
	var built: Dictionary = {}
	var lost: Dictionary = {}
	var killed: Dictionary = {}
	var merged: Dictionary = {}
	for row in _rows.slice(_match_row_start):
		var team: int = row["team"]
		if row["funds_start"] - row["spent"] != row["funds_end"]:
			return (
				"day %d team %d: funds_start %d - spent %d != funds_end %d"
				% [row["day"], team, row["funds_start"], row["spent"], row["funds_end"]]
			)
		built[team] = int(built.get(team, 0)) + _count_of(row["built"])
		lost[team] = int(lost.get(team, 0)) + _count_of(row["lost"])
		merged[team] = int(merged.get(team, 0)) + int(row["merged"])
		# A kill is recorded in the row of the side that was *taking the turn*,
		# so the victim's own team is the other one. Two-sided game; the sim's
		# own TEAMS list decides who that is.
		for other in GameState.TEAMS:
			if other != team:
				killed[other] = int(killed.get(other, 0)) + _count_of(row["killed"])
	for team in GameState.TEAMS:
		var expected := (
			int(starting.get(team, 0))
			+ int(built.get(team, 0))
			- int(lost.get(team, 0))
			- int(killed.get(team, 0))
			- int(merged.get(team, 0))
		)
		var actual := state.units_of(team).size()
		if expected != actual:
			return (
				"team %d: %d started + %d built - %d lost - %d killed by enemy - %d merged = %d, board has %d"
				% [
					team,
					int(starting.get(team, 0)),
					int(built.get(team, 0)),
					int(lost.get(team, 0)),
					int(killed.get(team, 0)),
					int(merged.get(team, 0)),
					expected,
					actual,
				]
			)
	return ""


# --- turn bookkeeping --------------------------------------------------------


func _open_turn(state: GameState, income: int) -> void:
	var team := state.current_team
	_turn = TurnRow.new()
	_turn.day = state.day
	_turn.team = team
	_turn.commander = String(state.commander_of(team).id)
	_turn.tier = String(_tiers.get(team, Difficulty.DEFAULT_ID))
	_turn.income = income
	_turn.funds_start = int(state.funds.get(team, 0))


## Freezes the end-of-turn half of the row and files it. Everything read here is
## the board as the side leaves it: what it still owns, what it is still worth,
## and how full its meter is.
func _close_turn(state: GameState) -> void:
	if _turn == null:
		return
	var team := _turn.team
	var row := {
		"match_id": _match_id,
		"day": _turn.day,
		"team": team,
		"commander": _turn.commander,
		"tier": _turn.tier,
		"funds_start": _turn.funds_start,
		"income": _turn.income,
		"spent": _turn.spent,
		"funds_end": int(state.funds.get(team, 0)),
		"built": _tally_text(_turn.built),
		"built_value": _turn.built_value,
		"killed": _tally_text(_turn.killed),
		"lost": _tally_text(_turn.lost),
		"killed_value": _turn.killed_value,
		"lost_value": _turn.lost_value,
		"merged": _turn.merged,
		"unit_count": state.units_of(team).size(),
		"army_value": _army_value(state, team),
		"properties": state.properties_of(team).size(),
		"captures": _turn.captures,
		"power_charge": _charge_pct(state, team),
		"power_fired": 1 if _turn.power_fired else 0,
		"commands": _turn.commands,
		"planning_ms": "%.1f" % (float(_turn.planning_usec) / 1000.0),
	}
	_rows.append(row)
	_turn = null


## Σ cost x HP fraction — the honest number, since a 2 HP tank is not a tank.
## Integer throughout, like every other value in the sim, so a rerun matches.
func _army_value(state: GameState, team: int) -> int:
	var total := 0
	for unit in state.units_of(team):
		total += unit.type.cost * unit.hp / 100
	return total


func _charge_pct(state: GameState, team: int) -> int:
	return roundi(state.commander_state(team).charge_ratio() * 100.0)


# --- attribution -------------------------------------------------------------


## Units that were live before this command and are not on the board after it.
func _removed_units(state: GameState) -> Array[Unit]:
	var present: Dictionary = {}
	for unit in state.units:
		present[unit] = true
	var gone: Array[Unit] = []
	for unit: Unit in _live:
		if not present.has(unit):
			gone.append(unit)
	return gone


func _refresh_live(state: GameState) -> void:
	_live.clear()
	for unit in state.units:
		_live[unit] = true


func _attribute(removed: Array[Unit], command: Command) -> void:
	if removed.is_empty():
		return
	if _turn == null:
		_unattributed += removed.size()
		return
	var merged_away: Unit = (command as JoinCommand).unit if command is JoinCommand else null
	for unit in removed:
		if unit == merged_away:
			_turn.merged += 1  # merged into its twin; nothing died
			continue
		if not _explains_removals(command):
			_unattributed += 1
			continue
		if unit.team == _turn.team:
			_tally(_turn.lost, unit.type.id)
			_turn.lost_value += unit.type.cost
		else:
			_tally(_turn.killed, unit.type.id)
			_turn.killed_value += unit.type.cost


## The commands a death may legitimately come out of. Attack kills directly;
## EndTurn's start-of-turn tick strands an empty tank; Power is listed because a
## future one-shot effect that damages is a doctrine change, not a recorder
## change. Anything else removing a unit is a rule the recorder has not been
## told about, and it is counted as unattributed rather than guessed at.
func _explains_removals(command: Command) -> bool:
	return command is AttackCommand or command is EndTurnCommand or command is PowerCommand


func _record_build(build: BuildCommand) -> void:
	if _turn == null or build.unit_type == null:
		return
	_turn.spent += build.unit_type.cost
	_turn.built_value += build.unit_type.cost
	_tally(_turn.built, build.unit_type.id)


## A capture that *completed* this turn — ownership actually changed hands.
## Chipping at a property over several turns is not a capture until it flips.
func _record_capture(state: GameState) -> void:
	if _turn == null:
		return
	var now := state.owner_at(_capture_cell)
	if now != _capture_owner_before and now == _turn.team:
		_turn.captures += 1


static func _tally(into: Dictionary, id: StringName) -> void:
	into[id] = int(into.get(id, 0)) + 1


## `infantry x2;tank` — ids alphabetical so a rerun writes the same cell, counts
## suffixed only above one, and semicolons throughout so the field never needs
## CSV quoting.
static func _tally_text(tally: Dictionary) -> String:
	var ids: Array = tally.keys()
	ids.sort()
	var parts: Array[String] = []
	for id: StringName in ids:
		var count: int = tally[id]
		parts.append(String(id) if count == 1 else "%s x%d" % [id, count])
	return ";".join(parts)


static func _count_of(text: String) -> int:
	var total := 0
	for part in text.split(";", false):
		var at := part.find(" x")
		total += int(part.substr(at + 2)) if at >= 0 else 1
	return total


# --- per-command log (plan Q3) -----------------------------------------------


## One JSONL record per applied command: what was issued, from where, to where,
## and what it did. Deterministic — no clock, no wall time — so a suspicious
## match can be stepped through offline and compared across runs.
func _log_entry(state: GameState, command: Command) -> Dictionary:
	var entry := {
		"match_id": _match_id,
		"seq": _seq,
		"day": _turn.day if _turn != null else state.day,
		"team": _turn.team if _turn != null else state.current_team,
		"type": _command_name(command),
	}
	if command is AttackCommand:
		var attack := command as AttackCommand
		entry["unit"] = String(attack.unit.type.id)
		entry["from"] = _cell(attack.path[0])
		entry["to"] = _cell(attack.path[attack.path.size() - 1])
		entry["target_cell"] = _cell(attack.target_cell)
		if attack.result != null:
			entry["damage"] = attack.result.attack_damage
			entry["counter"] = attack.result.counter_damage if attack.result.countered else -1
			entry["target_died"] = attack.result.defender_died
			entry["attacker_died"] = attack.result.attacker_died
	elif command is BuildCommand:
		var build := command as BuildCommand
		entry["unit"] = String(build.unit_type.id) if build.unit_type != null else ""
		entry["to"] = _cell(build.cell)
		entry["cost"] = build.unit_type.cost if build.unit_type != null else 0
	elif command is PowerCommand:
		var power := command as PowerCommand
		entry["commander"] = String(power.commander.id) if power.commander != null else ""
	elif command is CaptureCommand:
		var capture := command as CaptureCommand
		entry["unit"] = String(capture.unit.type.id)
		entry["from"] = _cell(capture.path[0])
		entry["to"] = _cell(_capture_cell)
		entry["captured"] = state.owner_at(_capture_cell) == capture.unit.team
	else:
		# Every other command that moves something — Move, Join, Load, Dive,
		# Drop, Supply — carries the same two fields, and each already logs under
		# its own name from _command_name. Asking for the fields rather than
		# naming the six classes means a seventh movement command logs correctly
		# with no edit here; EndTurnCommand has neither and falls straight
		# through.
		var mover: Unit = command.get("unit")
		var path: Variant = command.get("path")
		if mover != null and path is Array:
			var steps: Array = path
			entry["unit"] = String(mover.type.id)
			entry["from"] = _cell(steps[0])
			entry["to"] = _cell(steps[steps.size() - 1])
		if command is DropCommand:
			entry["drop_cell"] = _cell((command as DropCommand).drop_cell)
	return entry


static func _cell(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


## `AttackCommand` -> `attack`. Derived from the class rather than a lookup
## table, so a command added later logs under a sensible name with no edit here.
static func _command_name(command: Command) -> String:
	var script: Script = command.get_script()
	if script == null:
		return "command"
	return str(script.get_global_name()).trim_suffix("Command").to_snake_case()
