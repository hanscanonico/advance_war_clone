extends SceneTree
## The Balance Lab: two independent AIs on any shipped board, each side carrying
## any commander at any difficulty tier, over N seeded matches with both seats
## swapped — recording not just who won but a turn-by-turn timeline of how.
##
## It is the general instrument the two shipped presets are special cases of.
## `make commander-balance` and `make difficulty-check` still answer the two
## standing documents' exact questions with their exact flags; this answers
## everything in between — "why does Gideon crush Cass on ironworks?", "is this
## board fair?", "is Difficult worth a commander handicap?" — and any matchup it
## can score it can also *show*, because the same spec and seed boot the real
## battle scene with both sides AI-driven (`make balance-watch`).
##
## Usage (headless; see `make balance-sim`):
##   Godot --headless --path . -s res://tools/run_balance_sim.gd -- [flags]
##     --map=ironworks           any shipped map, or a balance fixture
##                               (clash/ridge/combined); default first_steps
##     --red=<co>:<tier>         a side spec — commander id or `none`, tier
##     --blue=<co>:<tier>        easy/normal/hard. Default none:normal.
##     --seeds=10                paired seed count (default 4)
##     --days=20                 day cap before the match is scored on points
##     --sweep=commanders        one free axis per run (plan D5):
##     --sweep=maps                commanders — every commander vs --blue at --tier
##     --sweep=tiers              maps       — --red vs --blue on every shipped board
##                                tiers      — the adjacent-tier ladder, both sides
##                                             carrying --commander
##     --tier=normal             the tier both sides play at, for --sweep=commanders
##     --commander=alina_ward    the doctrine both sides carry, for --sweep=tiers
##     --no-commands             skip commands.jsonl (a big sweep's is large)
##     --out=reports/...         output directory (default reports/balance_sim/<run>)
##
## Writes four files, all gitignored with the rest of reports/:
##   matches.csv   — one row per match
##   timeline.csv  — one row per side per played turn, keyed by match_id
##   commands.jsonl— one line per applied command (plan Q3)
##   summary.json  — the aggregates and flags
##   report.html   — the same numbers, drawn (plan BS4)
##
## Determinism: same map + seed + side specs => byte-identical rows, because the
## RNG is seeded, the AI is lookahead-free and RNG-free, and nothing here reads
## the clock. `planning_ms` in the timeline is the one exception and is excluded
## from the determinism test for exactly that reason.

const DEFAULT_SEEDS := 4
const SEED_BASE := 1000
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"
const DEFAULT_OUT_ROOT := "reports/balance_sim"
const DEFAULT_MAP := "first_steps"

## Adjacent tiers only, matching the difficulty ladder: each pairing asks whether
## one step up is a real step. Higher tier second.
const TIER_LADDER: Array = [[&"easy", &"normal"], [&"normal", &"hard"]]

const MATCH_COLUMNS: Array[String] = [
	"match_id",
	"sweep_axis",
	"sweep_value",
	"map",
	"seed",
	"seat",
	"mirror",
	"naval",
	"red_commander",
	"red_tier",
	"blue_commander",
	"blue_tier",
	"subject_side",
	"subject_won",
	"winner",
	"termination",
	"day_ended",
	"commands",
	"rejected",
	"cap_stall",
	"turn_cap_hits",
	"red_units",
	"blue_units",
	"red_props",
	"blue_props",
	"red_funds",
	"blue_funds",
	"red_army_value",
	"blue_army_value",
	"red_powers",
	"blue_powers",
]

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB
var difficulty_db: DifficultyDB

var _map_name := DEFAULT_MAP
var _red_text := BalanceSideSpec.DEFAULT_TEXT
var _blue_text := BalanceSideSpec.DEFAULT_TEXT
var _sweep := ""
var _sweep_tier := Difficulty.DEFAULT_ID
var _sweep_commander := CommanderType.NEUTRAL_ID
var _seed_count := DEFAULT_SEEDS
## -1 unless `--seed=` pinned one, in which case the run is that single seed —
## the same one a watch-mode launch replays.
var _pinned_seed := -1
var _days_cap := BalanceMatchEngine.DEFAULT_DAYS
var _out_dir := ""
var _log_commands := true

