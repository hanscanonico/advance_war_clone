class_name SaveGame
extends RefCounted
## JSON (de)serialization of a running match to user:// storage.
## The save stores sim state plus the match setup (AI sides); the map itself
## is reloaded from its res:// file by path.

const SAVE_PATH := "user://save.json"
const VERSION := 1

## Keys every save envelope must carry; optional ones (fog, winner,
## capture_progress, carrier, ai_teams) fall back to defaults instead.
const REQUIRED_KEYS: Array = [
	"map_path", "day", "current_team", "funds", "rng_state", "owners", "units",
]
const REQUIRED_UNIT_KEYS: Array = ["type", "team", "x", "y", "hp", "fuel", "ammo", "acted"]
const REQUIRED_OWNER_KEYS: Array = ["x", "y", "team"]
const REQUIRED_PROGRESS_KEYS: Array = ["x", "y", "points"]


class LoadedMatch:
	var state: GameState
	var ai_teams: Array[int] = []


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


static func save(state: GameState, ai_teams: Array[int], path: String = SAVE_PATH) -> bool:
	var units: Array = []
	for unit in state.units:
		units.append({
			"type": String(unit.type.id),
			"team": unit.team,
			"x": unit.cell.x,
			"y": unit.cell.y,
			"hp": unit.hp,
			"fuel": unit.fuel,
			"ammo": unit.ammo,
			"acted": unit.acted,
			"carrier": state.units.find(unit.carrier),  # -1 when on the board
		})
	var owners: Array = []
	for cell: Vector2i in state.property_owners:
		owners.append({"x": cell.x, "y": cell.y, "team": state.property_owners[cell]})
	var progress: Array = []
	for cell: Vector2i in state.capture_progress:
		progress.append({"x": cell.x, "y": cell.y, "points": state.capture_progress[cell]})
	var data := {
		"version": VERSION,
		"map_path": state.map_path,
		"fog": state.fog_enabled,
		"day": state.day,
		"current_team": state.current_team,
		"winner": state.winner,
		"funds": {"1": state.funds[1], "2": state.funds[2]},
		"rng_state": str(state.rng.state),  # int64 as string: JSON numbers are lossy
		"ai_teams": ai_teams,
		"owners": owners,
		"capture_progress": progress,
		"units": units,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


## Returns null (with a pushed error) when the file is missing or invalid.
static func load_game(
	terrain_db: TerrainDB, unit_db: UnitDB, damage_chart: DamageChart,
	path: String = SAVE_PATH
) -> LoadedMatch:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveGame: cannot read %s" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_error("SaveGame: %s is not a valid save" % path)
		return null
	var data: Dictionary = json.data
	if int(data.get("version", -1)) != VERSION:
		push_error("SaveGame: unsupported save version")
		return null
	if not _has_keys(data, REQUIRED_KEYS, "save"):
		return null
	if not _valid_entries(data["owners"], REQUIRED_OWNER_KEYS, "owner"):
		return null
	var progress: Variant = data.get("capture_progress", [])
	if not _valid_entries(progress, REQUIRED_PROGRESS_KEYS, "capture progress"):
		return null
	if not _valid_entries(data["units"], REQUIRED_UNIT_KEYS, "unit"):
		return null
	var funds: Variant = data["funds"]
	if not (funds is Dictionary):
		push_error("SaveGame: 'funds' is malformed")
		return null
	for team in GameState.TEAMS:
		if not (funds as Dictionary).has(str(team)):
			push_error("SaveGame: save has no funds for team %d" % team)
			return null
	var map := MapData.load_from_file(String(data["map_path"]), terrain_db)
	if map == null:
		return null
	var state := GameState.new()
	state.map = map
	state.map_path = String(data["map_path"])
	state.damage_chart = damage_chart
	state.fog_enabled = bool(data.get("fog", false))
	state.day = int(data["day"])
	state.current_team = int(data["current_team"])
	state.winner = int(data.get("winner", 0))
	for team in GameState.TEAMS:
		state.funds[team] = int((funds as Dictionary)[str(team)])
	state.rng.state = int(String(data["rng_state"]))
	for entry in data["owners"]:
		state.property_owners[Vector2i(int(entry.x), int(entry.y))] = int(entry.team)
	for entry in progress:
		state.capture_progress[Vector2i(int(entry.x), int(entry.y))] = int(entry.points)
	var carrier_indices: Array[int] = []
	for entry in data["units"]:
		var type := unit_db.by_id(StringName(String(entry.type)))
		if type == null:
			push_error("SaveGame: unknown unit type '%s'" % entry.type)
			return null
		var unit := Unit.create(type, int(entry.team), Vector2i(int(entry.x), int(entry.y)))
		unit.hp = int(entry.hp)
		unit.fuel = int(entry.fuel)
		unit.ammo = int(entry.ammo)
		unit.acted = bool(entry.acted)
		state.units.append(unit)
		carrier_indices.append(int(entry.get("carrier", -1)))
	for i in state.units.size():
		var index := carrier_indices[i]
		if index >= 0 and index < state.units.size():
			state.units[i].carrier = state.units[index]
	var result := LoadedMatch.new()
	result.state = state
	var teams: Variant = data.get("ai_teams", [])
	if teams is Array:
		for team in teams as Array:
			result.ai_teams.append(int(team))
	return result


## True when `data` carries every key; pushes an error naming the first gap.
static func _has_keys(data: Dictionary, keys: Array, what: String) -> bool:
	for key in keys:
		if not data.has(key):
			push_error("SaveGame: %s is missing '%s'" % [what, key])
			return false
	return true


## True when `value` is an array of dictionaries that all carry `keys`.
static func _valid_entries(value: Variant, keys: Array, what: String) -> bool:
	if not (value is Array):
		push_error("SaveGame: '%s' list is malformed" % what)
		return false
	for entry: Variant in value as Array:
		if not (entry is Dictionary):
			push_error("SaveGame: %s entry is malformed" % what)
			return false
		if not _has_keys(entry as Dictionary, keys, "%s entry" % what):
			return false
	return true
