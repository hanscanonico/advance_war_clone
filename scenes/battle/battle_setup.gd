class_name BattleSetup
extends RefCounted
## Builds the match the battle scene is about to play: which map, which
## commanders, which sides the computer takes, and whether this is a fresh start
## or a resumed save.
##
## Split out of Battle because none of it is *flow*. Battle runs a match; this
## decides which match — from the main menu's MatchConfig and the command-line
## flags that override it, so a headless capture and a menu launch arrive at the
## same board by the same route.
##
## Node-free, like the rest of the logic the scene leans on: it reads autoloads
## and the command line, and hands back plain simulation objects.

const DEFAULT_MAP_PATH := "res://maps/first_steps.txt"
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"


class BuiltMatch:
	var map: MapData
	var game: GameState
	## Teams played by the computer. Blue by default; `--hotseat` clears it.
	var ai_teams: Array[int] = []
	## The tier the computer plays at. Never null — DifficultyDB always answers —
	## and the source of both the AI's profile and the id the save records.
	var difficulty: Difficulty
	## team -> Difficulty, when the sides play at *different* tiers. Only watch
	## mode fills it; a normal match has one computer opponent at one tier, and
	## `difficulty` above is that tier and the one the save records.
	var per_team_difficulty: Dictionary = {}
	## `--watch`: both seats are the computer's and the match came from a Balance
	## Lab spec. The scene prints its result and exits when the match ends, so a
	## watched run can be diffed against the CSV row it was launched from.
	var watching := false
	## Watch mode only: the day after which a match nobody has won is scored on
	## the harness's own tiebreak, so a `day_cap` row can be watched to the same
	## line it was launched from. `--days=`, matching the Lab's flag. Normal play
	## ignores it entirely — a hot-seat or player-vs-AI match has no day limit.
	var days_cap := BalanceMatchEngine.DEFAULT_DAYS


static func build(terrain_db: TerrainDB, unit_db: UnitDB, commander_db: CommanderDB) -> BuiltMatch:
	var result := BuiltMatch.new()
	var chart: DamageChart = load(DAMAGE_CHART_PATH)
	var difficulty_db := DifficultyDB.load_default()
	var args := OS.get_cmdline_user_args()
	var map_path: String = MatchConfig.map_path
	var fog: bool = MatchConfig.fog_enabled
	var picked: Dictionary = MatchConfig.commanders.duplicate()
	var tier: StringName = MatchConfig.difficulty
	var seed_val := -1
	var sides: Dictionary = {}  # team -> BalanceSideSpec, from --red / --blue
	result.ai_teams = MatchConfig.ai_teams.duplicate()
	var watching := "--watch" in args
	for arg in args:
		if arg.begins_with("--map="):
			# Through MapCatalog so a balance fixture resolves by the same name the
			# headless Lab knows it by — a watched match must be the same board its
			# CSV row was played on. A name nothing answers to is said out loud
			# rather than quietly played on the default board: a watched match on
			# the wrong map still prints a result line, and that line is what the
			# replay-fidelity check diffs.
			var wanted := arg.get_slice("=", 1)
			var resolved := MapCatalog.resolve(wanted)
			if resolved == "":
				push_error(
					(
						"battle: unknown map '%s'; playing %s instead. Known: %s"
						% [wanted, map_path, ", ".join(MapCatalog.resolvable_names())]
					)
				)
			else:
				map_path = resolved
		elif arg.begins_with("--days="):
			result.days_cap = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--co="):
			picked = parse_co_flag(arg.get_slice("=", 1))
		elif arg.begins_with("--difficulty="):
			tier = StringName(arg.get_slice("=", 1).strip_edges())
		elif arg.begins_with("--red="):
			sides[GameState.TEAMS[0]] = arg.get_slice("=", 1)
		elif arg.begins_with("--blue="):
			sides[GameState.TEAMS[1]] = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			seed_val = maxi(0, int(arg.get_slice("=", 1)))
	if "--hotseat" in args:
		result.ai_teams = []
	if "--fog" in args:
		fog = true
	if watching:
		# Watch mode (balance plan BS3): both seats are the computer's, each with
		# its own commander and its own tier, and the match RNG is pinned. That is
		# the whole difference from a normal launch — the sim, the planners and
		# the animations are the shipped ones, which is what makes the watched
		# match the same match as its headless row (plan D7).
		result.ai_teams = GameState.TEAMS.duplicate()
		result.watching = true
	_apply_difficulty(result, difficulty_db, tier)
	if MatchConfig.load_save and SaveGame.has_save():
		MatchConfig.load_save = false
		var loaded := SaveGame.load_game(
			terrain_db, unit_db, chart, SaveGame.SAVE_PATH, commander_db
		)
		if loaded != null:
			# A resumed save brings its own map, sides, commanders and tier;
			# nothing the menu last wrote applies to it.
			result.game = loaded.state
			result.ai_teams = loaded.ai_teams
			_apply_difficulty(result, difficulty_db, loaded.difficulty)
			result.map = result.game.map
			return result
	result.map = MapData.load_from_file(map_path, terrain_db)
	if result.map == null and map_path != DEFAULT_MAP_PATH:
		push_error("failed to load %s; falling back to %s" % [map_path, DEFAULT_MAP_PATH])
		map_path = DEFAULT_MAP_PATH
		result.map = MapData.load_from_file(map_path, terrain_db)
	assert(result.map != null, "failed to load %s" % map_path)
	# Commanders resolved *before* the state is built, so the opening side's day-1
	# begin_turn runs against its real doctrine (a supply radius, a repair discount)
	# rather than the neutral one it would see if commanders were set afterward.
	var commanders := _resolve_commanders(result, commander_db, difficulty_db, picked, sides)
	result.game = GameState.create(result.map, unit_db, chart, commanders)
	assert(result.game != null, "failed to build game state from %s" % map_path)
	result.game.map_path = map_path
	result.game.fog_enabled = fog
	# A pinned seed is what makes a watched match *the* match rather than another
	# one like it: the AI is lookahead-free and RNG-free, so the seed is the only
	# thing left that could make two runs of one spec diverge.
	if seed_val >= 0:
		result.game.rng.seed = seed_val
	else:
		result.game.rng.randomize()
	return result