var _maps: Dictionary = {}  # name -> MapData, loaded once and shared


## One match to play: which board, which seat holds which spec, and what swept
## value the row belongs to.
class Job:
	var value := ""
	var map_name := ""
	var red: BalanceSideSpec
	var blue: BalanceSideSpec
	## The spec the swept value names, whose side-normalized win rate is the
	## question the run is asking. Its seat alternates with `seat`.
	var subject_side := "red"
	var seat := 0
	var seed_val := 0
	var mirror := false


func _init() -> void:
	_load_dbs()
	if not _parse_args():
		quit(2)
		return
	var jobs := _build_jobs()
	if jobs.is_empty():
		push_error("balance-sim: nothing to play")
		quit(2)
		return
	var recorder := BalanceMatchRecorder.new(_log_commands)
	var matches := _run(jobs, recorder)
	if matches.is_empty():
		quit(2)
		return
	var summary := BalanceRunSummary.build(_config(), matches, recorder.rows())
	_write(matches, recorder, summary)
	_print_summary(summary)
	var totals: Dictionary = summary["totals"]
	quit(0 if totals["invariants_clean"] else 1)


# --- setup -------------------------------------------------------------------


func _load_dbs() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load(DAMAGE_CHART_PATH)
	commander_db = CommanderDB.load_default()
	difficulty_db = DifficultyDB.load_default()


## Returns false on any bad flag rather than quietly playing something else: a
## mistyped commander would otherwise measure a neutral matchup and the run would
## look fine.
func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map_name = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--red="):
			_red_text = arg.get_slice("=", 1)
		elif arg.begins_with("--blue="):
			_blue_text = arg.get_slice("=", 1)
		elif arg.begins_with("--sweep="):
			_sweep = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--tier="):
			_sweep_tier = StringName(arg.get_slice("=", 1).strip_edges())
		elif arg.begins_with("--commander="):
			_sweep_commander = StringName(arg.get_slice("=", 1).strip_edges())
		elif arg.begins_with("--seeds="):
			_seed_count = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seed="):
			# Watch mode's spelling, accepted here too: a suspicious row's flags
			# copied verbatim off the CSV replay that one match headlessly.
			_pinned_seed = maxi(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--days="):
			_days_cap = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1).strip_edges()
		elif arg == "--no-commands":
			_log_commands = false
		else:
			push_error("balance-sim: unknown flag '%s'" % arg)
			return false
	if _sweep != "" and _sweep not in ["commanders", "maps", "tiers"]:
		push_error("balance-sim: --sweep must be commanders, maps or tiers (got '%s')" % _sweep)
		return false
	if not difficulty_db.has(_sweep_tier):
		push_error("balance-sim: unknown tier '%s'" % _sweep_tier)
		return false
	if not commander_db.has(_sweep_commander):
		push_error("balance-sim: unknown commander '%s'" % _sweep_commander)
		return false
	if _sweep != "maps" and _map_of(_map_name) == null:
		return false
	return _spec(_red_text) != null and _spec(_blue_text) != null


func _spec(text: String) -> BalanceSideSpec:
	var spec := BalanceSideSpec.parse(text, commander_db, difficulty_db)
	if spec.error != "":
		push_error("balance-sim: %s" % spec.error)
		return null
	return spec


## A board by name, read once and shared across every match played on it. Safe to
## share: GameState.create copies the ownership it needs and never writes back.
func _map_of(name: String) -> MapData:
	if _maps.has(name):
		var cached: MapData = _maps[name]
		return cached
	var path := MapCatalog.resolve(name)
	if path == "":
		push_error(
			(
				"balance-sim: unknown map '%s'. Known: %s"
				% [name, ", ".join(MapCatalog.resolvable_names())]
			)
		)
		return null
	var map := MapData.load_from_file(path, terrain_db)
	if map == null:
		return null
	_maps[name] = map
	return map


# --- the run ------------------------------------------------------------------


