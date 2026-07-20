extends GutTest
## PowerCommand and the two places a Command Power expires.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state() -> GameState:
	var map := MapData.parse("[terrain]\n...\n...\n[units]\n1 t 0 0\n2 i 2 0", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


## A commander built in the test rather than loaded, so the expiry machinery can
## be checked on both durations without waiting for the general who uses each.
func _commander(duration: CommanderType.Duration) -> CommanderType:
	var co := CommanderType.new()
	co.id = &"test_co"
	co.display_name = "Test CO"
	co.power_name = "Test Power"
	co.power_cost = 1000
	co.power_duration = duration
	return co


func _charged(state: GameState, team: int, duration: CommanderType.Duration) -> void:
	state.set_commander(team, _commander(duration))
	state.add_charge(team, 1000)


# --- validation --------------------------------------------------------------


func test_a_neutral_commander_has_no_power_to_fire() -> void:
	var state := _state()
	assert_eq(PowerCommand.new().validate(state), "this commander has no Command Power")


func test_an_uncharged_meter_rejects_the_power() -> void:
	var state := _state()
	state.set_commander(1, _commander(CommanderType.Duration.OWNER_TURN))
	state.add_charge(1, 999)
	assert_eq(PowerCommand.new().validate(state), "the Command Power is not charged")


func test_a_full_meter_accepts_the_power() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.OWNER_TURN)
	assert_eq(PowerCommand.new().validate(state), "")


func test_the_power_cannot_be_fired_twice() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.OWNER_TURN)
	PowerCommand.new().apply(state)
	state.add_charge(1, 1000)  # even a meter that refilled mid-turn
	assert_eq(PowerCommand.new().validate(state), "a Command Power is already active")


func test_a_finished_match_rejects_the_power() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.OWNER_TURN)
	state.winner = 2
	assert_eq(PowerCommand.new().validate(state), "the match is over")


# --- applying and expiring ---------------------------------------------------


func test_applying_spends_the_meter_and_raises_the_power() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.OWNER_TURN)
	var command := PowerCommand.new()
	command.apply(state)
	assert_eq(state.commander_state(1).charge, 0, "the full cost is spent")
	assert_true(state.power_active(1))
	assert_eq(command.team, 1, "apply records who fired, for the banner")
	assert_eq(command.commander.power_name, "Test Power")


func test_an_owner_turn_power_ends_with_the_turn_it_fired_on() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.OWNER_TURN)
	PowerCommand.new().apply(state)
	assert_true(state.power_active(1))
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1), "it covers exactly its own turn")


## Hold the Line's shape: it has to survive the opponent's whole turn, which is
## the turn it exists to defend against.
func test_a_round_power_survives_the_opponents_turn() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.ROUND)
	PowerCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "still up through blue's turn")
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1), "and down again as red's next turn opens")


func test_one_teams_power_never_touches_the_other() -> void:
	var state := _state()
	_charged(state, 1, CommanderType.Duration.OWNER_TURN)
	_charged(state, 2, CommanderType.Duration.OWNER_TURN)
	PowerCommand.new().apply(state)
	assert_true(state.power_active(1))
	assert_false(state.power_active(2))
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1))
	assert_eq(state.commander_state(2).charge, 1000, "blue's meter is untouched")


## The one-shot half of a power: everything that is not an ongoing modifier
## goes through on_power_activated, and it fires exactly once.
class HealingCommander:
	extends CommanderType

	var heals := 0

	func on_power_activated(state: GameState, team: int) -> void:
		heals += 1
		for unit in state.units_of(team):
			unit.hp = mini(100, unit.hp + 10)


func test_on_power_activated_runs_once_when_the_power_fires() -> void:
	var state := _state()
	var co := HealingCommander.new()
	co.power_cost = 1000
	state.set_commander(1, co)
	state.add_charge(1, 1000)
	state.units[0].hp = 50
	PowerCommand.new().apply(state)
	assert_eq(co.heals, 1)
	assert_eq(state.units[0].hp, 60, "the one-shot effect landed")
	EndTurnCommand.new().apply(state)
	assert_eq(co.heals, 1, "and does not fire again when the power expires")
