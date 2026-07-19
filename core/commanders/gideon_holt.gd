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


func supply_range(_state: GameState, _unit: Unit) -> int:
	return apc_supply_range


func repair_cost_pct(_state: GameState, _unit: Unit) -> int:
	return repair_price_pct


## Purely one-shot: the depots open, everything fills up, and nothing lingers
## afterwards — so there is no hook of his to gate on is_active().
func on_power_activated(state: GameState, team: int) -> void:
	for unit in state.units_of(team):
		unit.resupply()
		unit.hp = mini(100, unit.hp + depot_heal_hp)
