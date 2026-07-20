class_name AttackCommand
extends Command
## Moves a unit along its path (possibly staying put), then attacks the unit
## on target_cell. Indirect units (min_range > 1) may only fire without moving.

var unit: Unit
var path: Array[Vector2i]
var target_cell: Vector2i
## Populated by apply() so the presentation layer can animate the outcome.
var result: CombatResolver.CombatResult


func _init(p_unit: Unit, p_path: Array[Vector2i], p_target_cell: Vector2i) -> void:
	unit = p_unit
	path = p_path
	target_cell = p_target_cell


func validate(state: GameState) -> String:
	var move_error := MoveCommand.new(unit, path).validate(state)
	if move_error != "":
		return move_error
	if unit.type.max_range <= 0:
		return "unit is unarmed"
	if not unit.has_ammo():
		return "out of ammo"
	if AttackRange.is_indirect(unit) and path.size() > 1:
		return "indirect units cannot move and fire"
	var target := state.unit_at(target_cell)
	if target == null:
		return "no unit at the target cell"
	if target.team == unit.team:
		return "cannot attack a friendly unit"
	if not AttackRange.covers(state, unit, path[path.size() - 1], target_cell):
		return "target out of range"
	if not state.damage_chart.can_attack(unit.type.id, target.type.id):
		return "cannot damage the target"
	return ""


func apply(state: GameState) -> void:
	var target := state.unit_at(target_cell)
	state.advance_unit(unit, path)
	result = CombatResolver.resolve(state, unit, target)
