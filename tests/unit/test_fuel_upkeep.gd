extends GutTest
## Fuel upkeep and the crash: the rule that separates aircraft from faster tanks.
## They burn fuel simply by existing and are destroyed when the tank runs dry, so
## holding an airfield is what keeps an air force in the sky.
##
## The order inside TurnRules.begin_turn is the whole mechanic — upkeep, then
## resupply, then the empty-tank check, then repair — so each step of it is
## pinned separately here. Movement fuel, ammo and field supply live next door in
## test_fuel_and_ammo.gd; this file is only what upkeep added.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


func test_ground_units_burn_no_fuel_standing_still() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0")
	state.units[0].fuel = 40
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)  # back to red
	assert_eq(state.units[0].fuel, 40, "a parked tank costs nothing to keep")


func test_aircraft_burn_upkeep_every_turn() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 b 0 0")
	var bomber := state.units[0]
	assert_eq(bomber.fuel, 99)
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(bomber.fuel, 99 - bomber.type.fuel_upkeep, "a bomber pays to stay up")


func test_aircraft_is_lost_when_the_tank_runs_dry() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 b 0 0\n1 i 1 0")
	var bomber := state.units[0]
	bomber.fuel = bomber.type.fuel_upkeep  # exactly enough for one more day
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(state.unit_at(Vector2i(0, 0)), null, "the bomber should have fallen out of the sky")
	assert_false(bomber in state.units)


## Upkeep is charged before resupply, but resupply runs before the crash check,
## so a plane that reached its airfield is always full again and can never die on
## friendly tarmac — even having landed with an empty tank.
func test_an_aircraft_on_its_airfield_is_never_lost() -> void:
	var state := _state("[terrain]\nA.\n[owners]\n1 0 0\n[units]\n1 b 0 0")
	var bomber := state.units[0]
	bomber.fuel = 0
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_true(bomber in state.units, "an airport should refuel before the tank is checked")
	assert_eq(bomber.fuel, bomber.type.max_fuel)


func test_a_city_does_not_refit_aircraft() -> void:
	var state := _state("[terrain]\nC.\n[owners]\n1 0 0\n[units]\n1 h 0 0")
	var copter := state.units[0]
	copter.fuel = 30
	copter.hp = 50
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(copter.fuel, 30 - copter.type.fuel_upkeep, "a city has no fuel a helicopter can use")
	assert_eq(copter.hp, 50, "and no mechanics for it either")


func test_an_airport_does_not_refit_ground_units() -> void:
	var state := _state("[terrain]\nA.\n[owners]\n1 0 0\n[units]\n1 t 0 0")
	var tank := state.units[0]
	tank.fuel = 20
	tank.ammo = 0
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(tank.fuel, 20, "a hangar stocks no diesel")
	assert_eq(tank.ammo, 0)


## An APC refuels anything it can reach, aircraft included — the field supply
## that makes a forward push sustainable without holding an airfield.
func test_an_apc_refuels_an_aircraft_in_the_field() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 p 0 0\n1 h 1 0")
	var copter := state.units[1]
	copter.fuel = 10
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(copter.fuel, copter.type.max_fuel)


## Cargo does not fly itself, so it pays no upkeep and cannot run dry in the
## hold — but it still goes down with the transport that does.
func test_cargo_burns_nothing_and_dies_with_its_carrier() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 H 0 0\n1 i 1 0")
	var copter := state.units[0]
	var rifleman := state.units[1]
	LoadCommand.new(rifleman, _path([Vector2i(1, 0), Vector2i(0, 0)])).apply(state)
	rifleman.fuel = 3
	copter.fuel = copter.type.fuel_upkeep
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(rifleman.fuel, 3, "a passenger burns nothing")
	assert_false(copter in state.units, "the T-Copter ran dry")
	assert_false(rifleman in state.units, "and took its passenger down with it")


## Running yourself dry is not an exchange, so neither meter gains from it.
## Otherwise starving your own air force would be a way to feed a Command Power.
func test_a_crash_banks_no_command_power_charge() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 b 0 0\n1 i 1 0\n2 i 0 1")
	var commanders := CommanderDB.load_default()
	state.set_commander(1, commanders.by_id(&"mara_voss"))
	state.set_commander(2, commanders.by_id(&"mara_voss"))
	var bomber := state.units[0]
	bomber.fuel = bomber.type.fuel_upkeep
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_false(bomber in state.units)
	assert_eq(state.commander_state(1).charge, 0, "the owner banks nothing for its own loss")
	assert_eq(state.commander_state(2).charge, 0, "and the enemy banks nothing it did not do")


## Wiping yourself out is still a rout: the match cannot carry on with one side
## holding no units because its last plane fell.
func test_losing_the_last_unit_to_fuel_ends_the_match() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 b 0 0\n2 i 1 0")
	state.units[0].fuel = state.units[0].type.fuel_upkeep
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(state.winner, 2)


## The warning the board badge, the tile panel and the AI all share.
func test_running_dry_flags_only_units_an_empty_tank_kills() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 h 1 0")
	var tank := state.units[0]
	var copter := state.units[1]
	tank.fuel = 0
	assert_false(tank.running_dry(), "an empty tank is parked, not doomed")
	assert_false(copter.running_dry(), "a full copter has nothing to warn about")
	copter.fuel = copter.type.fuel_upkeep + copter.type.move_points
	assert_true(copter.running_dry())
	assert_false(copter.running_dry(0), "a zero margin turns the warning off")
