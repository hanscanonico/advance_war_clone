class_name CommanderDB
extends RefCounted
## Registry of all CommanderType resources, indexed by id. Mirrors UnitDB.
##
## The neutral commander is not a file: it is CommanderType's own defaults, and
## it is always present under `CommanderType.NEUTRAL_ID` so the CO picker and a
## save that names no commander both resolve through the same lookup.

const COMMANDER_DIR := "res://data/commanders"

var _by_id: Dictionary = {}


static func load_default() -> CommanderDB:
	var db := CommanderDB.new()
	db.register(CommanderType.neutral())
	var dir := DirAccess.open(COMMANDER_DIR)
	if dir == null:
		push_error("CommanderDB: cannot open %s" % COMMANDER_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var commander: CommanderType = load(COMMANDER_DIR.path_join(file_name))
		if commander != null:
			db.register(commander)
	return db


func register(commander: CommanderType) -> void:
	if _by_id.has(commander.id):
		push_error("CommanderDB: duplicate commander id '%s'" % commander.id)
		return
	_by_id[commander.id] = commander


## Never null: an unknown id falls back to the neutral commander, so a save that
## names a general who has since been removed still loads and plays.
func by_id(id: StringName) -> CommanderType:
	return _by_id.get(id, CommanderType.neutral())


func has(id: StringName) -> bool:
	return _by_id.has(id)


## Every commander, neutral first and the rest grouped by faction then name —
## the order the CO picker shows them in.
func all() -> Array[CommanderType]:
	var result: Array[CommanderType] = []
	for commander: CommanderType in _by_id.values():
		result.append(commander)
	result.sort_custom(
		func(a: CommanderType, b: CommanderType) -> bool:
			if a.faction != b.faction:
				return a.faction < b.faction
			return a.display_name < b.display_name
	)
	return result


func size() -> int:
	return _by_id.size()
