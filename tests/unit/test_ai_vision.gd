extends GutTest
## The single exception to the AI's omniscience: a unit a doctrine has hidden.
##
## The planner sees the whole board on purpose — an openly-cheating opponent
## rather than a guessing one — and that stays true for terrain, range and
## property sight. Sable Wren's Vanish is the one visibility rule that is a
## *power* rather than a fact about the map, and an invisibility power that the
## computer opponent ignores is inert in the only match most people play. So the
## planner asks Vision.is_hidden_from, and nothing else.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


## Team 2 plays Sable Wren and hides in woods; team 1 is the AI hunting them.
func _state(map_text: String, fog: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.fog_enabled = fog
	state.set_commander(2, commander_db.by_id(&"sable_wren"))
	return state


func _vanish(state: GameState) -> void:
	state.add_charge(2, state.commander_of(2).power_cost)
	var command := PowerCommand.new()
	state.current_team = 2
	assert_eq(command.validate(state), "")
	command.apply(state)
	state.current_team = 1


# --- Vision.is_hidden_from ---------------------------------------------------


func test_only_a_doctrine_hides_a_unit_from_the_question() -> void:
	var state := _state("[terrain]\n.F\n[units]\n1 t 0 0\n2 i 1 0")
	var hidden := state.units[1]
	assert_false(Vision.is_hidden_from(state, 1, hidden), "no power running, nothing hidden")
	_vanish(state)
	assert_true(Vision.is_hidden_from(state, 1, hidden), "Vanish hides it, even from adjacent")


## Terrain is not the AI's problem: an ordinary unit in woods stays visible to
## this question, which is what keeps the exception narrow.
func test_woods_alone_do_not_hide_a_unit_from_the_question() -> void:
	var state := _state("[terrain]\n..F\n[units]\n1 t 0 0\n2 i 2 0")
	assert_false(Vision.is_hidden_from(state, 1, state.units[1]))


func test_a_commander_never_hides_from_their_own_side() -> void:
	var state := _state("[terrain]\n.F\n[units]\n2 t 0 0\n2 i 1 0")
	_vanish(state)
	assert_false(Vision.is_hidden_from(state, 2, state.units[1]))


func test_nothing_is_hidden_without_fog() -> void:
	var state := _state("[terrain]\n.F\n[units]\n1 t 0 0\n2 i 1 0", false)
	_vanish(state)
	assert_false(Vision.is_hidden_from(state, 1, state.units[1]), "Vanish is a fog rule")


# --- the planner respects it -------------------------------------------------


## Adjacent and one hit from dead — the attack the planner always takes — and
## the AI leaves it alone once it cannot see it. The target is wounded on
## purpose: a Tank turns down a *healthy* Infantry anyway, because the counter
## risk against 7000 of tank outweighs 1000 of infantry, and a sanity check has
## to be an attack the planner would really make.
func test_the_planner_does_not_attack_what_it_cannot_see() -> void:
	var state := _state("[terrain]\n.F\n[units]\n1 t 0 0\n2 i 1 0")
	state.units[1].hp = 20
	var plain := AIController.new(unit_db).plan_next_command(state)
	assert_true(plain is AttackCommand, "sanity: it finishes an infantry it can see")
	_vanish(state)
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_false(command is AttackCommand, "a vanished unit is not a target")


## The other half: a hidden unit stops being something to walk toward, so the AI
## does not home in on a position it is not supposed to know about.
func test_the_planner_does_not_advance_on_what_it_cannot_see() -> void:
	var line := ".".repeat(8)
	var state := _state("[terrain]\n%s\n%sF\n[units]\n1 i 0 0\n2 i 8 1" % [line + ".", line])
	_vanish(state)
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_true(command is MoveCommand, "it still acts")
	var move := command as MoveCommand
	assert_eq(move.path[move.path.size() - 1], Vector2i(0, 0), "with nothing to walk toward")


## An unhidden enemy is still tracked with the power running, so the exception
## really is per unit rather than "fog on, planner blinded". One of her infantry
## is in woods and one is in the open; only the second is a target.
func test_the_planner_still_sees_units_outside_cover() -> void:
	var state := _state("[terrain]\n...\nF..\n[units]\n1 t 0 0\n2 i 0 1\n2 i 2 0")
	state.units[1].hp = 20
	state.units[2].hp = 20
	_vanish(state)
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_true(command is AttackCommand, "the one in the open is still fair game")
	assert_eq((command as AttackCommand).target_cell, Vector2i(2, 0), "not the one in cover")


## The wedge case: every enemy hidden must still leave the planner able to
## finish a turn rather than loop on a command it cannot make legal.
func test_a_wholly_hidden_enemy_army_does_not_wedge_the_planner() -> void:
	var state := _state("[terrain]\n.F\n[units]\n1 t 0 0\n2 i 1 0")
	_vanish(state)
	var ai := AIController.new(unit_db)
	var commands := 0
	while commands < 50:
		var command := ai.plan_next_command(state)
		assert_eq(command.validate(state), "", "planner proposed a rejected command")
		command.apply(state)
		commands += 1
		if command is EndTurnCommand:
			return
	fail_test("the planner never reached the end of its turn")


## And it never tries to walk onto the hidden unit: the AI does not know it is
## there, but the movement rules do, so a plan that ignored it would be illegal.
func test_the_planner_never_moves_onto_a_hidden_unit() -> void:
	var state := _state("[terrain]\n.F.\n[units]\n1 t 0 0\n2 i 1 0")
	_vanish(state)
	var ai := AIController.new(unit_db)
	for i in 20:
		var command := ai.plan_next_command(state)
		assert_eq(command.validate(state), "", "planner proposed a rejected command")
		command.apply(state)
		if command is EndTurnCommand:
			break
	assert_eq(state.unit_at(Vector2i(1, 0)), state.units[1], "the hidden unit still holds its cell")
