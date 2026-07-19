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


static func build(terrain_db: TerrainDB, unit_db: UnitDB, commander_db: CommanderDB) -> BuiltMatch:
	var result := BuiltMatch.new()
	var chart: DamageChart = load(DAMAGE_CHART_PATH)
	var args := OS.get_cmdline_user_args()
	var map_path: String = MatchConfig.map_path
	var fog: bool = MatchConfig.fog_enabled
	var picked: Dictionary = MatchConfig.commanders.duplicate()
	result.ai_teams = MatchConfig.ai_teams.duplicate()
	for arg in args:
		if arg.begins_with("--map="):
			map_path = "res://maps/%s.txt" % arg.get_slice("=", 1)
		elif arg.begins_with("--co="):
			picked = parse_co_flag(arg.get_slice("=", 1))
	if "--hotseat" in args:
		result.ai_teams = []
	if "--fog" in args:
		fog = true
	if MatchConfig.load_save and SaveGame.has_save():
		MatchConfig.load_save = false
		var loaded := SaveGame.load_game(
			terrain_db, unit_db, chart, SaveGame.SAVE_PATH, commander_db
		)
		if loaded != null:
			# A resumed save brings its own map, sides and commanders; nothing the
			# menu last wrote applies to it.
			result.game = loaded.state
			result.ai_teams = loaded.ai_teams
			result.map = result.game.map
			return result
	result.map = MapData.load_from_file(map_path, terrain_db)
	if result.map == null and map_path != DEFAULT_MAP_PATH:
		push_error("failed to load %s; falling back to %s" % [map_path, DEFAULT_MAP_PATH])
		map_path = DEFAULT_MAP_PATH
		result.map = MapData.load_from_file(map_path, terrain_db)
	assert(result.map != null, "failed to load %s" % map_path)
	result.game = GameState.create(result.map, unit_db, chart)
	assert(result.game != null, "failed to build game state from %s" % map_path)
	result.game.map_path = map_path
	result.game.fog_enabled = fog
	result.game.rng.randomize()
	for team: int in picked:
		result.game.set_commander(team, commander_db.by_id(picked[team]))
	return result


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
