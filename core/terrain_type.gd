class_name TerrainType
extends Resource
## Static properties of one terrain kind (plains, woods, city, ...).
## Pure data: usable from the simulation core and from tests.

const IMPASSABLE := -1

## Movement classes. Units reference these from their UnitType (M2).
const FOOT := &"foot"  # infantry
const BOOT := &"boot"  # mech: crosses mountains and rivers at cost 1
const TIRES := &"tires"  # recon, rockets, missiles
const TREADS := &"treads"  # tanks, artillery, anti-air, APC
const AIR := &"air"  # everything that flies: costs 1 on every terrain

@export var id: StringName
@export var display_name: String
## Single character representing this terrain in .txt map files.
@export var symbol: String
@export_range(0, 4) var defense_stars: int = 0
## Movement cost per movement class (StringName -> int).
## A missing key means the terrain is impassable for that class.
@export var move_costs: Dictionary = {}
## Capturable property (city, base, HQ, airport, port).
@export var is_property: bool = false
## Move classes this terrain produces units of: a base builds what drives, a
## port what floats, an airport what flies. Empty means it builds nothing, which
## is every terrain that is not a factory of some kind.
##
## This list, and not a terrain id, is what BuildCommand, the build menu and the
## AI's production all ask — so adding a facility is a data edit and none of the
## three can be the one that was forgotten.
@export var builds: Array[StringName] = []
## Unit domains this property repairs and resupplies (see UnitType's LAND / AIR
## / SEA). A city refits what drives and nothing else, so a bomber parked on one
## gets no fuel out of it — which is the whole reason airports are worth taking.
@export var services: Array[StringName] = []
## Column of this terrain in the generated atlas texture.
@export var atlas_col: int = 0
## Properties have team-colored variants on rows 1+ of the atlas.
@export var team_tinted: bool = false


func move_cost(move_class: StringName) -> int:
	return move_costs.get(move_class, IMPASSABLE)


func is_passable(move_class: StringName) -> bool:
	return move_costs.has(move_class)


func can_build(move_class: StringName) -> bool:
	return move_class in builds


## True when a unit of `domain` standing here is repaired and refuelled — asked
## by TurnRules for both, so the two can never disagree about one property.
func services_domain(domain: StringName) -> bool:
	return domain in services
