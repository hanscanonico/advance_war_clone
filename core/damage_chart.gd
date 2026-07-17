class_name DamageChart
extends Resource
## Base damage matrix: attacker unit id -> (defender unit id -> base damage %).
## A missing entry means the attacker cannot damage that defender at all.

@export var chart: Dictionary = {}


func base_damage(attacker: StringName, defender: StringName) -> int:
	var row: Dictionary = chart.get(attacker, {})
	return row.get(defender, -1)


func can_attack(attacker: StringName, defender: StringName) -> bool:
	return base_damage(attacker, defender) >= 0
