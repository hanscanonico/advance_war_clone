extends GutTest
## Mara Voss, and with her the is_counter flag and the ROUND power duration.

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
	state.set_commander(1, commander_db.by_id(&"mara_voss"))
	return state


func _fire_power(state: GameState) -> void:
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


# --- the doctrine ------------------------------------------------------------


## Her Tank opening on an Infantry: 25 * 0.9 * 0.9 = 20.25 -> 20, against 23.
func test_initiating_hits_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		20
	)


## The same units the other way round: the enemy Tank opens, and her Infantry's
## counter carries the bonus. Infantry vs Tank base 5, defender at 8 displayed
## after the hit: 5 * 1.2 * 0.8 * 0.9 = 4.32 -> 4, against 5 * 0.8 * 0.9 = 3.6
## -> 4. Read the hook directly, since rounding hides it at this base damage.
func test_countering_hits_harder() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(1, 0), 10, true
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 20, "countering")
	fight.is_counter = false
	assert_eq(state.commander_of(1).attack_bonus(state, fight), -10, "initiating")


## Indirect units never counter, so neither half of the doctrine reaches them.
func test_indirect_units_are_untouched() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 i 2 0")
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(2, 0), 10
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 0)


# --- Hold the Line -----------------------------------------------------------


## The whole point of a ROUND power: it has to still be up while the opponent
## plays, since that is the turn it defends against.
func test_the_power_covers_the_opponents_turn() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	_fire_power(state)
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "still up on blue's turn")
	# Blue's Tank into her defended Infantry: 25 * (200 - 130)/100 * 0.9
	# = 25 * 0.7 * 0.9 = 15.75 -> 16, against 23 undefended.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		16
	)
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1), "and down as her next turn opens")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		23
	)


func test_the_power_stacks_onto_the_counter_bonus() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	_fire_power(state)
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(1, 0), 10, true
	)
	assert_eq(
		state.commander_of(1).attack_bonus(state, fight), 60, "20 passive + 40 from the power"
	)
