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
## Column of this unit in the generated units atlas texture.
@export var atlas_col: int = 0
