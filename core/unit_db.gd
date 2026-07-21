class_name UnitDB
extends RefCounted
## Registry of all UnitType resources, indexed by id and by map symbol.

const UNIT_DIR := "res://data/units"

var _by_id: Dictionary = {}
var _by_symbol: Dictionary = {}


static func load_default() -> UnitDB:
	var db := UnitDB.new()
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		push_error("UnitDB: cannot open %s" % UNIT_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var unit_type: UnitType = load(UNIT_DIR.path_join(name))
		if unit_type != null:
			db.register(unit_type)
	return db


func register(unit_type: UnitType) -> void:
	if _by_id.has(unit_type.id):
		push_error("UnitDB: duplicate unit id '%s'" % unit_type.id)
		return
	if _by_symbol.has(unit_type.symbol):
		push_error("UnitDB: duplicate unit symbol '%s'" % unit_type.symbol)
		return
	_by_id[unit_type.id] = unit_type
	_by_symbol[unit_type.symbol] = unit_type


func by_id(id: StringName) -> UnitType:
	return _by_id.get(id)


func by_symbol(symbol: String) -> UnitType:
	return _by_symbol.get(symbol)


## All unit types, cheapest first (build-menu order), ties broken by id. The
## tie-break is what makes the order total: sort_custom is not stable and several
## units share a price, so without it the menu would be seeded by whatever order
## the directory happened to list. The ids are compared as Strings deliberately —
## `<` on two StringNames ranks them by their address in the name table, which is
## an arbitrary order that can differ between one run and the next.
func all() -> Array[UnitType]:
	var result: Array[UnitType] = []
	for unit_type in _by_id.values():
		result.append(unit_type)
	result.sort_custom(
		func(a: UnitType, b: UnitType) -> bool:
			if a.cost != b.cost:
				return a.cost < b.cost
			return String(a.id) < String(b.id)
	)
	return result


func size() -> int:
	return _by_id.size()
