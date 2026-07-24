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


## Firing empties the meter (charge -> 0); the bug this pins is that the combat
## the power enables must not refill it while it is still up, or the power is
## never re-earned. The owner banks nothing until the power comes down again.
func test_a_running_power_banks_nothing_for_its_owner() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	var alina := state.commander_state(1)
	state.add_charge(1, alina.type.power_cost)
	assert_true(alina.is_ready(), "team 1 opens the scenario with a full meter")

	PowerCommand.new().apply(state)  # fires for the current team (team 1)
	assert_eq(alina.charge, 0, "firing empties the meter")
	assert_true(alina.power_active)

	# The kind of exchange the power exists to win, resolved while it is up.
	state.bank_losses(state.units[0], 100, 2)  # team 1 loses a whole tank
	state.bank_losses(state.units[1], 100, 1)  # team 1 destroys one in reply
	assert_eq(alina.charge, 0, "a running power banks nothing, dealt or lost")

	# The opponent's meter is a separate economy and fills as usual.
	assert_gt(state.commander_state(2).charge, 0, "the side without a power up still banks")


## The exact reported bug: fire, fight through the power turn, end it — and the
## meter is still down, so the power has to be charged again from empty rather
## than coming back READY the instant it expires.
func test_the_meter_must_be_re_earned_after_a_power() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	state.add_charge(1, state.commander_state(1).type.power_cost)
	PowerCommand.new().apply(state)
	state.bank_losses(state.units[0], 100, 2)  # combat during the active turn

	EndTurnCommand.new().apply(state)  # the OWNER_TURN power expires here
	var alina := state.commander_state(1)
	assert_false(alina.power_active, "the power came down with the turn")
	assert_eq(alina.charge, 0, "and the meter is empty, not refilled under the power")
	assert_false(alina.is_ready(), "so it cannot be fired again until re-earned")
