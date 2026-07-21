class_name UnitType
extends Resource
## Static properties of one unit kind (infantry, tank, ...).
## Pure data: usable from the simulation core and from tests.
## Combat stats (weapons, damage chart rows) arrive in M3.

## Movement domains. Where `move_class` says which tiles a unit may enter, the
## domain says what *kind* of thing it is, and three rules ask: which properties
## service it (TerrainType.services), whether the ground below it is cover it
## gets to keep (CombatResolver), and whether an empty tank strands it or kills
## it (TurnRules).
const LAND := &"land"
const AIR := &"air"
const SEA := &"sea"

@export var id: StringName
@export var display_name: String
## Single character representing this unit in .txt map [units] sections.
@export var symbol: String
@export var cost: int = 0
@export var move_points: int = 0
@export var move_class: StringName = TerrainType.FOOT
## Which of LAND / AIR / SEA this unit is. See the constants above.
@export var domain: StringName = LAND
@export var vision: int = 2
## Infantry and mechs capture properties (used from M4).
@export var can_capture: bool = false
## Weapon range in tiles; 0/0 means unarmed (APC). min_range > 1 = indirect:
## cannot move and fire, never counters, and is never countered.
@export var min_range: int = 0
@export var max_range: int = 0
## Fuel tank; movement spends fuel equal to the terrain cost of each step.
@export var max_fuel: int = 99
## Fuel burned at the start of every one of this unit's turns, before it is
## resupplied. Zero for anything that can simply park — a plane cannot, which is
## what makes an airport worth taking. See TurnRules.begin_turn for the order.
@export var fuel_upkeep: int = 0
## Primary ammo; 0 means the weapon needs no ammo (or the unit is unarmed).
@export var max_ammo: int = 0
## How many passengers this unit can carry (APC = 1).
@export var transport_capacity: int = 0
## Move classes this unit can carry. An APC and a T-Copter take foot and boot;
## a Lander takes anything that drives. Empty means it carries nothing, which
## `transport_capacity` also has to agree with before a load is legal.
@export var cargo_classes: Array[StringName] = []
## Supply units (APC) refill adjacent friendlies at turn start and on demand.
@export var can_resupply: bool = false
## Column of this unit in the generated units atlas texture.
@export var atlas_col: int = 0


## True when running dry destroys this unit rather than merely stranding it.
## A plane falls out of the sky and a ship is lost; a tank just stops, which is
## how every land unit behaved before air and sea existed.
func lost_when_dry() -> bool:
	return domain != LAND


## True when this unit can carry `carried_class`. Capacity is a separate
## question — see GameState.cargo_of — but a transport that carries nothing is
## not a transport whatever its capacity says.
func can_carry(carried_class: StringName) -> bool:
	return transport_capacity > 0 and carried_class in cargo_classes
