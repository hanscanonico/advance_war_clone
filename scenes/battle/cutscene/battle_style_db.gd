class_name BattleStyleDB
extends RefCounted
## Registry of BattleStyle resources, indexed by id. Same shape as TerrainDB and
## UnitDB — scan the directory, index by id — so adding a weapon signature is
## dropping a .tres in and naming it from a unit, with no code to change.
##
## `by_id` never returns null. A unit whose style is missing or misspelled stages
## as unarmed rather than crashing the cut-in mid-attack, the same graceful
## degradation Sfx gives a missing sound: the exchange still resolves, still ticks
## HP and still ends, it just has nothing leaving the barrel. The warning is
## pushed once per unknown id so a typo is visible in the log without filling it.

const STYLE_DIR := "res://data/battle_anim"

## The style anything unrecognised falls back to. Built in code rather than
## loaded, so the fallback cannot itself be the missing file.
static var _unarmed: BattleStyle

var _by_id: Dictionary = {}
var _warned: Dictionary = {}


static func load_default() -> BattleStyleDB:
	var db := BattleStyleDB.new()
	var dir := DirAccess.open(STYLE_DIR)
	if dir == null:
		push_error("BattleStyleDB: cannot open %s" % STYLE_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var style: BattleStyle = load(STYLE_DIR.path_join(file_name))
		if style != null:
			db.register(style)
	return db


static func unarmed() -> BattleStyle:
	if _unarmed == null:
		_unarmed = BattleStyle.new()
		_unarmed.id = &"unarmed"
		_unarmed.projectile = BattleStyle.NONE
		_unarmed.muzzle = 0.0
	return _unarmed


func register(style: BattleStyle) -> void:
	if _by_id.has(style.id):
		push_error("BattleStyleDB: duplicate style id '%s'" % style.id)
		return
	_by_id[style.id] = style


## The style a unit fires with. Never null — see the note at the top.
func for_unit(type: UnitType) -> BattleStyle:
	return by_id(type.battle_style)


func by_id(id: StringName) -> BattleStyle:
	var style: BattleStyle = _by_id.get(id)
	if style != null:
		return style
	if not _warned.has(id):
		_warned[id] = true
		push_warning("BattleStyleDB: no style '%s'; staging it unarmed" % id)
	return unarmed()


func has(id: StringName) -> bool:
	return _by_id.has(id)


func size() -> int:
	return _by_id.size()
