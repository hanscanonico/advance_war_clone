class_name SaveGame
extends RefCounted
## Storage for a running match: reads and writes the single save slot under
## user://, and nothing else.
##
## Everything about *what* a save contains — the field layout, the validation
## rules, rebuilding a GameState — belongs to SaveCodec. This file only knows
## about files and JSON text, so a disk error and a malformed save are separate
## failures with separate messages.
##
## The public surface is deliberately unchanged: `save`, `load_game`,
## `has_save`, `SAVE_PATH`, and `VERSION` are what callers use, and the on-disk
## format is still version 1.

const SAVE_PATH := "user://save.json"
const VERSION := SaveCodec.VERSION


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


static func save(state: GameState, ai_teams: Array[int], path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(SaveCodec.encode(state, ai_teams), "\t"))
	return true


## Returns null (with a pushed error) when the file is missing or invalid.
static func load_game(
	terrain_db: TerrainDB, unit_db: UnitDB, damage_chart: DamageChart, path: String = SAVE_PATH
) -> SaveCodec.LoadedMatch:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveGame: cannot read %s" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_error("SaveGame: %s is not a valid save" % path)
		return null
	return SaveCodec.decode(json.data, terrain_db, unit_db, damage_chart)
