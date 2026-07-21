class_name DifficultyDB
extends RefCounted
## Registry of Difficulty tiers, indexed by id. Mirrors CommanderDB and UnitDB:
## the tiers are data under data/difficulty/, and an unknown id — a save or flag
## naming a tier that has since been removed — falls back to Normal so the match
## still plays.

const DIFFICULTY_DIR := "res://data/difficulty"
const DEFAULT_ID := Difficulty.DEFAULT_ID
## Menu order, gentlest first. An id not listed sorts last, so a tier added
## before this list learns about it is still shown — just at the end.
const ORDER: Array[StringName] = [&"easy", &"normal", &"hard"]

var _by_id: Dictionary = {}


static func load_default() -> DifficultyDB:
	var db := DifficultyDB.new()
	var dir := DirAccess.open(DIFFICULTY_DIR)
	if dir == null:
		push_error("DifficultyDB: cannot open %s" % DIFFICULTY_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var tier: Difficulty = load(DIFFICULTY_DIR.path_join(file_name))
		if tier != null:
			db.register(tier)
	return db


func register(tier: Difficulty) -> void:
	if _by_id.has(tier.id):
		push_error("DifficultyDB: duplicate difficulty id '%s'" % tier.id)
		return
	_by_id[tier.id] = tier


## Never null: an unknown id falls back to Normal, and a data dir so broken that
## even Normal is missing yields a built-in Normal tier, so difficulty can never
## take the game out.
func by_id(id: StringName) -> Difficulty:
	if _by_id.has(id):
		return _by_id[id]
	if _by_id.has(DEFAULT_ID):
		return _by_id[DEFAULT_ID]
	return _fallback_normal()


func has(id: StringName) -> bool:
	return _by_id.has(id)


func size() -> int:
	return _by_id.size()


## The tiers in menu order, gentlest first.
func all() -> Array[Difficulty]:
	var result: Array[Difficulty] = []
	for tier: Difficulty in _by_id.values():
		result.append(tier)
	result.sort_custom(func(a: Difficulty, b: Difficulty) -> bool: return _rank(a.id) < _rank(b.id))
	return result


static func _rank(id: StringName) -> int:
	var index := ORDER.find(id)
	return index if index >= 0 else ORDER.size()


static func _fallback_normal() -> Difficulty:
	var tier := Difficulty.new()
	tier.id = DEFAULT_ID
	tier.display_name = "Normal"
	return tier
