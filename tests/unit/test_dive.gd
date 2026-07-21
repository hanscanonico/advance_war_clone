extends GutTest
## The submarine's dive: the one mechanic that touches movement, targeting,
## vision and the save format at once.
##
## Each of those is a place the rule could be half-implemented and look fine. A
## dived boat that is still targetable is a sub with an expensive downside and no
## upside; one that is hidden but still counterattacks gives itself away for free;
## one that saves and reloads on the surface loses a match's worth of position.
## So each is asserted separately here rather than trusted to the one flag they
## all read.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


# --- the command --------------------------------------------------------------


## Diving is an ordinary turn: the boat repositions and goes under in one action,
## rather than spending a turn standing still to close a hatch.
func test_a_sub_dives_while_moving() -> void:
	var state := _state("[terrain]\nSSS\n[units]\n1 s 0 0")
	var sub := state.units[0]
	var command := DiveCommand.new(sub, _path([Vector2i(0, 0), Vector2i(1, 0)]), true)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(sub.dived)
	assert_eq(sub.cell, Vector2i(1, 0))
	assert_true(sub.acted)


func test_surfacing_is_the_same_command_the_other_way() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 0 0")
	var sub := state.units[0]
	sub.dived = true
	var command := DiveCommand.new(sub, _path([Vector2i(0, 0)]), false)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(sub.dived)


func test_dive_rejections() -> void:
	var state := _state("[terrain]\nSS\n..\n[units]\n1 s 0 0\n1 c 1 0\n1 t 0 1")
	var sub := state.units[0]
	assert_eq(
		DiveCommand.new(state.units[1], _path([Vector2i(1, 0)]), true).validate(state),
		"unit cannot dive",
		"a cruiser hunts submarines, it does not become one"
	)
	assert_eq(
		DiveCommand.new(state.units[2], _path([Vector2i(0, 1)]), true).validate(state),
		"unit cannot dive"
	)
	assert_eq(
		DiveCommand.new(sub, _path([Vector2i(0, 0)]), false).validate(state),
		"already on the surface"
	)
	sub.dived = true
	assert_eq(
		DiveCommand.new(sub, _path([Vector2i(0, 0)]), true).validate(state), "already submerged"
	)


# --- targeting ----------------------------------------------------------------


## Only a weapon built to hunt a submarine reaches one. That is the whole payoff
## of diving, and it has to hold in the command that validates the shot — the
## planner and the targeting overlay ask the same authority.
func test_only_a_hunter_can_engage_a_dived_sub() -> void:
	var state := _state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 B 0 0\n2 c 2 0")
	var sub := state.units[0]
	sub.dived = true
	EndTurnCommand.new().apply(state)  # blue's turn
	var battleship := state.units[1]
	var cruiser := state.units[2]
	assert_false(
		AttackRange.can_engage(state, battleship, sub), "a battleship's guns do not reach under"
	)
	assert_true(AttackRange.can_engage(state, cruiser, sub), "a cruiser is built for exactly this")
	assert_eq(
		AttackCommand.new(cruiser, _path([Vector2i(2, 0)]), Vector2i(1, 0)).validate(state), ""
	)


func test_surfacing_makes_the_sub_targetable_again() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 1 0\n2 B 0 0")
	var sub := state.units[0]
	var battleship := state.units[1]
	sub.dived = true
	assert_false(AttackRange.can_engage(state, battleship, sub))
	sub.dived = false
	assert_true(AttackRange.can_engage(state, battleship, sub))


## A boat that shot back would give itself away, so it does not — which is what
## makes attacking from under the water worth the fuel.
func test_a_dived_sub_does_not_counterattack() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 1 0\n2 c 0 0")
	state.rng.seed = 3
	var sub := state.units[0]
	sub.dived = true
	EndTurnCommand.new().apply(state)
	var result := CombatResolver.resolve(state, state.units[1], sub)
	assert_gt(result.attack_damage, 0, "the cruiser should have hit it")
	assert_false(result.countered)


## And the mirror: a submerged attacker is countered only by something that could
## have engaged it in the first place.
func test_only_a_hunter_counters_a_submerged_attacker() -> void:
	var state := _state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 B 0 0\n2 c 2 0")
	state.rng.seed = 3
	var sub := state.units[0]
	sub.dived = true
	var against_battleship := CombatResolver.resolve(state, sub, state.units[1])
	assert_false(
		against_battleship.countered, "a battleship cannot shoot back at what it cannot see"
	)
	sub.ammo = sub.type.max_ammo
	var against_cruiser := CombatResolver.resolve(state, sub, state.units[2])
	assert_true(against_cruiser.countered, "the escort can and does")


# --- vision -------------------------------------------------------------------


