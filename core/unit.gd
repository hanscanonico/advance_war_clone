class_name Unit
extends RefCounted
## One unit instance on the battlefield. Pure simulation state.

var type: UnitType
var team: int
var cell: Vector2i
## Internal HP 0-100; the UI shows ceil(hp / 10).
var hp: int = 100
## True once the unit has used its action this turn.
var acted: bool = false


func displayed_hp() -> int:
	return ceili(hp / 10.0)
