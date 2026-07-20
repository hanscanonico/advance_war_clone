class_name SaveCodec
extends RefCounted
## Translation between a running match and the version-1 save dictionary.
##
## Pure: no filesystem, no JSON text, no `user://`. SaveGame owns storage and
## hands this a Dictionary that is already parsed. Keeping the two apart means
## a format change or a validation rule can be tested on a literal dictionary,
## without a file on disk — and a storage failure is never mistaken for a
## malformed save.
##
## Version 2 adds the commander block: which general each side is playing, how
## much charge their meter holds, and whether their Command Power is up. It is
## purely additive, so version 1 is still read rather than rejected — a save
## with no commander block loads with both sides neutral, which is exactly the
## match a version-1 save recorded. New saves are always written at version 2.
##
## When a format arrives that *cannot* be read this way, it gets its own
## encode/decode pair here and SaveGame keeps choosing between them; the facade
## and its callers do not change.

const VERSION := 2
## Every version this codec can still read, oldest first.
const READABLE_VERSIONS: Array[int] = [1, 2]

## Keys every save envelope must carry; optional ones (fog, winner,
## capture_progress, carrier, ai_teams, commanders) fall back to defaults.
const REQUIRED_KEYS: Array = [
	"map_path",
	"day",
	"current_team",
	"funds",
	"rng_state",
	"owners",
	"units",
]
const REQUIRED_UNIT_KEYS: Array = ["type", "team", "x", "y", "hp", "fuel", "ammo", "acted"]
const REQUIRED_OWNER_KEYS: Array = ["x", "y", "team"]
const REQUIRED_PROGRESS_KEYS: Array = ["x", "y", "points"]

## A unit standing on the board rather than riding in something.
const NO_CARRIER := -1


class LoadedMatch:
	var state: GameState
	var ai_teams: Array[int] = []


## The whole match as a plain Dictionary: sim state plus the match setup (AI
## sides). The map itself is stored by path and reloaded from res:// on the way
## back in, so saves stay small and follow map edits.
static func encode(state: GameState, ai_teams: Array[int]) -> Dictionary:
	var units: Array = []
	for unit in state.units:
		(
			units
			. append(
				{
					"type": String(unit.type.id),
					"team": unit.team,
					"x": unit.cell.x,
					"y": unit.cell.y,
					"hp": unit.hp,
					"fuel": unit.fuel,
					"ammo": unit.ammo,
					"acted": unit.acted,
					"carrier": state.units.find(unit.carrier),  # -1 when on the board
				}
			)
		)
	var owners: Array = []
	for cell: Vector2i in state.property_owners:
		owners.append({"x": cell.x, "y": cell.y, "team": state.property_owners[cell]})
	var progress: Array = []
	for cell: Vector2i in state.capture_progress:
		progress.append({"x": cell.x, "y": cell.y, "points": state.capture_progress[cell]})
	var commanders: Dictionary = {}
	for team in GameState.TEAMS:
		var co_state := state.commander_state(team)
		commanders[str(team)] = {
			"id": String(co_state.type.id),
			"charge": co_state.charge,
			"active": co_state.power_active,
		}
	return {
		"version": VERSION,
		"map_path": state.map_path,
		"fog": state.fog_enabled,
		"day": state.day,
		"current_team": state.current_team,
		"winner": state.winner,
		"funds": {"1": state.funds[1], "2": state.funds[2]},
		"rng_state": str(state.rng.state),  # int64 as string: JSON numbers are lossy
		"ai_teams": ai_teams,
		"commanders": commanders,
		"owners": owners,
		"capture_progress": progress,
		"units": units,
	}


## Rebuilds a match from a parsed save. Returns null (with a pushed error
## naming the problem) when the dictionary is not a save this codec can read.
##
## `commander_db` is optional so callers that have no commanders to resolve —
## most tests — need not mention one. Left out, only the neutral commander is
## known, which is also what every id that is not in the database resolves to.
static func decode(
	data: Dictionary,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	damage_chart: DamageChart,
	commander_db: CommanderDB = null
) -> LoadedMatch:
	var error := validate(data)
	if error != "":
		push_error("SaveCodec: %s" % error)
		return null
	var map := MapData.load_from_file(String(data["map_path"]), terrain_db)
	if map == null:
		return null  # MapData already reported why

	var state := GameState.new()
	state.map = map
	state.map_path = String(data["map_path"])
	state.damage_chart = damage_chart
	state.fog_enabled = bool(data.get("fog", false))
	state.day = int(data["day"])
	state.current_team = int(data["current_team"])
	state.winner = int(data.get("winner", 0))
	var funds: Dictionary = data["funds"]
	for team in GameState.TEAMS:
		state.funds[team] = int(funds[str(team)])
	state.rng.state = int(String(data["rng_state"]))
	for entry in data["owners"]:
		state.property_owners[Vector2i(int(entry.x), int(entry.y))] = int(entry.team)
	for entry in data.get("capture_progress", []):
		state.capture_progress[Vector2i(int(entry.x), int(entry.y))] = int(entry.points)
	_decode_commanders(state, data, commander_db)

	var carrier_indices: Array[int] = []
	for entry in data["units"]:
		var type := unit_db.by_id(StringName(String(entry.type)))
		if type == null:
			push_error("SaveCodec: unknown unit type '%s'" % entry.type)
			return null
		var unit := Unit.create(type, int(entry.team), Vector2i(int(entry.x), int(entry.y)))
		unit.hp = int(entry.hp)
		unit.fuel = int(entry.fuel)
		unit.ammo = int(entry.ammo)
		unit.acted = bool(entry.acted)
		state.units.append(unit)
		carrier_indices.append(int(entry.get("carrier", NO_CARRIER)))

	# Checked only now that the unit count is known, and before anything is
	# wired up, so a bad save never produces a half-linked board.
	var carrier_error := _validate_carriers(carrier_indices)
	if carrier_error != "":
		push_error("SaveCodec: %s" % carrier_error)
		return null
	for i in state.units.size():
		var index := carrier_indices[i]
		if index != NO_CARRIER:
			state.units[i].carrier = state.units[index]

	var result := LoadedMatch.new()
	result.state = state
	var teams: Variant = data.get("ai_teams", [])
	if teams is Array:
		for team in teams as Array:
			result.ai_teams.append(int(team))
	return result


