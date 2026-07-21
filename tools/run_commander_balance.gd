extends SceneTree
## Offline commander balance runner (readiness plan G4). Plays AI-vs-AI matches
## across every commander pairing, on rotationally-symmetric scenarios, with
## paired seeds, and writes a CSV of per-match rows plus a JSON summary with the
## plan's thresholds evaluated. It is a *measurement* tool, not a gate: the
## per-hook unit tests and the AI-vs-AI legality soak stay the correctness net;
## this quantifies balance so tuning has evidence behind it.
##
## It calls the exact same AIController and Commands play does, so a match here
## resolves identically to one in the battle scene given the same seed — the
## determinism the plan's report acceptance criteria require (same scenario +
## seed => byte-identical rows on a rerun; nothing here reads the clock or an
## unseeded RNG).
##
## Usage (headless; see `make commander-balance`):
##   Godot --headless --path . -s res://tools/run_commander_balance.gd -- [flags]
##     --commanders=alina_ward,viktor_draeg   subset (default: all twelve)
##     --scenarios=clash,ridge                subset (default: all three)
##     --seeds=4                              paired seed count (default: 4)
##     --neutral                              add each commander vs No Commander
##     --days=20                              day cap before a match is a draw
##     --out=reports/commander_balance        output directory (default shown)
##
## The full batch (no flags) is every ordered pair on every scenario at four
## seeds — an explicit release task, deliberately out of `make test`; its size
## and the thresholds it is read against are in docs/commander_balance.md.
## A focused `--commanders`/`--scenarios`/`--seeds` run is the fast iteration loop.
##
## `--difficulty-check` (see `make difficulty-check`) is a second, opt-in mode
## asking a different question: do the tiers actually order Easy < Normal <
## Difficult? Tier against tier, no commanders, both mirrored maps, sides
## swapped, gated on DIFFICULTY_GATE_PCT. Difficulty ships no economy or damage
## handicap, so that win rate *is* the whole claim (plan D2).

const COMMAND_CAP := 3000
const DEFAULT_DAYS := 20
const DEFAULT_SEEDS := 4
const SEED_BASE := 1000
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"

## The plan's bands (section 06). Soft — a commander outside them is a review
## trigger, not an automatic nerf — so they colour the summary but never fail the
## run. Only the hard invariants (zero rejected commands, zero cap stalls) do.
const BAND_PREFERRED := Vector2(45.0, 55.0)
const BAND_WARNING := Vector2(40.0, 60.0)
const MAX_SIDE_BIAS_PP := 5.0

## --- difficulty check (plan DF4) ---------------------------------------------
##
## Two committed maps, small and large, because the gate has to answer whether
## the extra thinking pays with room to manoeuvre as well as without. Both are
## exactly 180-degree symmetric (asserted first), so a win here is planning.
const DIFFICULTY_MAPS: Array[String] = ["scrimmage", "ironworks"]
## Adjacent tiers only: each pairing asks whether one step up the ladder is a
## real step. Higher tier second.
const DIFFICULTY_PAIRINGS: Array = [[&"easy", &"normal"], [&"normal", &"hard"]]
## The acceptance gate. With identical economies, vision and dice at every tier
## this is a pure planning-skill differential — what "smarter, not cheating" has
## to prove. Missing it means tuning the .tres, never loosening this number.
const DIFFICULTY_GATE_PCT := 70.0

const DIFFICULTY_CSV_COLUMNS: Array[String] = [
	"map",
	"seed",
	"low_tier",
	"high_tier",
	"high_side",
	"winner",
	"high_won",
	"termination",
	"day_ended",
	"commands",
	"rejected",
	"cap_stall",
]

