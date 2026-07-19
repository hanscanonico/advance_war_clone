class_name NiaRowan
extends CommanderType
## Verdant League. Terrain doctrine: her foot units treat the difficult ground
## everyone else avoids as ordinary, so woods and mountains become her road
## network rather than an obstacle. Ghost March adds sight to that mobility for
## a turn, and lifts the rule that woods hide what is more than a tile away.
##
## No combat modifier at all — everything she does is positional.

@export var discount_classes: Array[StringName] = [TerrainType.FOOT, TerrainType.BOOT]
@export var discount_terrain: Array[StringName] = [&"woods", &"mountain"]
## Movement points taken off a discounted step. MovementResolver floors the
## result at 1, so this can never make a step free.
@export var terrain_discount: int = 1
@export var march_classes: Array[StringName] = [TerrainType.FOOT, TerrainType.BOOT]
## Recon is not foot, but scouting is the point of Ghost March.
@export var march_ids: Array[StringName] = [&"recon"]
@export var march_move_bonus: int = 1
@export var march_vision_bonus: int = 1


func terrain_cost(_state: GameState, unit: Unit, terrain: TerrainType, base: int) -> int:
	if unit.type.move_class not in discount_classes or terrain.id not in discount_terrain:
		return base
	return base - terrain_discount


func move_bonus(state: GameState, unit: Unit) -> int:
	return march_move_bonus if _marching(state, unit) else 0


func vision_bonus(state: GameState, unit: Unit) -> int:
	return march_vision_bonus if _marching(state, unit) else 0


func sees_into_woods(state: GameState, unit: Unit) -> bool:
	return _marching(state, unit)


func _marching(state: GameState, unit: Unit) -> bool:
	if not is_active(state, unit.team):
		return false
	return unit.type.move_class in march_classes or unit.type.id in march_ids
