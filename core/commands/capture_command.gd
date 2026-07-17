class_name CaptureCommand
extends Command
## Moves a capture-capable unit onto a property and chips at its capture
## points by the unit's displayed HP. Reaching zero flips ownership; taking
## the enemy HQ wins the match.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var move_error := MoveCommand.new(unit, path).validate(state)
	if move_error != "":
		return move_error
	if not unit.type.can_capture:
		return "unit cannot capture"
	var dest: Vector2i = path[path.size() - 1]
	var terrain := state.map.terrain_at(dest)
	if not terrain.is_property:
		return "destination is not a property"
	if state.owner_at(dest) == unit.team:
		return "property already owned"
	return ""


func apply(state: GameState) -> void:
	var origin: Vector2i = path[0]
	var dest: Vector2i = path[path.size() - 1]
	if dest != origin:
		state.notify_unit_left(origin)
	unit.cell = dest
	unit.acted = true
	var points: int = state.capture_progress.get(dest, GameState.CAPTURE_POINTS)
	points -= unit.displayed_hp()
	if points > 0:
		state.capture_progress[dest] = points
		return
	state.capture_progress.erase(dest)
	state.set_owner(dest, unit.team)
	if state.map.terrain_at(dest).id == &"hq":
		state.winner = unit.team
