class_name JoinCommand
extends Command
## Merges a unit into a damaged same-type friendly on the destination cell.
## HP, fuel, and ammo add up (capped at the type maximums); the moving unit
## disappears and the merged unit is exhausted.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var steps := MoveCommand.validate_path_steps(state, unit, path)
	if steps != "":
		return steps
	var target := state.unit_at(path[path.size() - 1])
	if target == null or target == unit:
		return "no unit to join at the destination"
	if target.team != unit.team or target.type != unit.type:
		return "can only join an identical friendly unit"
	if target.acted:
		return "target has already acted"
	if target.displayed_hp() >= 10:
		return "target is at full strength"
	if not state.cargo_of(unit).is_empty() or not state.cargo_of(target).is_empty():
		return "cannot join transports with cargo"
	return ""


func apply(state: GameState) -> void:
	var target := state.unit_at(path[path.size() - 1])
	ambushed = state.advance_unit(unit, path)  # spends fuel, resets any abandoned capture
	if ambushed:
		return  # stopped short of the friendly; the two do not merge
	target.hp = mini(100, target.hp + unit.hp)
	target.fuel = mini(target.type.max_fuel, target.fuel + unit.fuel)
	target.ammo = mini(target.type.max_ammo, target.ammo + unit.ammo)
	target.acted = true
	# Plain erase, not remove_unit: nothing died, so no rout check, and the
	# target's own capture progress on this cell must survive the merge.
	state.units.erase(unit)