## Being under the water is not a question of how far anyone can see, so unlike
## every other hiding rule this one holds in a match with no fog at all.
func test_a_dived_sub_is_hidden_without_fog() -> void:
	var state := _state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	var sub := state.units[0]
	sub.dived = true
	assert_false(state.fog_enabled, "this is the clear-weather case on purpose")
	assert_true(Vision.is_hidden_from(state, 2, sub))
	assert_false(Vision.can_see_unit(state, 2, sub, Vision.visible_cells(state, 2)))
	assert_true(
		Vision.can_see_unit(state, 1, sub, Vision.visible_cells(state, 1)),
		"its own side always knows where it is"
	)


## Hunting a submarine means closing with it: standing next to one gives it up.
func test_an_adjacent_enemy_finds_a_dived_sub() -> void:
	var state := _state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 c 2 0")
	var sub := state.units[0]
	sub.dived = true
	assert_false(Vision.is_hidden_from(state, 2, sub), "the cruiser is right on top of it")
	MoveCommand.new(state.units[1], _path([Vector2i(2, 0)])).apply(state)
	assert_false(Vision.is_hidden_from(state, 2, sub))


func test_a_surfaced_sub_hides_from_nobody() -> void:
	var state := _state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	assert_false(Vision.is_hidden_from(state, 2, state.units[0]))


# --- fuel ---------------------------------------------------------------------


## Staying under costs several times what running on the surface does. That is
## the clock the whole mechanic is played against: hiding is safe and expensive.
func test_staying_under_burns_the_dived_rate() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 0 0")
	var sub := state.units[0]
	sub.dived = true
	assert_eq(sub.upkeep(), sub.type.dived_fuel_upkeep)
	assert_gt(sub.type.dived_fuel_upkeep, sub.type.fuel_upkeep, "a dive has to cost more than not")
	var before := sub.fuel
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(sub.fuel, before - sub.type.dived_fuel_upkeep)


func test_a_sub_that_stays_under_too_long_is_lost() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 0 0\n1 c 1 0")
	var sub := state.units[0]
	sub.dived = true
	sub.fuel = sub.type.dived_fuel_upkeep
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_false(sub in state.units, "an empty tank drowns a submarine like any other hull")


# --- saves --------------------------------------------------------------------


func test_a_dive_survives_a_save() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 0 0")
	state.map_path = "res://maps/the_straits.txt"
	state.units[0].dived = true
	var encoded := SaveCodec.encode(state, [2] as Array[int])
	# The map is reloaded from res:// on the way back in, so the round trip needs a
	# board that exists; the boat is placed onto it by the decode, not the map.
	var loaded := SaveCodec.decode(encoded, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_true(loaded.state.units[0].dived, "a submerged boat must not surface on load")


## A save written before the dive existed has no flag to read, and every boat in
## it was on the surface — which is exactly what the default gives.
func test_an_older_save_loads_with_every_boat_on_the_surface() -> void:
	var state := _state("[terrain]\nSS\n[units]\n1 s 0 0")
	state.map_path = "res://maps/the_straits.txt"
	var encoded := SaveCodec.encode(state, [] as Array[int])
	encoded["version"] = 2
	for entry: Dictionary in encoded["units"]:
		entry.erase("dived")
	var loaded := SaveCodec.decode(encoded, terrain_db, unit_db, chart)
	assert_not_null(loaded, "a version-2 save must still load")
	if loaded == null:
		return
	assert_false(loaded.state.units[0].dived)


# --- the whole thing at once ---------------------------------------------------


## A staged fleet action played out by both planners: the integration half, where
## the dive's four layers meet each other rather than a test fixture.
##
## The naval soak cannot cover this — it plays a real board, where whether anyone
## buys a submarine is up to production and the treasury. So the fleet is dealt
## here and only the fighting is emergent. The assertion that matters is the first
## one: a command the planner proposed and the rules then refused means two layers
## disagree, which is exactly how a half-applied targeting or vision rule shows up.
func test_a_staged_fleet_action_dives_and_stays_legal() -> void:
	var state := _state(
		"[terrain]\nSSSSSSSSSSSSSS\nSSSSSSSSSSSSSS\n[units]\n1 s 0 0\n1 B 0 1\n2 s 13 0\n2 B 13 1"
	)
	state.rng.seed = 77
	var ai := AIController.new(unit_db)
	var dives := 0
	var commands := 0
	for i in 600:
		if state.winner != 0 or state.day > 12:
			break
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				"day %d: the planner proposed a command the rules reject: %s" % [state.day, error]
			)
			return
		if command is DiveCommand:
			dives += 1
		command.apply(state)
		commands += 1
	gut.p("staged fleet action: %d commands, day %d, %d dives" % [commands, state.day, dives])
	assert_lt(commands, 600, "the match never progressed — the planner is probably looping")
	assert_gt(
		dives,
		0,
		(
			"two submarines spent twelve days under a battleship's guns and neither "
			+ "went under. The dive is either never scored or never legal."
		)
	)
