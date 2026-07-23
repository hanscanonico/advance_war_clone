extends GutTest
## Fog ambush: a unit plans its move with only what its side can see, so an enemy
## it cannot see — fogged, or a dived sub it is not standing next to — is planned
## through as if the cell were empty. The trap springs on commit: GameState
## .advance_unit cuts the move short at the last free cell before the hidden unit,
## still spends the turn, and any follow-on bound to the move (attack, capture, …)
## is dropped. No RNG anywhere: the whole mechanic is deterministic.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String, fog: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	assert_not_null(map, "test map should parse")
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state, "test state should build")
	state.fog_enabled = fog
	return state


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


## Fires Sable Wren's Vanish for team 2, the doctrine that hides a unit even from
## an adjacent viewer — a hidden enemy whose position does not depend on distance.
func _vanish(state: GameState) -> void:
	state.set_commander(2, CommanderDB.load_default().by_id(&"sable_wren"))
	state.add_charge(2, state.commander_of(2).power_cost)
	state.current_team = 2
	assert_eq(PowerCommand.new().validate(state), "")
	PowerCommand.new().apply(state)
	state.current_team = 1


# --- reachability plans with the mover's knowledge ---------------------------


## An enemy the mover cannot see is planned through as if the cell were empty, so
## the movement overlay no longer has an unexplained hole where it stands.
func test_reachable_includes_a_fogged_enemy_cell() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 3 0")
	var far := state.units[1]
	assert_false(
		Vision.can_see_unit(state, 1, far, Vision.visible_cells(state, 1)),
		"the enemy three tiles off is outside infantry vision, so it is fogged"
	)
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_true(reach.has(Vector2i(3, 0)), "the fogged enemy's cell is reachable")
	assert_true(reach.can_stop_at(Vector2i(3, 0)), "and looks like a place to stop")


## A visible enemy is a wall exactly as before — the fog-aware rule only frees the
## ones the mover has no way to know about.
func test_reachable_excludes_a_visible_enemy_cell() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0\n2 i 2 0")
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_true(reach.has(Vector2i(1, 0)))
	assert_false(reach.has(Vector2i(2, 0)), "the enemy two tiles off is in sight and blocks")
	assert_false(reach.has(Vector2i(3, 0)), "and cannot be passed through")


# --- the trap springs on commit ----------------------------------------------


func test_a_move_is_cut_short_at_the_hidden_enemy() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 3 0")
	var mover := state.units[0]
	var command := MoveCommand.new(
		mover, _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	)
	assert_eq(
		command.validate(state), "", "a hidden occupant must not be refused — that is the probe"
	)
	command.apply(state)
	assert_true(command.ambushed, "walking onto a hidden enemy springs the trap")
	assert_eq(mover.cell, Vector2i(2, 0), "the unit stops on the last free cell before it")
	assert_true(mover.acted, "and its turn is spent")
	assert_eq(mover.fuel, mover.type.max_fuel - 2, "fuel is charged only for the two steps taken")


func test_the_attack_bound_to_an_ambushed_move_is_aborted() -> void:
	# The path stops on a hidden enemy at (3, 0); a second enemy at (3, 1) is the
	# shot it lined up. The move is cut short, so the shot never fires.
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0\n2 i 3 0\n2 i 3 1")
	var mover := state.units[0]
	var obstacle := state.units[1]
	var target := state.units[2]
	var command := AttackCommand.new(
		mover,
		_path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]),
		Vector2i(3, 1)
	)
	assert_eq(command.validate(state), "", "the shot is legal on paper, from the intended cell")
	command.apply(state)
	assert_true(command.ambushed)
	assert_null(command.result, "no combat was resolved")
	assert_eq(mover.cell, Vector2i(2, 0), "the attacker stopped short")
	assert_eq(target.hp, 100, "the target is untouched")
	assert_eq(obstacle.hp, 100, "and so is the hidden unit that stopped it")


func test_a_friendly_on_the_path_is_not_an_ambush() -> void:
	# Passing through a friendly is legal and never a trap: the move runs its full
	# length and nothing is cut short.
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0", false)
	var mover := state.units[0]
	var command := MoveCommand.new(mover, _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(command.ambushed)
	assert_eq(mover.cell, Vector2i(2, 0), "it passes the friendly and reaches its cell")


func test_a_capture_bound_to_an_ambushed_move_is_aborted() -> void:
	# A doctrine-cloaked enemy (hidden in woods by Vanish) sits between the
	# infantry and the city it means to take. The mover plans through it, is
	# stopped on commit, and the capture it lined up never begins.
	var state := _state("[terrain]\n.FC\n[units]\n1 i 0 0\n2 i 1 0")
	_vanish(state)
	var mover := state.units[0]
	var command := CaptureCommand.new(
		mover, _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_eq(mover.cell, Vector2i(0, 0), "stopped before the cloaked enemy at (1, 0)")
	assert_false(state.capture_progress.has(Vector2i(2, 0)), "no capture was begun")


# --- a dived submarine, fog or no fog -----------------------------------------


## The adjacency reveal is untouched: a mover standing next to a dived sub sees
## it, so it walls — the same rule that already lets an escort hunt one down.
func test_an_adjacent_dived_sub_still_blocks() -> void:
	var state := _state("[terrain]\nSSS\n[units]\n1 s 0 0\n2 s 1 0", false)
	state.units[1].dived = true
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_false(reach.has(Vector2i(1, 0)), "the boat right beside it gives it away, so it walls")


## A dived sub the mover is not next to is hidden — and now free to plan through —
## even with fog off, because being under the water is not a question of sight.
func test_a_distant_dived_sub_is_planned_through() -> void:
	var state := _state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 s 2 0", false)
	state.units[1].dived = true
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_true(reach.has(Vector2i(2, 0)), "two tiles off it is hidden, so its cell plans free")
	assert_true(reach.can_stop_at(Vector2i(2, 0)))
