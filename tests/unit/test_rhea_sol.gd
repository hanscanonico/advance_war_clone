extends GutTest
## Rhea Sol, and with her the R3 guard: rules, AI and UI must agree on how far
## an indirect unit can shoot once a doctrine has moved the answer.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, with_rhea: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if with_rhea:
		state.set_commander(1, commander_db.by_id(&"rhea_sol"))
	return state


func _fire_power(state: GameState) -> void:
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


# --- the doctrine ------------------------------------------------------------


## Artillery vs Infantry on plains, base 90: 90 * 1.1 * 0.9 = 89.1 -> 89,
## against 90 * 0.9 = 81 flat.
func test_indirect_units_hit_harder() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 i 2 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		89
	)


## Tank vs Artillery on plains, base 70: her guns take 70 * 0.9 * 1.1 = 69.3
## -> 69, against 70 * 0.9 = 63 flat.
func test_indirect_units_are_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 g 0 0\n2 t 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		69
	)


func test_direct_units_are_untouched() -> void:
	var map_text := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
	var neutral := _state(map_text, false)
	var rhea := _state(map_text)
	assert_eq(
		CombatResolver.forecast(rhea, rhea.units[0], Vector2i(0, 0), rhea.units[1]).attack_damage,
		(
			CombatResolver
			. forecast(neutral, neutral.units[0], Vector2i(0, 0), neutral.units[1])
			. attack_damage
		)
	)


# --- Grid Saturation, and the shared range helper ----------------------------


## Artillery is range 2-3. The power takes it to 4 — and the command, the AI and
## the targeting overlay all have to agree, which is why they share AttackRange.
func test_the_power_extends_the_firing_range() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 i 4 0")
	var artillery := state.units[0]
	assert_eq(AttackRange.maximum(state, artillery), 3)
	assert_false(AttackRange.covers(state, artillery, artillery.cell, Vector2i(4, 0)))
	var before := AttackCommand.new(artillery, [artillery.cell], Vector2i(4, 0))
	assert_eq(before.validate(state), "target out of range")

	_fire_power(state)
	assert_eq(AttackRange.maximum(state, artillery), 4)
	assert_true(AttackRange.covers(state, artillery, artillery.cell, Vector2i(4, 0)))
	assert_eq(AttackCommand.new(artillery, [artillery.cell], Vector2i(4, 0)).validate(state), "")


func test_the_minimum_range_is_not_moved() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 i 1 0")
	_fire_power(state)
	assert_eq(AttackRange.minimum(state, state.units[0]), 2, "the dead zone stays")
	assert_eq(
		AttackCommand.new(state.units[0], [state.units[0].cell], Vector2i(1, 0)).validate(state),
		"target out of range"
	)


func test_direct_units_gain_no_range() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 t 0 0\n2 i 2 0")
	_fire_power(state)
	assert_eq(AttackRange.maximum(state, state.units[0]), 1)


func test_an_unarmed_unit_never_gains_a_weapon() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n2 i 1 0")
	_fire_power(state)
	assert_eq(AttackRange.maximum(state, state.units[0]), 0)
	assert_false(AttackRange.covers(state, state.units[0], Vector2i(0, 0), Vector2i(1, 0)))


## The AI finds the extended shot, because its target search asks the same
## helper the command does.
func test_the_ai_takes_the_extended_shot() -> void:
	var state := _state("[terrain]\n.....\n.....\n[units]\n1 g 0 0\n2 i 4 0")
	_fire_power(state)
	var ai := AIController.new(unit_db)
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand, "expected an attack, got %s" % command)
	assert_eq((command as AttackCommand).target_cell, Vector2i(4, 0))


## The extra reach must not turn a siege gun into something that shoots back:
## countering is adjacency, whatever a doctrine does to firing range.
func test_the_power_does_not_let_indirects_counter() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 t 1 0")
	_fire_power(state)
	state.rng.seed = 3
	var result := CombatResolver.resolve(state, state.units[1], state.units[0])
	assert_gt(result.attack_damage, 0)
	assert_false(result.countered, "artillery still never counters")


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 i 4 0")
	_fire_power(state)
	assert_eq(AttackRange.maximum(state, state.units[0]), 4)
	EndTurnCommand.new().apply(state)
	assert_eq(AttackRange.maximum(state, state.units[0]), 3)
