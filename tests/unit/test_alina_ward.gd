extends GutTest
## Alina Ward: combined-arms adjacency, and Coordinated Push.

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
	state.set_commander(1, commander_db.by_id(&"alina_ward"))
	return state


func _damage(state: GameState, attacker: Unit, defender: Unit) -> int:
	return CombatResolver.forecast(state, attacker, attacker.cell, defender).attack_damage


# --- the doctrine ------------------------------------------------------------


## Tank alone on plains: 25 * 0.9 = 22.5 -> 23, the neutral number.
func test_a_lone_unit_gets_no_bonus() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[1]), 23)


## Same shot with a friendly Infantry (foot) beside the Tank (treads):
## 25 * 1.1 * 0.9 = 24.75 -> 25.
func test_a_neighbour_of_another_class_lifts_the_attack() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n1 i 0 1\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[2]), 25)


func test_a_neighbour_of_the_same_class_does_not() -> void:
	# Tank beside an APC: both treads, so the line is not actually mixed.
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n1 p 0 1\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[2]), 23)


## Infantry is foot and Mech is boot: four movement classes exist, and these
## two count as different even though both walk.
func test_infantry_and_mech_count_as_mixed() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 i 0 0\n1 m 0 1\n2 t 1 0")
	# infantry -> tank base 5: 5 * 1.1 * 0.9 = 4.95 -> 5, against 4.5 -> 5 flat.
	# Compare the hook directly, since the rounding hides it at this base damage.
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[2], Vector2i(1, 0), 10
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 10)


func test_an_enemy_neighbour_is_not_a_friendly_one() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n2 i 0 1\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[2]), 23)


## The bonus follows the cell the shot is fired *from*, not the cell the unit
## currently stands on — otherwise the damage preview would lie about a move.
func test_the_bonus_is_judged_from_the_planned_firing_cell() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n1 i 2 1\n2 i 2 0")
	var tank := state.units[0]
	var target := state.units[2]
	# Where it stands, at (0,0), it has no neighbours at all.
	assert_eq(CombatResolver.forecast(state, tank, Vector2i(0, 0), target).attack_damage, 23)
	# Previewing a shot from (1,1) puts the friendly infantry at (2,1) beside it,
	# and the preview has to say so before the move is committed.
	assert_eq(CombatResolver.forecast(state, tank, Vector2i(1, 1), target).attack_damage, 25)


# --- Coordinated Push --------------------------------------------------------


func test_the_power_lifts_attack_defence_and_movement() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n2 i 1 0")
	var tank := state.units[0]
	var base_budget := MovementResolver.move_budget(state, tank)
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	# 25 * 1.1 * 0.9 = 24.75 -> 25, the same lift the adjacency gives.
	assert_eq(_damage(state, tank, state.units[1]), 25, "attack")
	assert_eq(MovementResolver.move_budget(state, tank), base_budget + 1, "movement")
	# Blue infantry shooting back at a tank under Push: base 5, def 110, so
	# 5 * 1.0 * 0.9 * 0.9 = 4.05 -> 4, against 4.5 -> 5 without it.
	assert_eq(_damage(state, state.units[1], tank), 4, "defence")


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n2 i 1 0")
	var tank := state.units[0]
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points + 1)
	EndTurnCommand.new().apply(state)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points)
	assert_eq(_damage(state, tank, state.units[1]), 23, "back to the neutral number")


## Both halves of the doctrine stack: adjacency and the power are separate
## percentage points on the same attack.
func test_the_power_stacks_with_the_adjacency_bonus() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n1 i 0 1\n2 i 1 0")
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	# 25 * 1.2 * 0.9 = 27
	assert_eq(_damage(state, state.units[0], state.units[2]), 27)
