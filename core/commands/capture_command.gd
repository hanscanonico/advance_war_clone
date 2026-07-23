class_name CaptureCommand
extends Command
## Moves a capture-capable unit onto a property and chips at its capture
## points. Reaching zero flips ownership; taking the enemy HQ wins the match.


## The snapshot the capture cut-in replays (plan D1). Filled by apply() at the
## moment the sim commits the numbers, and read only by the presentation layer —
## nothing in core/ or ai/ touches it, exactly as AttackCommand.result is read
## only by the animator. The cut-in must replay these, never recompute them: a
## second opinion on capture math is the bug class this repo already paid for
## once with movement.
class CaptureResult:
	## Capture points remaining before and after this action, 0-20. `points_after`
	## is clamped at zero, so `points_before - points_after` is the honest count
	## the meter drains by — and the chips sum to — even when a strong unit
	## overshoots the last few points.
	var points_before := 0
	var points_after := 0
	## Who owned the property going in, for the atlas row the cut-in shows before
	## the flip. On a partial capture it is the owner throughout.
	var owner_before := 0
	## True when this action flipped ownership — the completing capture.
	var captured := false


var unit: Unit
var path: Array[Vector2i]
## Populated by apply() so the presentation layer can animate the capture.
var result: CaptureResult


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
	ambushed = state.advance_unit(unit, path)
	if ambushed:
		return  # stopped short of the property; nothing is captured
	var dest: Vector2i = path[path.size() - 1]
	var before: int = state.capture_progress.get(dest, GameState.CAPTURE_POINTS)
	var remaining := before - capture_strength(state, unit)
	result = CaptureResult.new()
	result.points_before = before
	result.points_after = maxi(remaining, 0)
	result.owner_before = state.owner_at(dest)
	result.captured = remaining <= 0
	if remaining > 0:
		state.capture_progress[dest] = remaining
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
