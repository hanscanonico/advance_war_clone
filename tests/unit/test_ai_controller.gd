extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var ai: AIController


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	ai = AIController.new(unit_db)


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func test_attacks_enemy_in_range() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 g 2 0")
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand, "expected an attack, got %s" % command)
	assert_eq((command as AttackCommand).target_cell, Vector2i(2, 0))
	assert_eq(command.validate(state), "")


func test_prefers_valuable_target() -> void:
	# both the infantry and the artillery are attackable; artillery is worth more
	var state := _state("[terrain]\n....\n[units]\n1 t 1 0\n2 i 0 0\n2 g 2 0")
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand)
	assert_eq((command as AttackCommand).target_cell, Vector2i(2, 0))


func test_captures_nearby_property() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand, "expected a capture, got %s" % command)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path[path.size() - 1], Vector2i(1, 0))
	assert_eq(command.validate(state), "")


func test_prefers_hq_over_city() -> void:
	var state := _state("[terrain]\nQC.\n[owners]\n2 0 0\n[units]\n1 i 2 0")
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path[path.size() - 1], Vector2i(0, 0), "the enemy HQ outranks a city")


func test_continues_capture_in_progress() -> void:
	var state := _state("[terrain]\nCC\n[units]\n1 i 0 0")
	state.capture_progress[Vector2i(0, 0)] = 10
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path, [Vector2i(0, 0)] as Array[Vector2i], "finish the capture underway")


func test_advances_when_out_of_reach() -> void:
	var state := _state("[terrain]\n............\n[units]\n1 t 0 0\n2 g 11 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(6, 0), "move the full 6 toward the enemy")


## A property only shelters a damaged unit if it can actually mend it, and repair
## needs the terrain to service the unit's domain. An airport repairs aircraft,
## never a tank, so a hurt tank whose team owns only an airport must not adopt it
## as a retreat goal — parked on tarmac that never heals, it is removed from play.
## With no servicing property it falls through and presses on toward the enemy.
func test_hurt_unit_will_not_retreat_to_a_property_that_cannot_repair_it() -> void:
	var state := _state("[terrain]\nA.................\n[owners]\n1 0 0\n[units]\n1 t 3 0\n2 t 16 0")
	state.units[0].hp = 40  # at or below retreat_hp, so it is fleeing, not advancing
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_gt(
		path[path.size() - 1].x,
		3,
		"an airport cannot repair a tank, so it is no refuge — the tank advances instead"
	)
	assert_eq(command.validate(state), "")


## The other half of the same rule: a city services land, so a hurt tank does
## retreat onto an owned one to be repaired. Guards the fix from over-correcting
## into never breaking off at all.
func test_hurt_unit_retreats_to_a_property_that_can_repair_it() -> void:
	var state := _state("[terrain]\nC.................\n[owners]\n1 0 0\n[units]\n1 t 3 0\n2 t 16 0")
	state.units[0].hp = 40
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a retreat, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(
		path[path.size() - 1],
		Vector2i(0, 0),
		"a city repairs land units, so the hurt tank falls back onto it"
	)
	assert_eq(command.validate(state), "")


func test_waits_when_isolated() -> void:
	var state := _state("[terrain]\nS.S.\nSSSS\n[units]\n1 t 1 0\n2 t 3 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand)
	assert_eq((command as MoveCommand).path, [Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(command.validate(state), "", "waiting in place is still a legal action")


func test_indirect_unit_backs_off_into_firing_range() -> void:
	# Artillery (range 2-3) pinned next to a tank can neither fire nor counter,
	# so it must reposition instead of waiting there forever.
	var state := _state("[terrain]\n......\n[units]\n1 g 1 0\n2 t 0 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a reposition, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(3, 0), "stand off at max range")
	assert_eq(command.validate(state), "")


func test_indirect_unit_closes_in_when_out_of_range() -> void:
	var state := _state("[terrain]\n..........\n[units]\n1 g 0 0\n2 t 9 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(5, 0), "spend the full 5 closing in")


func test_ends_turn_when_nothing_left() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	state.units[0].acted = true
	var command := ai.plan_next_command(state)
	assert_true(command is EndTurnCommand)


func test_full_turn_on_real_map_terminates_legally() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 7
	EndTurnCommand.new().apply(state)  # hand the turn to Blue, the AI side
	assert_eq(state.current_team, 2)
	var commands := 0
	var ended := false
	for i in 200:
		var command := ai.plan_next_command(state)
		assert_eq(
			command.validate(state),
			"",
			"AI produced an illegal command on iteration %d: %s" % [i, command]
		)
		command.apply(state)
		commands += 1
		if command is EndTurnCommand:
			ended = true
			break
	assert_true(ended, "AI must reach EndTurnCommand well under the cap")
	assert_lt(commands, 30, "one AI turn should be a handful of commands")
	assert_eq(state.current_team, 1)


# --- the submarine's one decision ---------------------------------------------

## A boat with something it can hit does that instead of hiding, so the dive is
## scored below an attack on purpose. These check the case where there is nothing
## worth shooting and something worth hiding from.


func test_a_sub_dives_from_something_it_cannot_answer() -> void:
	# Eight tiles off: inside a battleship's reach (move plus a six-tile gun),
	# outside the sub's own move-and-fire. A boat that could shoot would.
	var state := _state("[terrain]\nSSSSSSSSSSSS\n[units]\n1 s 0 0\n2 B 8 0")
	var command := ai.plan_next_command(state)
	assert_true(command is DiveCommand, "expected a dive, got %s" % command)
	assert_true((command as DiveCommand).submerge)
	assert_eq(command.validate(state), "")


## Diving from a cruiser is worse than facing it: the escort reaches under the
## water anyway, and a submerged boat gives up its counterattack doing it.
func test_a_sub_does_not_hide_from_its_hunter() -> void:
	var state := _state("[terrain]\nSSSSSSSS\n[units]\n1 s 0 0\n2 c 7 0")
	var command := ai.plan_next_command(state)
	assert_false(command is DiveCommand, "hiding from a cruiser buys nothing")


func test_a_sub_surfaces_once_the_threat_is_gone() -> void:
	var state := _state("[terrain]\nSSSSSS\n[units]\n1 s 0 0\n1 c 1 0")
	state.units[0].dived = true
	var command := ai.plan_next_command(state)
	assert_true(command is DiveCommand, "expected a surface, got %s" % command)
	assert_false((command as DiveCommand).submerge)


## Going under on the last of the tank would only mean surfacing again next turn
## for exactly that reason, and diving again the turn after. It stays up instead.
func test_a_sub_low_on_fuel_stays_up() -> void:
	var state := _state("[terrain]\nSSSSSSSSSSSS\n[units]\n1 s 0 0\n2 B 8 0")
	var sub := state.units[0]
	sub.fuel = sub.type.dived_fuel_upkeep + sub.type.move_points
	var command := ai.plan_next_command(state)
	assert_false(command is DiveCommand, "a boat this dry cannot afford to be under")


## The damage chart is optional on a GameState, so every question the planner
## asks of it is guarded — deciding whether to dive is a threat question, and a
## state that resolves no combat has no threats to weigh.
func test_planning_without_a_damage_chart_asks_the_chart_nothing() -> void:
	var map := MapData.parse("[terrain]\nSSSSSSSSSSSS\n[units]\n1 s 0 0\n2 B 8 0", terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	var command := ai.plan_next_command(state)
	assert_false(command is DiveCommand, "nothing known to be dangerous is worth hiding from")
	assert_eq(command.validate(state), "")