## Restores each side's general, meter and running power. Every step falls back
## to the neutral commander with an empty meter, which is what makes a version-1
## save — where the whole block is missing — load as the no-commander match it
## actually was.
static func _decode_commanders(
	state: GameState, data: Dictionary, commander_db: CommanderDB
) -> void:
	var db := commander_db if commander_db != null else CommanderDB.new()
	var saved: Variant = data.get("commanders", {})
	if not (saved is Dictionary):
		return
	for team in GameState.TEAMS:
		var entry: Variant = (saved as Dictionary).get(str(team), {})
		if not (entry is Dictionary):
			continue
		var record := entry as Dictionary
		state.set_commander(team, db.by_id(StringName(String(record.get("id", "")))))
		var co_state := state.commander_state(team)
		# Through add_charge so a hand-edited meter is still capped at the cost,
		# and so a commander who has since lost their power banks nothing.
		state.add_charge(team, int(record.get("charge", 0)))
		co_state.power_active = bool(record.get("active", false)) and co_state.type.has_power()


## "" when `data` is a well-formed save this codec can read, else the reason it
## is not.
## Structure only — it does not check that the map exists or that unit ids are
## known, because that needs the databases decode is given.
static func validate(data: Dictionary) -> String:
	if not READABLE_VERSIONS.has(int(data.get("version", -1))):
		return "unsupported save version"
	var missing := _missing_key(data, REQUIRED_KEYS)
	if missing != "":
		return "save is missing '%s'" % missing
	var error := _entries_error(data["owners"], REQUIRED_OWNER_KEYS, "owner")
	if error != "":
		return error
	error = _entries_error(
		data.get("capture_progress", []), REQUIRED_PROGRESS_KEYS, "capture progress"
	)
	if error != "":
		return error
	error = _entries_error(data["units"], REQUIRED_UNIT_KEYS, "unit")
	if error != "":
		return error
	var funds: Variant = data["funds"]
	if not (funds is Dictionary):
		return "'funds' is malformed"
	for team in GameState.TEAMS:
		if not (funds as Dictionary).has(str(team)):
			return "save has no funds for team %d" % team
	return ""


## Carrier links are indices into the unit list, so a corrupt save can point
## anywhere. Rejecting the three ways that goes wrong — off the end of the
## list, a unit carrying itself, and a ring of units carrying each other —
## keeps the loader from building a board the rules cannot reason about, or
## looping forever walking a cargo chain.
static func _validate_carriers(indices: Array[int]) -> String:
	var count := indices.size()
	for i in count:
		var index := indices[i]
		if index == NO_CARRIER:
			continue
		if index < 0 or index >= count:
			return "unit %d has carrier index %d, outside the %d unit(s) saved" % [i, index, count]
		if index == i:
			return "unit %d is its own carrier" % i
	# Every chain must reach the board. More hops than there are units means it
	# never will, which is exactly a cycle.
	for i in count:
		var at := i
		var hops := 0
		while indices[at] != NO_CARRIER:
			at = indices[at]
			hops += 1
			if hops > count:
				return "unit %d is in a loop of units carrying each other" % i
	return ""


## The first key `data` lacks, or "" when it carries them all.
static func _missing_key(data: Dictionary, keys: Array) -> String:
	for key in keys:
		if not data.has(key):
			return String(key)
	return ""


## "" when `value` is an array of dictionaries that all carry `keys`.
static func _entries_error(value: Variant, keys: Array, what: String) -> String:
	if not (value is Array):
		return "'%s' list is malformed" % what
	for entry: Variant in value as Array:
		if not (entry is Dictionary):
			return "%s entry is malformed" % what
		var missing := _missing_key(entry as Dictionary, keys)
		if missing != "":
			return "%s entry is missing '%s'" % [what, missing]
	return ""