## Expands the run's one free axis (plan D5) into the flat list of matches to
## play. Every job is a fully-pinned matchup, so the loop below has no branching
## left in it and a sweep is just a longer list.
func _build_jobs() -> Array[Job]:
	var jobs: Array[Job] = []
	var red := _spec(_red_text)
	var blue := _spec(_blue_text)
	match _sweep:
		"commanders":
			# Every commander against the pinned opponent, both at --tier: a
			# power-level reading of the roster on one board.
			for co in commander_db.all():
				var subject := BalanceSideSpec.new()
				subject.commander = co.id
				subject.tier = _sweep_tier
				var against := BalanceSideSpec.new()
				against.commander = blue.commander
				against.tier = _sweep_tier
				jobs.append_array(_pair(String(co.id), _map_name, subject, against))
		"maps":
			for path in MapCatalog.paths():
				var name := path.get_file().trim_suffix(".txt")
				if _map_of(name) == null:
					continue
				jobs.append_array(_pair(name, name, red, blue))
		"tiers":
			for pairing: Array in TIER_LADDER:
				var high := BalanceSideSpec.new()
				high.commander = _sweep_commander
				high.tier = pairing[1]
				var low := BalanceSideSpec.new()
				low.commander = _sweep_commander
				low.tier = pairing[0]
				jobs.append_array(
					_pair("%s over %s" % [pairing[1], pairing[0]], _map_name, high, low)
				)
		_:
			jobs.append_array(_pair("%s vs %s" % [red.slug(), blue.slug()], _map_name, red, blue))
	return jobs


## Every seed of one matchup, played from **both seats** so a first-move edge
## cancels out of the win rate and is reported separately as bias.
##
## Two identical specs are the exception: swapping the seats of a mirror replays
## the identical match, seed and all, so it is played once. That is not a lost
## measurement — with both sides the same, the red win rate *is* the seat's
## worth, which is exactly what a mirror sweep is for.
func _pair(
	value: String, map_name: String, red: BalanceSideSpec, blue: BalanceSideSpec
) -> Array[Job]:
	var jobs: Array[Job] = []
	var mirror := red.text() == blue.text()
	for s in 1 if _pinned_seed >= 0 else _seed_count:
		# Paired seeds: both seatings of a matchup meet on identical luck, and the
		# seed varies by board so two maps in one sweep are not correlated.
		var seed_val := _pinned_seed if _pinned_seed >= 0 else SEED_BASE + s + hash(map_name) % 1000
		for seat in 1 if mirror else 2:
			var job := Job.new()
			job.value = value
			job.map_name = map_name
			job.seed_val = seed_val
			job.seat = seat
			job.mirror = mirror
			job.red = red if seat == 0 else blue
			job.blue = blue if seat == 0 else red
			job.subject_side = "red" if seat == 0 else "blue"
			jobs.append(job)
	return jobs


func _run(jobs: Array[Job], recorder: BalanceMatchRecorder) -> Array[Dictionary]:
	print(
		(
			"balance-sim: %s, %d seeds, day cap %d -> %d matches"
			% [_axis_label(), _seed_count, _days_cap, jobs.size()]
		)
	)
	var rows: Array[Dictionary] = []
	var done := 0
	for job in jobs:
		var row := _play(job, recorder)
		if row.is_empty():
			return []
		rows.append(row)
		done += 1
		if done % 50 == 0:
			print("balance-sim: %d / %d matches" % [done, jobs.size()])
	return rows


