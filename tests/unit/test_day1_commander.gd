extends GutTest
## The opening begin_turn — day 1 for the first player, run inside GameState.create
## — must resolve against that side's real commander, not the neutral one. The bug:
## every caller assigned commanders *after* create, so team 1's day-1 doctrine
## (Gideon Holt's two-tile supply radius) went unconsulted, while team 2's first
## turn, reached later through EndTurnCommand, already saw its real commander.
## Passing commanders into create closes that slot-order asymmetry.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB

# A b_copter burns two fuel every begin_turn, so its opening tick is observable
# even on day 1 when every unit starts full: an APC two tiles away tops it back up
# under Gideon's radius, but only an adjacent one would under the neutral radius
# of 1. Both sides carry an APC-and-copter pair so either slot can be tested.
const BOARD := "[terrain]\n===\n===\n[units]\n1 p 0 0\n1 h 2 0\n2 p 0 1\n2 h 2 1"


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _gideon() -> CommanderType:
	return commander_db.by_id(&"gideon_holt")


func _copter_of(state: GameState, team: int) -> Unit:
	for unit in state.units_of(team):
		if unit.type.id == &"b_copter":
			return unit
	return null


## The failing case: team 1's day-1 opening tick used to run against neutral, so a
## copter two tiles from its APC was left two fuel short.
func test_team_1_day_1_begin_turn_uses_its_real_commander() -> void:
	var map := MapData.parse(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart, {1: _gideon()})
	assert_not_null(state)
	var copter := _copter_of(state, 1)
	assert_eq(copter.fuel, copter.type.max_fuel, "Gideon's APC resupplies from two tiles on day 1")


## The mirror slot: team 2's first begin_turn, reached by ending team 1's turn,
## has always seen its real commander. The asymmetry the fix removes is that team 1
## now does too — the same doctrine, the same result, on either seat.
func test_team_2_first_begin_turn_uses_its_real_commander() -> void:
	var map := MapData.parse(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart, {2: _gideon()})
	assert_not_null(state)
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 2, "team 2 is now to move")
	var copter := _copter_of(state, 2)
	assert_eq(copter.fuel, copter.type.max_fuel, "Gideon's APC resupplies from two tiles")


## Control: the neutral commander reaches only one tile, so the same copter is left
## two fuel short — the observable is real, and the doctrine is what moves it.
func test_a_neutral_first_player_reaches_only_one_tile() -> void:
	var map := MapData.parse(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var copter := _copter_of(state, 1)
	assert_eq(
		copter.fuel,
		copter.type.max_fuel - copter.upkeep(),
		"two tiles is out of the neutral commander's reach"
	)