## Three 180-degree rotationally-symmetric boards (see _assert_symmetric), so
## neither side gets a terrain or income edge and a first-side bias in the
## results is the doctrines' doing, not the map's.
##
## clash: open and decisive — both armies in reach on day one, so games resolve
## rather than stall into day-cap draws. ridge: the same fairness with more
## terrain between the lines (woods, mountains, four contested cities). combined:
## all three domains at once — an airfield, a port and a shared channel — because
## a doctrine tuned only against tanks is tuned against a third of the game, and
## the hooks that read a unit's move class or domain (Viktor Draeg's breakthrough,
## Nia Rowan's terrain discount, Cassian Rook's heavies) behave differently when
## half the army is not on the ground.
##
## Its lake is centred, which is what keeps it self-symmetric under the rotation
## while both fleets share one basin — and it is small enough that the land armies
## walk past it rather than around a coast. That last part is not decoration: an
## earlier, larger version of this board separated the armies with water, ground
## to the day cap in 430 of 432 matches, and produced a twenty-point first-side
## bias out of the tiebreak alone. A fixture that does not resolve measures the
## clock, not the doctrines.
const SCENARIOS := {
	"clash":
	"""
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
""",
	"ridge":
	"""
[terrain]
.Q.B....F..C
..........M.
....F.......
...M....C...
...C....M...
.......F....
.M..........
C..F....B.Q.
[owners]
1 1 0
1 3 0
2 10 7
2 8 7
[units]
1 t 4 1
1 i 3 1
1 r 5 2
1 m 2 2
2 t 7 6
2 i 8 6
2 r 6 5
2 m 9 5
""",
	"combined":
	"""
[terrain]
.QB.A........
.....CS......
.....SSS...C.
C...FSSSS....
...PSSSSSP...
....SSSSF...C
.C...SSS.....
......SC.....
........A.BQ.
[owners]
1 1 0
2 11 8
1 2 0
2 10 8
1 4 0
2 8 8
1 3 4
2 9 4
[units]
1 i 2 3
2 i 10 5
1 m 3 3
2 m 9 5
1 t 4 3
2 t 8 5
1 r 2 5
2 r 10 3
1 h 4 5
2 h 8 3
1 c 5 4
2 c 7 4
"""
}

const CSV_COLUMNS: Array[String] = [
	"scenario",
	"seed",
	"red",
	"blue",
	"winner",
	"termination",
	"day_ended",
	"commands",
	"red_powers",
	"blue_powers",
	"red_first_ready",
	"red_first_fired",
	"blue_first_ready",
	"blue_first_fired",
	"red_units",
	"blue_units",
	"red_props",
	"blue_props",
	"red_funds",
	"blue_funds",
	"rejected",
	"cap_stall",
]

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB
var difficulty_db: DifficultyDB

var _commander_ids: Array[StringName] = []
var _scenario_names: Array[String] = []
var _seed_count := DEFAULT_SEEDS
var _days_cap := DEFAULT_DAYS
var _include_neutral := false
var _difficulty_check := false
var _out_dir := ""


func _init() -> void:
	_load_dbs()
	_parse_args()
	if _difficulty_check:
		_run_difficulty_check()
		return
	for name in _scenario_names:
		if not _assert_symmetric(name):
			return
	var rows := _run_all()
	var summary := _summarise(rows)
	_write_reports(rows, summary)
	_print_summary(summary)
	# Hard invariants only: a rejected command or a cap stall means the AI and the
	# rules disagree, or a match never resolves — both real bugs. Out-of-band win
	# rates are review triggers and never fail the run.
	var failed: bool = summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0
	quit(1 if failed else 0)


# --- setup -------------------------------------------------------------------


func _load_dbs() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load(DAMAGE_CHART_PATH)
	commander_db = CommanderDB.load_default()
	difficulty_db = DifficultyDB.load_default()


