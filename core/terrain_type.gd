class_name TerrainType
extends Resource
## Static properties of one terrain kind (plains, woods, city, ...).
## Pure data: usable from the simulation core and from tests.

const IMPASSABLE := -1

## Movement classes. Units reference these from their UnitType (M2).
const FOOT := &"foot"      # infantry
const BOOT := &"boot"      # mech: crosses mountains and rivers at cost 1
const TIRES := &"tires"    # recon, rockets
const TREADS := &"treads"  # tanks, artillery, anti-air, APC

@export var id: StringName
@export var display_name: String
## Single character representing this terrain in .txt map files.
@export var symbol: String
@export_range(0, 4) var defense_stars: int = 0
## Movement cost per movement class (StringName -> int).
## A missing key means the terrain is impassable for that class.
@export var move_costs: Dictionary = {}
## Capturable property (city, base, HQ).
@export var is_property: bool = false
## Column of this terrain in the generated atlas texture.
@export var atlas_col: int = 0
## Properties have team-colored variants on rows 1+ of the atlas.
@export var team_tinted: bool = false


func move_cost(move_class: StringName) -> int:
	return move_costs.get(move_class, IMPASSABLE)


func is_passable(move_class: StringName) -> bool:
	return move_costs.has(move_class)