## `--co` / MatchConfig ids together with the Balance Lab's `--red=<co>:<tier>` /
## `--blue=<co>:<tier>` grammar, resolved to `team -> CommanderType` before the
## state is built so the opening side's day-1 begin_turn sees its real doctrine.
## Side specs — read through the Lab's own parser so a spec means the same thing
## in the window as in the report — win over `--co` for the same team, as they did
## when both called set_commander in turn; each records its tier so the scene can
## hand that team a planner of its own.
static func _resolve_commanders(
	result: BuiltMatch,
	commander_db: CommanderDB,
	difficulty_db: DifficultyDB,
	picked: Dictionary,
	sides: Dictionary
) -> Dictionary:
	var commanders: Dictionary = {}
	for team: int in picked:
		commanders[team] = commander_db.by_id(picked[team])
	for team: int in sides:
		var spec := BalanceSideSpec.parse(sides[team], commander_db, difficulty_db)
		if spec.error != "":
			push_error("battle: %s" % spec.error)
			continue
		commanders[team] = commander_db.by_id(spec.commander)
		result.per_team_difficulty[team] = difficulty_db.by_id(spec.tier)
	return commanders


## Resolves the tier and makes MatchConfig agree with it, so the id the save
## records and the one a rematch replays are the tier actually being played —
## whether it came from the menu, a `--difficulty=` flag, or the resumed save
## itself. Doing it here means the battle scene never has to carry the tier
## around just to hand it back.
static func _apply_difficulty(result: BuiltMatch, db: DifficultyDB, id: StringName) -> void:
	result.difficulty = db.by_id(id)
	MatchConfig.difficulty = result.difficulty.id


## Writes the match actually running back into MatchConfig, so a rematch replays
## *it* — including one resumed from a save, whose map, sides and commanders the
## menu never saw — rather than whatever the menu last wrote. The mirror of
## build(), and here for the same reason: it is setup, not flow. Difficulty is
## absent on purpose: _apply_difficulty already settled it.
static func remember(game: GameState, ai_teams: Array[int]) -> void:
	MatchConfig.map_path = game.map_path
	MatchConfig.fog_enabled = game.fog_enabled
	MatchConfig.ai_teams = ai_teams.duplicate()
	MatchConfig.commanders = {}
	for team in GameState.TEAMS:
		MatchConfig.commanders[team] = game.commander_of(team).id
	MatchConfig.load_save = false


## `--co=alina_ward,viktor_draeg`: red first, blue second, either side blank for
## no commander. Keeps headless demos and captures able to pick a matchup
## without the menu, exactly as --map and --fog do. Public so it can be tested
## without a scene tree or an autoload.
static func parse_co_flag(value: String) -> Dictionary:
	var picked: Dictionary = {}
	var ids := value.split(",")
	for i in mini(ids.size(), GameState.TEAMS.size()):
		var id := ids[i].strip_edges()
		if id != "":
			picked[GameState.TEAMS[i]] = StringName(id)
	return picked
