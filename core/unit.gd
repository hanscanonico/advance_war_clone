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
## Remaining fuel; movement spends it point-for-point with terrain cost.
var fuel: int = 99
## Remaining primary ammo; only meaningful when type.max_ammo > 0.
var ammo: int = 0
## The transport carrying this unit, or null when on the board. Carried units
## are invisible to cell lookups and can neither act nor be targeted.
var carrier: Unit = null
## Submerged (subs only). A dived unit is hidden from enemies that are not
## standing next to it — with or without fog, unlike everything else the fog
## rules hide — and only a weapon that reaches under the surface can touch it.
## It still occupies its cell: an enemy that moves into it finds it there. That
## blocking is visible even when the boat is not — with fog off the move-range
## overlay shows a one-tile hole where it sits, which gives its position away.
## Known and accepted: the proper answer is the trap behaviour a hidden unit has
## in Advance Wars, where moving into one halts you there, and that is deferred.
var dived: bool = false


static func create(p_type: UnitType, p_team: int, p_cell: Vector2i) -> Unit:
	var unit := Unit.new()
	unit.type = p_type
	unit.team = p_team
	unit.cell = p_cell
	unit.fuel = p_type.max_fuel
	unit.ammo = p_type.max_ammo
	return unit


func displayed_hp() -> int:
	return ceili(hp / 10.0)


## True when the unit can still fire (max_ammo 0 = the weapon needs none).
func has_ammo() -> bool:
	return type.max_ammo == 0 or ammo > 0


## True when the unit has under `margin_turns` worth of fuel left: it can no
## longer both fly a full move and pay that many days of upkeep. Always false for
## anything an empty tank merely strands — a tank out of fuel is parked, not
## doomed, so warning about it would be noise.
##
## The single definition of "running dry". The board's warning badge, the tile
## panel and the AI's decision to break off and refuel all ask this one question,
## which is what stops the interface flagging a unit the planner is happy with,
## or the reverse.
func running_dry(margin_turns: int = 1) -> bool:
	if not type.lost_when_dry() or margin_turns <= 0:
		return false
	return fuel <= (upkeep() + type.move_points) * margin_turns


## Fuel this unit burns at the start of its turn. Staying under costs a submarine
## several times what running on the surface does, which is the clock the whole
## dive mechanic is played against: hiding is free of risk and expensive in fuel.
func upkeep() -> int:
	return type.dived_fuel_upkeep if dived else type.fuel_upkeep


func resupply() -> void:
	fuel = type.max_fuel
	ammo = type.max_ammo
