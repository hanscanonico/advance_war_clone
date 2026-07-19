class_name TomasReed
extends CommanderType
## Verdant League. An infantry doctrine: his foot units fight and capture above
## their price, his vehicles below theirs, so he wants a cheap wide army taking
## ground rather than an expensive one holding it. Popular Uprising can take a
## property outright in a single turn.
##
## Keyed on movement class rather than unit id: "foot units" is what the
## doctrine means, and a future walking unit should inherit it without an edit
## here.

@export var foot_classes: Array[StringName] = [TerrainType.FOOT, TerrainType.BOOT]
@export var foot_attack_pct: int = 15
## Negative on purpose: what the infantry bonus above costs him.
@export var vehicle_attack_pct: int = -10
@export var capture_pct: int = 20
## +100 doubles the chip, so 10 displayed HP takes a property in one turn.
@export var uprising_capture_pct: int = 100
@export var uprising_move_bonus: int = 1


func attack_bonus(_state: GameState, fight: Engagement) -> int:
	return foot_attack_pct if _is_foot(fight.attacker) else vehicle_attack_pct


func capture_bonus_pct(state: GameState, unit: Unit) -> int:
	var bonus := capture_pct
	if is_active(state, unit.team):
		bonus += uprising_capture_pct
	return bonus


func move_bonus(state: GameState, unit: Unit) -> int:
	if not is_active(state, unit.team) or not _is_foot(unit):
		return 0
	return uprising_move_bonus


func _is_foot(unit: Unit) -> bool:
	return unit.type.move_class in foot_classes
