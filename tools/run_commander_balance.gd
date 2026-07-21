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
##     --scenarios=clash,ridge                subset (default: both)
##     --seeds=4                              paired seed count (default: 4)
##     --neutral                              add each commander vs No Commander
##     --days=20                              day cap before a match is a draw
##     --out=reports/commander_balance        output directory (default shown)
##
## The full batch (no flags) is 12x12 ordered pairs x 2 scenarios x 4 seeds =
## 1,152 matches — an explicit release task, deliberately out of `make test`.
## A focused `--commanders`/`--scenarios`/`--seeds` run is the fast iteration loop.

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

## Two 180-degree rotationally-symmetric boards (see _assert_symmetric), so
## neither side gets a terrain or income edge and a first-side bias in the
## results is the doctrines' doing, not the map's.
##
## clash: open and decisive — both armies in reach on day one, so games resolve
## rather than stall into day-cap draws. ridge: the same fairness with more
## terrain between the lines (woods, mountains, four contested cities).
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

var _commander_ids: Array[StringName] = []
var _scenario_names: Array[String] = []
var _seed_count := DEFAULT_SEEDS
var _days_cap := DEFAULT_DAYS
var _include_neutral := false
var _out_dir := "reports/commander_balance"


func _init() -> void:
	_load_dbs()
	_parse_args()
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
	var map := MapData.parse(SCENARIOS[name], terrain_db)
	var state := GameState.create(map, unit_db, chart)
	var w := map.width
	var h := map.height
	for y in h:
		for x in w:
			var a := Vector2i(x, y)
			var b := Vector2i(w - 1 - x, h - 1 - y)
			if map.terrain_at(a).id != map.terrain_at(b).id:
				return _fatal("scenario '%s' terrain not symmetric at %s vs %s" % [name, a, b])
			if state.owner_at(a) != _swap_team(state.owner_at(b)):
				return _fatal("scenario '%s' ownership not mirror-symmetric at %s" % [name, a])
	for unit in state.units:
		var mirror := Vector2i(w - 1 - unit.cell.x, h - 1 - unit.cell.y)
		var twin := state.unit_at(mirror)
		if twin == null or twin.team != _swap_team(unit.team) or twin.type.id != unit.type.id:
			return _fatal(
				"scenario '%s' unit %s at %s has no mirror" % [name, unit.type.id, unit.cell]
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
	_write_csv(dir.path_join("matches.csv"), rows)
	_write_json(dir.path_join("summary.json"), summary)
	print("balance: wrote matches.csv and summary.json to %s" % _out_dir)


func _write_csv(path: String, rows: Array[Dictionary]) -> void:
	var lines: Array[String] = [",".join(CSV_COLUMNS)]
	for row in rows:
		var cells: Array[String] = []
		for column in CSV_COLUMNS:
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
