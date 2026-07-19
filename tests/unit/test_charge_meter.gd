extends GutTest
## The Command Power economy: value-weighted charge, the asymmetric split, and
## the caps that stop a meter being farmed.

const TANK_COST := 7000
const INFANTRY_COST := 1000

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	# Both sides need a power for the meter to exist at all.
	state.set_commander(1, commander_db.by_id(&"alina_ward"))
	state.set_commander(2, commander_db.by_id(&"viktor_draeg"))
	return state


## The plan's worked example: halving a 7 000 Tank is 3 500 points to the side
## that lost it, half that to the side that dealt it.
func test_value_weighted_charge_splits_asymmetrically() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.bank_losses(state.units[0], 50, 2)
	assert_eq(state.commander_state(1).charge, TANK_COST * 50 / 100, "the loser banks all of it")
	assert_eq(state.commander_state(2).charge, TANK_COST * 50 / 100 / 2, "the dealer banks half")


func test_charge_is_capped_at_the_power_cost() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	for i in 20:
		state.bank_losses(state.units[0], 100, 2)
	var co_state := state.commander_state(1)
	assert_eq(co_state.charge, co_state.type.power_cost, "an idle meter never banks a second power")
	assert_true(co_state.is_ready())
	assert_eq(co_state.charge_ratio(), 1.0)


## R5: feeding cheap units cannot buy a power. An Infantry is worth 1 000 points
## dead against a power costing eleven times that.
func test_sacrificing_infantry_barely_moves_the_meter() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	state.bank_losses(state.units[0], 100, 2)
	assert_eq(state.commander_state(1).charge, INFANTRY_COST)
	assert_false(state.commander_state(1).is_ready())


func test_a_commander_with_no_power_banks_nothing() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.set_commander(1, CommanderType.neutral())
	state.bank_losses(state.units[0], 100, 2)
	assert_eq(state.commander_state(1).charge, 0)
	assert_eq(state.commander_state(1).charge_ratio(), 0.0, "a meter with no power never fills")
	assert_false(state.commander_state(1).is_ready())


func test_combat_banks_for_both_the_attack_and_the_counter() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.rng.seed = 1234
	var result := CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_true(result.countered, "this exchange needs a counter to be worth checking")
	var dealt := TANK_COST * result.attack_damage / 100
	var taken := TANK_COST * result.counter_damage / 100
	assert_eq(state.commander_state(1).charge, taken + dealt / 2, "red lost HP and dealt HP")
	assert_eq(state.commander_state(2).charge, dealt + taken / 2, "blue lost HP and dealt HP")


## A kill charges for the HP the victim actually had, not for whatever overkill
## the luck roll produced — otherwise a lucky roll would pay a bonus.
func test_a_kill_charges_only_for_the_hp_on_the_board() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 7
	var defender := state.units[1]
	defender.hp = 10
	var result := CombatResolver.resolve(state, state.units[0], defender)
	assert_true(result.defender_died)
	assert_gt(result.attack_damage, 10, "the roll has to overkill for this test to mean anything")
	assert_eq(state.commander_state(2).charge, INFANTRY_COST * 10 / 100)