func _play(job: Job, recorder: BalanceMatchRecorder) -> Dictionary:
	var map := _map_of(job.map_name)
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = map
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = job.seed_val
	setup.days_cap = _days_cap
	setup.match_id = (
		"%s#%s_vs_%s#s%d" % [job.map_name, job.red.slug(), job.blue.slug(), job.seed_val]
	)
	setup.commanders = {
		1: commander_db.by_id(job.red.commander),
		2: commander_db.by_id(job.blue.commander),
	}
	setup.tiers = {1: job.red.tier, 2: job.blue.tier}
	# One planner per side, each with its own profile and its own per-turn threat
	# map. The tier's whole effect is which profile plans the moves — no economy,
	# vision, damage or luck differs at any tier (difficulty plan D2/D3).
	setup.planners = {
		1: AIController.new(unit_db, difficulty_db.by_id(job.red.tier).profile()),
		2: AIController.new(unit_db, difficulty_db.by_id(job.blue.tier).profile()),
	}
	var outcome := BalanceMatchEngine.play(setup, recorder)
	if outcome.state == null:
		push_error("balance-sim: could not build a match on '%s'" % job.map_name)
		return {}
	var state := outcome.state
	# The timeline is checked against the board it describes on every match, not
	# once at the end: a miscount is a red build, never a quiet lie in the data.
	var problem := recorder.reconcile(state, outcome.starting_units)
	if problem != "":
		push_error(
			"balance-sim: telemetry does not reconcile on %s: %s" % [setup.match_id, problem]
		)
		return {}
	var subject_team := 1 if job.subject_side == "red" else 2
	return {
		"match_id": setup.match_id,
		"sweep_axis": _sweep if _sweep != "" else "matchup",
		"sweep_value": job.value,
		"map": job.map_name,
		"seed": job.seed_val,
		"seat": job.seat,
		"mirror": 1 if job.mirror else 0,
		"naval": 1 if _is_naval(map) else 0,
		"red_commander": String(job.red.commander),
		"red_tier": String(job.red.tier),
		"blue_commander": String(job.blue.commander),
		"blue_tier": String(job.blue.tier),
		"subject_side": job.subject_side,
		"subject_won": 1 if outcome.winner == subject_team else 0,
		"winner": outcome.winner,
		"termination": outcome.termination,
		"day_ended": outcome.day_ended,
		"commands": outcome.commands,
		"rejected": outcome.rejected,
		"cap_stall": 1 if outcome.cap_stall else 0,
		"turn_cap_hits": outcome.turn_cap_hits,
		"red_units": state.units_of(1).size(),
		"blue_units": state.units_of(2).size(),
		"red_props": state.properties_of(1).size(),
		"blue_props": state.properties_of(2).size(),
		"red_funds": int(state.funds.get(1, 0)),
		"blue_funds": int(state.funds.get(2, 0)),
		"red_army_value": _army_value(state, 1),
		"blue_army_value": _army_value(state, 2),
		"red_powers": outcome.powers[1],
		"blue_powers": outcome.powers[2],
	}


static func _army_value(state: GameState, team: int) -> int:
	var total := 0
	for unit in state.units_of(team):
		total += unit.type.cost * unit.hp / 100
	return total


## A board where the naval domain is actually in play — one that can *build* a
## hull, not merely one with water on it. Almost every shipped map is framed by a
## decorative sea border, so "has a sea tile" would annotate the whole roster and
## the flag would mean nothing; a port is what puts a fleet, and therefore the
## ferry problem, on the board.
##
## Read off TerrainType.builds rather than a terrain id or a map name, like every
## other question about what a property does — so a board that gains a port is
## annotated the day it does, and only then.
##
## Plan R1: the AI never plans a ferry, so what the Lab measures on one of these
## is what the AI can express there, not what the board is worth to a human.
func _is_naval(map: MapData) -> bool:
	for y in map.height:
		for x in map.width:
			var builds := map.terrain_at(Vector2i(x, y)).builds
			if TerrainType.SHIP in builds or TerrainType.LANDER in builds:
				return true
	return false


# --- output ------------------------------------------------------------------


func _config() -> Dictionary:
	return {
		"axis": _sweep if _sweep != "" else "matchup",
		"label": _axis_label(),
		"map": "(swept)" if _sweep == "maps" else _map_name,
		"red": _red_text,
		"blue": _blue_text,
		"seeds": _seed_count,
		"days_cap": _days_cap,
		"command_log": _log_commands,
	}


func _axis_label() -> String:
	match _sweep:
		"commanders":
			return "every commander at %s on %s" % [_sweep_tier, _map_name]
		"maps":
			return "%s vs %s on every shipped board" % [_red_text, _blue_text]
		"tiers":
			return "the tier ladder on %s, both sides %s" % [_map_name, _sweep_commander]
	return "%s vs %s on %s" % [_red_text, _blue_text, _map_name]


