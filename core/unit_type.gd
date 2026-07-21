class_name UnitType
extends Resource
## Static properties of one unit kind (infantry, tank, ...).
## Pure data: usable from the simulation core and from tests.
## Combat stats (weapons, damage chart rows) arrive in M3.

@export var id: StringName
@export var display_name: String
## Single character representing this unit in .txt map [units] sections.
@export var symbol: String
@export var cost: int = 0
@export var move_points: int = 0
@export var move_class: StringName = TerrainType.FOOT
@export var vision: int = 2
## Infantry and mechs capture properties (used from M4).
@export var can_capture: bool = false
## Weapon range in tiles; 0/0 means unarmed (APC). min_range > 1 = indirect:
## cannot move and fire, never counters, and is never countered.
@export var min_range: int = 0
@export var max_range: int = 0
## Fuel tank; movement spends fuel equal to the terrain cost of each step.
@export var max_fuel: int = 99
## Primary ammo; 0 means the weapon needs no ammo (or the unit is unarmed).
@export var max_ammo: int = 0
## How many foot/boot passengers this unit can carry (APC = 1).
@export var transport_capacity: int = 0
## Supply units (APC) refill adjacent friendlies at turn start and on demand.
@export var can_resupply: bool = false
## Column of this unit in the generated units atlas texture.
@export var atlas_col: int = 0
## Id of the terrain that produces this unit. The whole land roster is built at
## a base, which is the default; a naval or air unit names its own site instead
## and is then buildable nowhere else. This is the single authority on what a
## property can turn out — BuildCommand rejects on it and the AI filters its
## candidates through it, so the planner cannot propose a build the rules refuse.
@export var built_at: StringName = &"base"


func buildable_at(site: StringName) -> bool:
	return built_at == site
