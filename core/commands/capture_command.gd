class_name CaptureCommand
extends Command
## Moves a capture-capable unit onto a property and chips at its capture
## points. Reaching zero flips ownership; taking the enemy HQ wins the match.

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
	state.advance_unit(unit, path)
	var dest: Vector2i = path[path.size() - 1]
	var points: int = state.capture_progress.get(dest, GameState.CAPTURE_POINTS)
	points -= capture_strength(state, unit)
	if points > 0:
		state.capture_progress[dest] = points
		return
	state.capture_progress.erase(dest)
	state.set_owner(dest, unit.team)
	if state.map.terrain_at(dest).id == &"hq":
		state.winner = unit.team


## Capture points chipped off per turn: the unit's displayed HP, adjusted by its
## commander's doctrine and rounded down. Floored at 1 so no doctrine can ever
## stall a capture outright, and public so the UI can show what a turn is worth.
static func capture_strength(state: GameState, unit: Unit) -> int:
	var bonus := state.commander_of(unit.team).capture_bonus_pct(state, unit)
	return maxi(1, unit.displayed_hp() * (100 + bonus) / 100)
