class_name DiveCommand
extends Command
## Moves a submarine, then takes it under or brings it back up.
##
## One command for both directions rather than a pair, because they are the same
## action with the flag the other way round and share every rule about when it is
## legal. `submerge` says which is meant; the menu offers whichever the boat is
## not currently doing.
##
## Shaped like SupplyCommand: move along the path, then do the thing. That is
## what makes it an ordinary turn — a sub dives *and* repositions, it does not
## spend a turn standing still to close a hatch.

var unit: Unit
var path: Array[Vector2i]
## True to go under, false to surface.
var submerge: bool


func _init(p_unit: Unit, p_path: Array[Vector2i], p_submerge: bool) -> void:
	unit = p_unit
	path = p_path
	submerge = p_submerge


func validate(state: GameState) -> String:
	var move_error := MoveCommand.new(unit, path).validate(state)
	if move_error != "":
		return move_error
	if not unit.type.can_dive:
		return "unit cannot dive"
	if unit.dived == submerge:
		return "already submerged" if submerge else "already on the surface"
	return ""


func apply(state: GameState) -> void:
	ambushed = state.advance_unit(unit, path)
	if ambushed:
		return  # cut short by a hidden enemy; the boat just stops, hatch as it was
	unit.dived = submerge
