class_name GideonHolt
extends CommanderType
## Meridian Coalition. Logistics: his army stays in the field longer and repairs
## cheaper than anyone else's, and Open the Depots tops the whole thing up at
## once. No combat modifier at all — everything he does is measured in fuel,
## ammo and funds, which is why his power is the cheapest on the roster.

@export var apc_supply_range: int = 2
## Repairs at a discount, as a percentage of the standard price.
@export var repair_price_pct: int = 80
## Internal HP the power restores — 10 is one displayed pip.
@export var depot_heal_hp: int = 10
## What the AI counts as worn down: at or below this internal HP, at or below
## this fraction of a full tank, or out of ammo entirely.
@export var depot_want_hp: int = 70
@export var depot_want_fuel_pct: int = 50
## How many units have to want it before the depots are worth opening. The power
## tops up the whole side at once, so firing it for a single scratched unit
## wastes most of it.
@export var depot_want_units: int = 2


func supply_range(_state: GameState, _unit: Unit) -> int:
	return apc_supply_range


func repair_cost_pct(_state: GameState, _unit: Unit) -> int:
	return repair_price_pct


## Purely one-shot: the depots open, everything fills up, and nothing lingers
## afterwards — so there is no hook of his to gate on _is_active().
func on_power_activated(state: GameState, team: int) -> void:
	for unit in state.units_of(team):
		unit.resupply()
		unit.hp = mini(100, unit.hp + depot_heal_hp)


## Nothing in his kit is a fight, so nothing about the fight gates it. The
## default read — "an enemy is in reach" — would leave a logistics commander
## waiting on an engagement his power has no opinion about; this waits on the
## thing it actually fixes, an army that is worn down.
func wants_power(state: GameState, team: int) -> bool:
	var worn := 0
	for unit in state.units_of(team):
		if unit.carrier != null or not _wants_depot(unit):
			continue
		worn += 1
		if worn >= depot_want_units:
			return true
	return false


## A pip of damage gone, half the tank spent, or the magazine empty.
func _wants_depot(unit: Unit) -> bool:
	if unit.hp <= depot_want_hp:
		return true
	if unit.fuel * 100 <= unit.type.max_fuel * depot_want_fuel_pct:
		return true
	return unit.type.max_ammo > 0 and unit.ammo <= 0