func _parse_args() -> void:
	_commander_ids = _all_commander_ids()
	_scenario_names = []
	for name: String in SCENARIOS:
		_scenario_names.append(name)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--commanders="):
			_commander_ids = _parse_commander_list(arg.get_slice("=", 1))
		elif arg.begins_with("--scenarios="):
			_scenario_names = _parse_scenario_list(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			_seed_count = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--days="):
			_days_cap = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		elif arg == "--neutral":
			_include_neutral = true
		elif arg == "--difficulty-check":
			_difficulty_check = true
	if _out_dir == "":
		_out_dir = "reports/difficulty_check" if _difficulty_check else "reports/commander_balance"


func _all_commander_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for co in commander_db.all():
		if co.id != CommanderType.NEUTRAL_ID:
			ids.append(co.id)
	return ids


func _parse_commander_list(value: String) -> Array[StringName]:
	var ids: Array[StringName] = []
	for token in value.split(",", false):
		var id := StringName(token.strip_edges())
		if commander_db.has(id) and id != CommanderType.NEUTRAL_ID:
			ids.append(id)
		else:
			push_error("balance: unknown commander id '%s', skipping" % id)
	return ids


func _parse_scenario_list(value: String) -> Array[String]:
	var names: Array[String] = []
	for token in value.split(",", false):
		var name := token.strip_edges()
		if SCENARIOS.has(name):
			names.append(name)
		else:
			push_error("balance: unknown scenario '%s', skipping" % name)
	return names


## Fails loudly if a scenario is not 180-degree rotationally symmetric with the
## teams swapped: terrain must map onto itself, and every owned cell and unit must
## have a mirror belonging to the other side. A broken map would quietly bias the
## whole run, which is the one thing the paired design exists to prevent.
func _assert_symmetric(name: String) -> bool:
	return _assert_map_symmetric(name, MapData.parse(SCENARIOS[name], terrain_db))


## The same check against any already-parsed board, so the difficulty gate can
## hold its committed maps to the identical standard as the embedded scenarios.
func _assert_map_symmetric(name: String, map: MapData) -> bool:
	if map == null:
		return _fatal("cannot load board '%s'" % name)
	var state := GameState.create(map, unit_db, chart)
	var w := map.width
	var h := map.height
	for y in h:
		for x in w:
			var a := Vector2i(x, y)
			var b := Vector2i(w - 1 - x, h - 1 - y)
			if map.terrain_at(a).id != map.terrain_at(b).id:
				return _fatal("board '%s' terrain not symmetric at %s vs %s" % [name, a, b])
			if state.owner_at(a) != _swap_team(state.owner_at(b)):
				return _fatal("board '%s' ownership not mirror-symmetric at %s" % [name, a])
	for unit in state.units:
		var mirror := Vector2i(w - 1 - unit.cell.x, h - 1 - unit.cell.y)
		var twin := state.unit_at(mirror)
		if twin == null or twin.team != _swap_team(unit.team) or twin.type.id != unit.type.id:
			return _fatal(
				"board '%s' unit %s at %s has no mirror" % [name, unit.type.id, unit.cell]
			)
	return true


func _swap_team(team: int) -> int:
	if team == 1:
		return 2
	if team == 2:
		return 1
	return team


func _fatal(message: String) -> bool:
	push_error("balance: " + message)
	quit(2)
	return false


# --- run ---------------------------------------------------------------------


func _run_all() -> Array[Dictionary]:
	var pairings := _pairings()
	var total := pairings.size() * _scenario_names.size() * _seed_count
	print(
		(
			"balance: %d commanders, %d scenarios, %d seeds -> %d matches"
			% [_commander_ids.size(), _scenario_names.size(), _seed_count, total]
		)
	)
	var rows: Array[Dictionary] = []
	var done := 0
	for scenario in _scenario_names:
		var map_str: String = SCENARIOS[scenario]
		for pair in pairings:
			for s in _seed_count:
				# Paired seeds: the same seed set for every pairing, so A-vs-B and
				# B-vs-A (ordered pairs) meet on identical luck and the side-swap is
				# clean. Seeds vary by scenario so the two boards are not correlated.
				var seed_val := SEED_BASE + s + hash(scenario) % 1000
				rows.append(_play(scenario, map_str, pair[0], pair[1], seed_val))
				done += 1
				if done % 100 == 0:
					print("balance: %d / %d matches" % [done, total])
	return rows


## Every ordered pair, mirrors included (a commander against itself is a control:
## a symmetric board plus a mirror pairing should sit at 50%). Optionally each
## commander against neutral, both sides, as a power-level reference.
func _pairings() -> Array:
	var pairs: Array = []
	for red in _commander_ids:
		for blue in _commander_ids:
			pairs.append([red, blue])
	if _include_neutral:
		for id in _commander_ids:
			pairs.append([id, CommanderType.NEUTRAL_ID])
			pairs.append([CommanderType.NEUTRAL_ID, id])
	return pairs


## Plays one match to a decision, a day cap, or the command cap, tallying the
## per-match metrics the plan's report calls for. Mirrors the AI-vs-AI soak's
## loop exactly, so it inherits the same "planner never proposes an illegal
## command" guarantee — a rejection is counted here rather than asserted, so the
## batch finishes and the summary reports how many and where.
func _play(
	scenario: String, map_str: String, red: StringName, blue: StringName, seed_val: int
) -> Dictionary:
	var map := MapData.parse(map_str, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = seed_val
	state.set_commander(1, commander_db.by_id(red))
	state.set_commander(2, commander_db.by_id(blue))
	var ai := AIController.new(unit_db)

	var powers := {1: 0, 2: 0}
	var first_ready := {1: -1, 2: -1}
	var first_fired := {1: -1, 2: -1}
	var rejected := 0
	var commands := 0
	while state.winner == 0 and state.day <= _days_cap and commands < COMMAND_CAP:
		var team := state.current_team
		var co_state := state.commander_state(team)
		if first_ready[team] < 0 and co_state.is_ready():
			first_ready[team] = state.day
		var command := ai.plan_next_command(state)
		if command.validate(state) != "":
			rejected += 1
			command = EndTurnCommand.new()
			if command.validate(state) != "":
				break
		if command is PowerCommand:
			powers[team] += 1
			if first_fired[team] < 0:
				first_fired[team] = state.day
		command.apply(state)
		commands += 1

	var cap_stall := commands >= COMMAND_CAP
	# A rule-based AI rarely races to an HQ, so most matches reach the day cap
	# undecided. Rather than throw that data away as a draw, decide day-cap games
	# on score — properties, then units, then funds, the way Advance Wars itself
	# ranks a timed match. `termination` still records that it went to the cap, so
	# natural wins and scored wins stay distinguishable in the CSV.
	var winner: int = state.winner
	if winner == 0 and not cap_stall:
		winner = _tiebreak(state)
	return {
		"scenario": scenario,
		"seed": seed_val,
		"red": String(red),
		"blue": String(blue),
		"winner": winner,
		"termination": _termination(state, cap_stall),
		"day_ended": state.day,
		"commands": commands,
		"red_powers": powers[1],
		"blue_powers": powers[2],
		"red_first_ready": first_ready[1],
		"red_first_fired": first_fired[1],
		"blue_first_ready": first_ready[2],
		"blue_first_fired": first_fired[2],
		"red_units": state.units_of(1).size(),
		"blue_units": state.units_of(2).size(),
		"red_props": state.properties_of(1).size(),
		"blue_props": state.properties_of(2).size(),
		"red_funds": int(state.funds.get(1, 0)),
		"blue_funds": int(state.funds.get(2, 0)),
		"rejected": rejected,
		"cap_stall": 1 if cap_stall else 0,
	}


## rout (loser has no units), hq (loser was routed off its HQ but still has
## units), day_cap (reached the day limit; the row's winner was decided on
## score), or command_cap (a match that would not resolve — a bug, and a hard
## failure of the run).
func _termination(state: GameState, cap_stall: bool) -> String:
	if state.winner != 0:
		var loser := _swap_team(state.winner)
		return "rout" if state.units_of(loser).is_empty() else "hq"
	if cap_stall:
		return "command_cap"
	return "day_cap"


## Ranks a timed match on properties, then surviving units, then funds — the
## standard Advance Wars timed-match order. 0 only when every measure ties, which
## on a symmetric board is the honest outcome of two identical doctrines (a mirror
## pairing) playing to a standstill.
func _tiebreak(state: GameState) -> int:
	for measure: Array in [
		[state.properties_of(1).size(), state.properties_of(2).size()],
		[state.units_of(1).size(), state.units_of(2).size()],
		[int(state.funds.get(1, 0)), int(state.funds.get(2, 0))],
	]:
		if measure[0] != measure[1]:
			return 1 if measure[0] > measure[1] else 2
	return 0


# --- summary -----------------------------------------------------------------


func _summarise(rows: Array[Dictionary]) -> Dictionary:
	var per_co: Dictionary = {}  # id -> {matches, wins}
	for id in _commander_ids:
		per_co[String(id)] = {"matches": 0, "wins": 0}
	var red_wins := 0
	var blue_wins := 0
	var decisive := 0
	var draws := 0
	var total_rejected := 0
	var total_cap_stalls := 0
	for row in rows:
		total_rejected += int(row["rejected"])
		total_cap_stalls += int(row["cap_stall"])
		var red: String = row["red"]
		var blue: String = row["blue"]
		var winner: int = row["winner"]
		# Each commander's aggregate win rate is already side-normalised: ordered
		# pairs mean every commander plays each opponent from both sides.
		_credit(per_co, red, winner == 1)
		_credit(per_co, blue, winner == 2)
		# First-side bias measured on non-mirror decisive games only — a mirror is
		# 50% by construction and would wash the signal out.
		if winner != 0:
			decisive += 1
			if red != blue:
				if winner == 1:
					red_wins += 1
				else:
					blue_wins += 1
		else:
			draws += 1

	var commanders: Array = []
	for id in _commander_ids:
		var key := String(id)
		var stats: Dictionary = per_co[key]
		var rate := 100.0 * float(stats["wins"]) / maxf(1.0, float(stats["matches"]))
		(
			commanders
			. append(
				{
					"id": key,
					"matches": stats["matches"],
					"wins": stats["wins"],
					"win_rate": rate,
					"flag": _band_flag(rate),
				}
			)
		)
	commanders.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["win_rate"] < b["win_rate"]
	)

	var non_mirror_decisive := red_wins + blue_wins
	var side_bias := 0.0
	if non_mirror_decisive > 0:
		side_bias = 100.0 * float(red_wins - blue_wins) / float(non_mirror_decisive)
	return {
		"matches": rows.size(),
		"decisive": decisive,
		"draws": draws,
		"total_rejected": total_rejected,
		"total_cap_stalls": total_cap_stalls,
		"red_side_win_pct": 100.0 * float(red_wins) / maxf(1.0, float(non_mirror_decisive)),
		"side_bias_pp": side_bias,
		"side_bias_ok": absf(side_bias) <= MAX_SIDE_BIAS_PP,
		"commanders": commanders,
	}


func _credit(per_co: Dictionary, id: String, won: bool) -> void:
	if not per_co.has(id):
		return
	per_co[id]["matches"] += 1
	if won:
		per_co[id]["wins"] += 1


func _band_flag(rate: float) -> String:
	if rate < BAND_WARNING.x or rate > BAND_WARNING.y:
		return "WARN"
	if rate < BAND_PREFERRED.x or rate > BAND_PREFERRED.y:
		return "watch"
	return "ok"


# --- output ------------------------------------------------------------------


func _write_reports(rows: Array[Dictionary], summary: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join(_out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_write_csv(dir.path_join("matches.csv"), rows, CSV_COLUMNS)
	_write_json(dir.path_join("summary.json"), summary)
	print("balance: wrote matches.csv and summary.json to %s" % _out_dir)


func _write_csv(path: String, rows: Array[Dictionary], columns: Array[String]) -> void:
	var lines: Array[String] = [",".join(columns)]
	for row in rows:
		var cells: Array[String] = []
		for column in columns:
			cells.append(str(row[column]))
		lines.append(",".join(cells))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("balance: cannot write %s" % path)
		return
	file.store_string("\n".join(lines) + "\n")


func _write_json(path: String, summary: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("balance: cannot write %s" % path)
		return
	file.store_string(JSON.stringify(summary, "\t"))


func _print_summary(summary: Dictionary) -> void:
	print("\n=== commander balance ===")
	print(
		(
			"matches %d   decisive %d   draws %d   rejected %d   cap-stalls %d"
			% [
				summary["matches"],
				summary["decisive"],
				summary["draws"],
				summary["total_rejected"],
				summary["total_cap_stalls"],
			]
		)
	)
	print(
		(
			"first-side bias %+.1f pp (%s, threshold +-%.0f)"
			% [
				summary["side_bias_pp"],
				"ok" if summary["side_bias_ok"] else "REVIEW",
				MAX_SIDE_BIAS_PP,
			]
		)
	)
	print("commander            win%%   n   band")
	for co: Dictionary in summary["commanders"]:
		print("  %-18s %5.1f  %3d  %s" % [co["id"], co["win_rate"], co["matches"], co["flag"]])
	if summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0:
		print("FAIL: rejected commands or cap stalls — the AI and the rules disagree.")
	else:
		print("hard invariants clean (0 rejected, 0 cap stalls). Band flags are review triggers.")


# --- difficulty check (plan DF4) ---------------------------------------------


## Plays the tier ladder and gates on it: each adjacent pairing on both mirrored
## maps, every seed, from both seats, with no commanders on either side — a
## doctrine would be noise in a measurement of planning alone.
func _run_difficulty_check() -> void:
	for name in DIFFICULTY_MAPS:
		if not _assert_map_symmetric(name, _difficulty_map(name)):
			return
	for pair: Array in DIFFICULTY_PAIRINGS:
		for id: StringName in pair:
			if not difficulty_db.has(id):
				_fatal("unknown difficulty tier '%s'" % id)
				return

	var total := DIFFICULTY_PAIRINGS.size() * DIFFICULTY_MAPS.size() * _seed_count * 2
	print(
		(
			"difficulty: %d pairings x %d maps x %d seeds x 2 sides -> %d matches"
			% [DIFFICULTY_PAIRINGS.size(), DIFFICULTY_MAPS.size(), _seed_count, total]
		)
	)
	var rows: Array[Dictionary] = []
	var timing: Dictionary = {}
	var done := 0
	for map_name in DIFFICULTY_MAPS:
		for pair: Array in DIFFICULTY_PAIRINGS:
			for s in _seed_count:
				# Paired seeds, same shape as the commander run: both seatings of a
				# pairing meet on identical luck, so the side-swap is clean.
				var seed_val := SEED_BASE + s + hash(map_name) % 1000
				for high_is_red: bool in [true, false]:
					rows.append(
						_play_tiers(map_name, pair[0], pair[1], high_is_red, seed_val, timing)
					)
					done += 1
					if done % 10 == 0:
						print("difficulty: %d / %d matches" % [done, total])

	var summary := _summarise_difficulty(rows, timing)
	_write_difficulty_reports(rows, summary)
	_print_difficulty_summary(summary)
	quit(0 if summary["passed"] else 1)


func _difficulty_map(name: String) -> MapData:
	return MapData.load_from_file("res://maps/%s.txt" % name, terrain_db)


## One tier-versus-tier match. `high_is_red` swaps which seat the stronger tier
## takes, and each side gets its own AIController — its own profile, and its own
## per-turn threat map.
func _play_tiers(
	map_name: String,
	low: StringName,
	high: StringName,
	high_is_red: bool,
	seed_val: int,
	timing: Dictionary
) -> Dictionary:
	var state := GameState.create(_difficulty_map(map_name), unit_db, chart)
	state.rng.seed = seed_val
	var red_tier: StringName = high if high_is_red else low
	var blue_tier: StringName = low if high_is_red else high
	var planners := {
		1: AIController.new(unit_db, difficulty_db.by_id(red_tier).profile()),
		2: AIController.new(unit_db, difficulty_db.by_id(blue_tier).profile()),
	}
	var tiers := {1: red_tier, 2: blue_tier}

	var rejected := 0
	var commands := 0
	while state.winner == 0 and state.day <= _days_cap and commands < COMMAND_CAP:
		var team := state.current_team
		var planner: AIController = planners[team]
		var tier: StringName = tiers[team]
		var started := Time.get_ticks_usec()
		var command := planner.plan_next_command(state)
		_record_time(timing, tier, Time.get_ticks_usec() - started, command is EndTurnCommand)
		if command.validate(state) != "":
			rejected += 1
			command = EndTurnCommand.new()
			if command.validate(state) != "":
				break
		command.apply(state)
		commands += 1

	var cap_stall := commands >= COMMAND_CAP
	var winner: int = state.winner
	if winner == 0 and not cap_stall:
		winner = _tiebreak(state)
	var high_team := 1 if high_is_red else 2
	return {
		"map": map_name,
		"seed": seed_val,
		"low_tier": String(low),
		"high_tier": String(high),
		"high_side": "red" if high_is_red else "blue",
		"winner": winner,
		"high_won": 1 if winner == high_team else 0,
		"termination": _termination(state, cap_stall),
		"day_ended": state.day,
		"commands": commands,
		"rejected": rejected,
		"cap_stall": 1 if cap_stall else 0,
	}


## Planning wall-clock per tier, a turn counted each time one ends. The only
## number here that is not reproducible run to run, so it is reported and never
## gated on — it answers R3: does the extra thinking cost a perceptible pause?
func _record_time(timing: Dictionary, tier: StringName, usec: int, ended_turn: bool) -> void:
	var key := String(tier)
	if not timing.has(key):
		timing[key] = {"usec": 0, "turns": 0}
	timing[key]["usec"] += usec
	if ended_turn:
		timing[key]["turns"] += 1


func _summarise_difficulty(rows: Array[Dictionary], timing: Dictionary) -> Dictionary:
	var total_rejected := 0
	var total_cap_stalls := 0
	for row in rows:
		total_rejected += int(row["rejected"])
		total_cap_stalls += int(row["cap_stall"])

	var pairings: Array = []
	var gates_ok := true
	for pair: Array in DIFFICULTY_PAIRINGS:
		var low := String(pair[0])
		var high := String(pair[1])
		var per_map: Dictionary = {}
		for name in DIFFICULTY_MAPS:
			per_map[name] = {"wins": 0, "played": 0}
		var wins := 0
		var played := 0
		for row in rows:
			if row["low_tier"] != low or row["high_tier"] != high:
				continue
			played += 1
			wins += int(row["high_won"])
			var bucket: Dictionary = per_map[row["map"]]
			bucket["played"] += 1
			bucket["wins"] += int(row["high_won"])
		var rate := 100.0 * float(wins) / maxf(1.0, float(played))
		gates_ok = gates_ok and rate >= DIFFICULTY_GATE_PCT
		var maps: Array = []
		for name in DIFFICULTY_MAPS:
			var bucket: Dictionary = per_map[name]
			var played_here := maxf(1.0, float(bucket["played"]))
			var per_map_row := {
				"map": name,
				"played": bucket["played"],
				"wins": bucket["wins"],
				"win_rate": 100.0 * float(bucket["wins"]) / played_here,
			}
			maps.append(per_map_row)
		var pairing_row := {
			"low": low,
			"high": high,
			"played": played,
			"wins": wins,
			"win_rate": rate,
			"gate_ok": rate >= DIFFICULTY_GATE_PCT,
			"maps": maps,
		}
		pairings.append(pairing_row)

	# A rejected command or an unresolvable match means planner and rules
	# disagree — a real bug, and it fails this run as it fails the commander one.
	return {
		"matches": rows.size(),
		"gate_pct": DIFFICULTY_GATE_PCT,
		"total_rejected": total_rejected,
		"total_cap_stalls": total_cap_stalls,
		"pairings": pairings,
		"turn_ms": _turn_times(timing),
		"passed": gates_ok and total_rejected == 0 and total_cap_stalls == 0,
	}


## Mean planning milliseconds per turn per tier. R3's budget is "no perceptible
## pause versus today", so Normal is the baseline, not any absolute number.
func _turn_times(timing: Dictionary) -> Array:
	var result: Array = []
	for key: String in timing:
		var stats: Dictionary = timing[key]
		var turns := maxi(1, int(stats["turns"]))
		var row := {
			"tier": key,
			"turns": stats["turns"],
			"mean_ms": float(stats["usec"]) / 1000.0 / float(turns),
		}
		result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"])
	return result


func _write_difficulty_reports(rows: Array[Dictionary], summary: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join(_out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_write_csv(dir.path_join("matches.csv"), rows, DIFFICULTY_CSV_COLUMNS)
	_write_json(dir.path_join("summary.json"), summary)
	print("difficulty: wrote matches.csv and summary.json to %s" % _out_dir)


func _print_difficulty_summary(summary: Dictionary) -> void:
	print("\n=== difficulty ladder ===")
	print(
		(
			"matches %d   rejected %d   cap-stalls %d   gate >= %.0f%%"
			% [
				summary["matches"],
				summary["total_rejected"],
				summary["total_cap_stalls"],
				summary["gate_pct"],
			]
		)
	)
	for pairing: Dictionary in summary["pairings"]:
		print(
			(
				"  %-7s over %-7s  %5.1f%%  (%d/%d)  %s"
				% [
					pairing["high"],
					pairing["low"],
					pairing["win_rate"],
					pairing["wins"],
					pairing["played"],
					"ok" if pairing["gate_ok"] else "FAIL",
				]
			)
		)
		for entry: Dictionary in pairing["maps"]:
			print(
				(
					"      on %-11s %5.1f%%  (%d/%d)"
					% [entry["map"], entry["win_rate"], entry["wins"], entry["played"]]
				)
			)
	print("mean AI planning per turn:")
	for entry: Dictionary in summary["turn_ms"]:
		print("  %-7s %7.1f ms over %d turns" % [entry["tier"], entry["mean_ms"], entry["turns"]])
	if summary["passed"]:
		print("PASS: every higher tier clears the gate.")
	else:
		print("FAIL: tune the tier .tres weights (or zero a misbehaving smart) — not this gate.")