## Derived from the spec, never from a clock — so rerunning the same batch
## overwrites its own directory instead of littering a new one, and two runs of
## the same question are diffable file for file.
func _run_name() -> String:
	var parts: Array[String] = []
	parts.append(_sweep if _sweep != "" else "matchup")
	parts.append("(swept)" if _sweep == "maps" else _map_name)
	if _sweep != "commanders":
		parts.append("%s_vs_%s" % [_red_text, _blue_text])
	if _sweep == "commanders":
		parts.append(String(_sweep_tier))
	if _sweep == "tiers":
		parts.append(String(_sweep_commander))
	parts.append("s%d" % _seed_count)
	return "_".join(parts).replace(":", "-").replace(" ", "").replace("(", "").replace(")", "")


func _write(
	matches: Array[Dictionary], recorder: BalanceMatchRecorder, summary: Dictionary
) -> void:
	var out := _out_dir if _out_dir != "" else DEFAULT_OUT_ROOT.path_join(_run_name())
	var dir := BalanceReportWriter.prepare_dir(out)
	BalanceReportWriter.write_csv(dir.path_join("matches.csv"), matches, MATCH_COLUMNS)
	BalanceReportWriter.write_csv(
		dir.path_join("timeline.csv"), recorder.rows(), BalanceMatchRecorder.TIMELINE_COLUMNS
	)
	BalanceReportWriter.write_json(dir.path_join("summary.json"), summary)
	if _log_commands:
		BalanceReportWriter.write_jsonl(dir.path_join("commands.jsonl"), recorder.command_log())
	BalanceReportWriter.write_text(
		dir.path_join("report.html"), BalanceReportHtml.render(summary, recorder.rows())
	)
	print(
		(
			"balance-sim: wrote %d match rows, %d timeline rows%s to %s"
			% [
				matches.size(),
				recorder.rows().size(),
				(
					" and %d command log lines" % recorder.command_log().size()
					if _log_commands
					else ""
				),
				out,
			]
		)
	)
	print("balance-sim: open %s/report.html to read it" % out)


func _print_summary(summary: Dictionary) -> void:
	var totals: Dictionary = summary["totals"]
	var bias: Dictionary = summary["bias"]["overall"]
	print("\n=== balance lab: %s ===" % summary["run"]["label"])
	print(
		(
			"matches %d   decisive %d   draws %d   rejected %d   cap-stalls %d"
			% [
				totals["matches"],
				totals["decisive"],
				totals["draws"],
				totals["total_rejected"],
				totals["total_cap_stalls"],
			]
		)
	)
	print(
		(
			"first-seat bias %+.1f pp (%s, threshold +-%.0f)"
			% [
				bias["bias_pp"],
				"ok" if bias["ok"] else "REVIEW",
				BalanceRunSummary.MAX_SIDE_BIAS_PP,
			]
		)
	)
	print(
		(
			"  %-26s %6s %5s  %-6s %-11s %8s %6s"
			% ["value", "win%", "n", "band", "confidence", "kills/1k", "exch."]
		)
	)
	for entry: Dictionary in summary["values"]:
		var economy: Dictionary = entry["economy"]
		print(
			(
				"  %-26s %6.1f %5d  %-6s %-11s %8.0f %6s"
				% [
					entry["value"],
					entry["win_rate"],
					entry["matches"],
					entry["flag"],
					entry["confidence"],
					economy["killed_per_1000_spent"],
					BalanceReportHtml.ratio(economy["exchange_ratio"]),
				]
			)
		)
	if summary["bias"]["per_map"].size() > 1:
		print("per-board first-seat bias:")
		for entry: Dictionary in summary["bias"]["per_map"]:
			print(
				(
					"  %-14s %+6.1f pp  (%d decisive)%s"
					% [
						entry["map"],
						entry["bias_pp"],
						entry["decisive"],
						"  [naval: AI-bounded]" if entry["naval_bounded"] else "",
					]
				)
			)
	for note: String in summary["notes"]:
		print("note: %s" % note)
	if totals["invariants_clean"]:
		print("hard invariants clean (0 rejected, 0 cap stalls). Band flags are review triggers.")
	else:
		print("FAIL: rejected commands or cap stalls — the AI and the rules disagree.")
