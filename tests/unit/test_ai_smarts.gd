extends GutTest
## The three Difficult-tier planner capabilities (plan DF3), each on a crafted
## state, each proved by the same board reaching a different command with the
## capability on than with it off.
##
## Almost every test builds its own profile rather than leaning on
## data/ai/hard.tres: these pin the *behaviour* of each smart, so retuning a
## shipped weight is a balance decision and never a test failure.
##
## The exception is deliberate. A capability suite where every test picks its own
## weight cannot notice a tier that ships a weight too small to do anything —
## which is exactly how Difficult shipped a kill-zone refusal that never refused
## anything. So one test loads the real Difficult profile and asserts the shipped
## configuration reaches the behaviour the tier claims.

const ARTILLERY_RING_BOARD := "[terrain]\n..........\n[units]\n1 t 0 0\n2 g 9 0"

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


func _profile() -> AIProfile:
	return AIProfile.new()  # every capability off; the Normal baseline


# --- S1 · threat awareness ----------------------------------------------------


## The flagship case. A tank walking at an enemy artillery ends its advance on
## the closest cell it can reach — which is inside the artillery's firing ring.
## With threat awareness on it gives up one tile and stops outside the ring.
##
## Exercised at 2.0, the value data/ai/hard.tres ships, because that is the
## claim: this dial is denominated in tiles precisely so a ladder-safe weight can
## still move a unit. The arithmetic is tight and worth spelling out — the shot
## forecasts 63 damage, so a tile costs 63/100 of the dial, and anything under
## ~1.6 leaves the tank inside the ring however confident the docs sound.
func test_advance_threat_tiles_keeps_a_tank_out_of_the_artillery_ring() -> void:
	var blind := AIController.new(unit_db, _profile())
	var blind_move := blind.plan_next_command(_state(ARTILLERY_RING_BOARD))
	assert_true(blind_move is MoveCommand, "expected an advance, got %s" % blind_move)
	var blind_path: Array[Vector2i] = (blind_move as MoveCommand).path
	assert_eq(
		blind_path[blind_path.size() - 1],
		Vector2i(6, 0),
		"the base planner spends its whole move, ending 3 tiles out — inside range 2-3"
	)

	var wary_profile := _profile()
	wary_profile.advance_threat_tiles = 2.0
	var wary_state := _state(ARTILLERY_RING_BOARD)
	var wary_move := AIController.new(unit_db, wary_profile).plan_next_command(wary_state)
	assert_true(wary_move is MoveCommand, "expected an advance, got %s" % wary_move)
	var wary_path: Array[Vector2i] = (wary_move as MoveCommand).path
	assert_eq(
		wary_path[wary_path.size() - 1],
		Vector2i(5, 0),
		"threat awareness gives up a tile to stop outside the artillery's reach"
	)
	assert_eq(wary_move.validate(wary_state), "", "a wary advance is still a legal move")


## The same board against the profile the game actually ships as Difficult, not
## a value invented for the test. The one above pins the capability; this pins
## the *configuration*, which is where the claim rotted last time — the tier
## shipped a weight that could not move a unit by a single tile, and every
## capability test passed anyway because each chose its own number.
func test_the_shipped_difficult_profile_refuses_the_artillery_ring() -> void:
	var hard: AIProfile = load("res://data/ai/hard.tres")
	assert_not_null(hard, "data/ai/hard.tres should load")
	var state := _state(ARTILLERY_RING_BOARD)
	var move := AIController.new(unit_db, hard).plan_next_command(state)
	assert_true(move is MoveCommand, "expected an advance, got %s" % move)
	var path: Array[Vector2i] = (move as MoveCommand).path
	assert_eq(
		path[path.size() - 1],
		Vector2i(5, 0),
		"Difficult as shipped must actually stop outside the ring, not merely intend to"
	)
	assert_eq(move.validate(state), "")


## The advance dial is denominated in tiles, so its scale is readable: at 1.0 a
## shot that would kill outright is worth exactly one tile of progress and no
## more. Pins the shape of the formula, which is the thing a retune must not
## quietly change.
func test_advance_threat_tiles_are_priced_in_tiles() -> void:
	# The artillery forecasts 63 damage, so a tile costs 0.63 of the dial.
	var timid := _profile()
	timid.advance_threat_tiles = 1.5  # 0.945 tiles: not quite enough to give one up
	var timid_move := AIController.new(unit_db, timid).plan_next_command(
		_state(ARTILLERY_RING_BOARD)
	)
	var timid_path: Array[Vector2i] = (timid_move as MoveCommand).path
	assert_eq(
		timid_path[timid_path.size() - 1],
		Vector2i(6, 0),
		"under one tile of aversion buys no tiles — the dial is not a veto"
	)

	var timider := _profile()
	timider.advance_threat_tiles = 1.6  # 1.008 tiles: just over the line
	var timider_move := AIController.new(unit_db, timider).plan_next_command(
		_state(ARTILLERY_RING_BOARD)
	)
	var timider_path: Array[Vector2i] = (timider_move as MoveCommand).path
	assert_eq(
		timider_path[timider_path.size() - 1], Vector2i(5, 0), "just over one tile buys one tile"
	)


## Lethality, not HP loss. The same shot on the same cell is a scratch to a fresh
## tank and certain death to a hurt one, and the dial has to read it that way
## round — a unit already down to its last points is the one that must give
## ground. Measured at a weight deliberately between the two: enough for the
## wounded tank, not enough for the healthy one, so the test fails if the penalty
## ever goes back to being a fraction of a full HP bar.
func test_a_wounded_unit_flinches_harder_than_a_healthy_one() -> void:
	var dial := _profile()
	dial.advance_threat_tiles = 1.2

	var healthy := _state(ARTILLERY_RING_BOARD)
	var healthy_move := AIController.new(unit_db, dial).plan_next_command(healthy)
	var healthy_path: Array[Vector2i] = (healthy_move as MoveCommand).path
	assert_eq(
		healthy_path[healthy_path.size() - 1],
		Vector2i(6, 0),
		"63 of a full 100 is worth 0.76 tiles at this dial — the fresh tank presses on"
	)

	var hurt := _state(ARTILLERY_RING_BOARD)
	hurt.units[0].hp = 49  # still above retreat_hp, so it is advancing, not fleeing
	var hurt_move := AIController.new(unit_db, dial).plan_next_command(hurt)
	assert_true(hurt_move is MoveCommand, "expected an advance, got %s" % hurt_move)
	var hurt_path: Array[Vector2i] = (hurt_move as MoveCommand).path
	assert_eq(
		hurt_path[hurt_path.size() - 1],
		Vector2i(5, 0),
		"the same shot takes every point it has left, so it is worth the whole dial"
	)
	assert_eq(hurt_move.validate(hurt), "")


## The two dials are independent: the attack-path one must not move an advancing
## unit, which is exactly the confusion that shipped a Difficult tier whose
## advance never flinched.
func test_the_attack_dial_does_not_steer_the_advance() -> void:
	var attack_only := _profile()
	attack_only.threat_aversion = 5.0
	var wary := AIController.new(unit_db, attack_only).plan_next_command(
		_state(ARTILLERY_RING_BOARD)
	)
	var blind := AIController.new(unit_db, _profile()).plan_next_command(
		_state(ARTILLERY_RING_BOARD)
	)
	assert_true(wary is MoveCommand and blind is MoveCommand)
	assert_eq(
		(wary as MoveCommand).path,
		(blind as MoveCommand).path,
		"threat_aversion prices shots, not steps"
	)


## Threat is a discount on the score, not a veto: a worthwhile attack still
## happens from a threatened cell. This is the R2 guard — an AI that refuses
## every trade and orbits is worse than one that loses.
func test_threat_aversion_still_takes_a_worthwhile_attack() -> void:
	var map_text := "[terrain]\n....\n[units]\n1 t 0 0\n2 g 1 0\n2 t 3 0"
	var wary_profile := _profile()
	wary_profile.threat_aversion = 0.5
	var state := _state(map_text)
	var command := AIController.new(unit_db, wary_profile).plan_next_command(state)
	assert_true(command is AttackCommand, "a profitable shot survives the threat discount")
	assert_eq((command as AttackCommand).target_cell, Vector2i(1, 0))
	assert_eq(command.validate(state), "")


## The threat map reads the board through the same authorities as everything
## else, so a unit that cannot be hurt at all registers no threat.
func test_an_unreachable_enemy_threatens_nothing() -> void:
	# Sea splits the board: the enemy tank can never reach the left half.
	var map_text := "[terrain]\n...S...\n[units]\n1 t 0 0\n2 t 6 0"
	var wary_profile := _profile()
	wary_profile.threat_aversion = 5.0
	wary_profile.advance_threat_tiles = 5.0
	var wary := AIController.new(unit_db, wary_profile).plan_next_command(_state(map_text))
	var blind := AIController.new(unit_db, _profile()).plan_next_command(_state(map_text))
	assert_true(wary is MoveCommand and blind is MoveCommand)
	assert_eq(
		(wary as MoveCommand).path,
		(blind as MoveCommand).path,
		"with nothing able to shoot us, threat awareness changes nothing"
	)


## The map measures a cell by standing the unit on it — the terrain it would move
## onto is exactly what changes the damage — and puts it straight back. The read
## is restored, so nothing about it may survive the call.
func test_measuring_a_cell_puts_the_unit_straight_back() -> void:
	var state := _state(ARTILLERY_RING_BOARD)
	var tank := state.units_of(1)[0]
	var origin := tank.cell
	var map := ThreatMap.build(state, state.units_of(2))
	assert_gt(
		map.incoming_damage(state, tank, Vector2i(7, 0)), 0, "the ring must actually threaten"
	)
	assert_eq(tank.cell, origin, "the measured unit is stood on the cell and put back")
	assert_eq(state.unit_at(origin), tank, "and the board still finds it where it was")


## The same guarantee across a whole Difficult turn on a real board: the sim
## changes when a command is *applied*, never while one is being planned. Guards
## the restored read above from anything a future capability adds beside it.
func test_planning_a_difficult_turn_leaves_the_board_untouched() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 7
	EndTurnCommand.new().apply(state)  # Blue, the AI side, is to move
	var ai := AIController.new(unit_db, DifficultyDB.load_default().by_id(&"hard").profile())
	var planned := 0
	for i in 60:
		var before := _board_snapshot(state)
		var command := ai.plan_next_command(state)
		assert_eq(_board_snapshot(state), before, "planning moved or hurt something")
		command.apply(state)
		planned += 1
		if command is EndTurnCommand:
			break
	assert_gt(planned, 3, "the reference turn should be more than a formality")


## Every unit's side, kind, position and HP, in the order the sim holds them.
func _board_snapshot(state: GameState) -> Array[String]:
	var rows: Array[String] = []
	for unit in state.units:
		rows.append("%d %s %s hp=%d" % [unit.team, unit.type.id, unit.cell, unit.hp])
	return rows


# --- S2 · focus fire ----------------------------------------------------------


## Two identical targets, both in reach of the acting tank. The far one is the
## one a second tank could also pile onto this turn; the near one nobody can
## follow up on. The base planner takes the near one because it is cheaper to
## reach; focus fire takes the one the team can finish together.
func test_focus_fire_picks_the_target_the_team_can_finish() -> void:
	var map_text := "[terrain]\n................\n[units]\n1 t 5 0\n1 t 15 0\n2 t 3 0\n2 t 8 0"

	var scattered := AIController.new(unit_db, _profile()).plan_next_command(_state(map_text))
	assert_true(scattered is AttackCommand, "expected an attack, got %s" % scattered)
	assert_eq(
		(scattered as AttackCommand).target_cell,
		Vector2i(3, 0),
		"the base planner takes the cheapest shot it can reach"
	)

	var focused_profile := _profile()
	focused_profile.focus_fire_bonus = 0.4
	var focused_state := _state(map_text)
	var focused := AIController.new(unit_db, focused_profile).plan_next_command(focused_state)
	assert_true(focused is AttackCommand, "expected an attack, got %s" % focused)
	assert_eq(
		(focused as AttackCommand).target_cell,
		Vector2i(8, 0),
		"focus fire prefers the target a second tank can still add damage to"
	)
	assert_eq(focused.validate(focused_state), "")


## A shot that already kills needs no follow-up, so focus fire must not inflate
## it — otherwise the AI would rate finished targets above fresh ones.
func test_focus_fire_adds_nothing_to_a_shot_that_already_kills() -> void:
	var map_text := "[terrain]\n....\n[units]\n1 t 0 0\n2 i 1 0\n2 i 3 0"
	var state := _state(map_text)
	state.units[1].hp = 10  # one shot finishes it
	var focused_profile := _profile()
	focused_profile.focus_fire_bonus = 5.0
	var command := AIController.new(unit_db, focused_profile).plan_next_command(state)
	assert_true(command is AttackCommand)
	assert_eq(
		(command as AttackCommand).target_cell, Vector2i(1, 0), "the kill is still the best shot"
	)


# --- S3 · counter-building ----------------------------------------------------


## An armour-heavy enemy roster with the heavy hammer priced out of reach. The
## static list buys the next thing on it; reactivity buys what the damage chart
## says actually hurts tanks.
func test_reactive_building_answers_an_armour_roster() -> void:
	var map_text := (
		"[terrain]\nB.......\n[owners]\n1 0 0\n"
		+ "[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0\n2 t 5 0\n2 t 6 0\n2 t 7 0"
	)

	var static_pick := _build_pick(map_text, _profile())
	assert_eq(
		static_pick, &"tank", "the static list buys the best thing on it that the funds allow"
	)

	var reactive_profile := _profile()
	reactive_profile.build_reactivity = 1.0
	assert_eq(
		_build_pick(map_text, reactive_profile),
		&"rockets",
		"against tank spam the chart's answer is rockets, which the list never names"
	)


## Reactivity re-ranks the buy; it never buys something the funds do not cover.
func test_reactive_building_still_respects_the_purse() -> void:
	var map_text := (
		"[terrain]\nB.......\n[owners]\n1 0 0\n"
		+ "[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0\n2 t 5 0\n2 t 6 0\n2 t 7 0"
	)
	var reactive_profile := _profile()
	reactive_profile.build_reactivity = 1.0
	var state := _state(map_text)
	state.funds[1] = 6500  # rockets and tank both out of reach
	for unit in state.units:
		unit.acted = true
	var command := AIController.new(unit_db, reactive_profile).plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	var built: UnitType = (command as BuildCommand).unit_type
	assert_lt(built.cost, 6500, "never buys what it cannot pay for")
	assert_eq(built.id, &"artillery", "the best affordable answer to armour")
	assert_eq(command.validate(state), "")


## Before contact there is no roster to answer, so reactivity must fall back to
## the order the profile already ships rather than picking off a table of zeroes.
func test_reactive_building_falls_back_to_the_list_with_no_enemy_seen() -> void:
	var map_text := "[terrain]\nB...\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0"
	var reactive_profile := _profile()
	reactive_profile.build_reactivity = 1.0
	assert_eq(
		_build_pick(map_text, reactive_profile),
		_build_pick(map_text, _profile()),
		"with no enemy in sight the static list decides, exactly as it always did"
	)


## Plans the one build the given profile makes on `map_text` with 15,000 in the
## bank — enough for everything but the md_tank, which is where counter-building
## has anything to say.
##
## Saving up is switched off because it would answer a different question: with
## the md_tank one turn of income out of reach, the planner would rightly bank
## rather than buy, and these tests pin *what* the team buys, not *when*.
func _build_pick(map_text: String, profile: AIProfile) -> StringName:
	var state := _state(map_text)
	profile.save_up_turns = 0
	state.funds[1] = 15000
	for unit in state.units:
		unit.acted = true
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	if not (command is BuildCommand):
		return &""
	assert_eq(command.validate(state), "")
	return (command as BuildCommand).unit_type.id


# --- the Normal pin -----------------------------------------------------------


## The guarantee the whole plan rests on: with every capability at its default,
## the planner produces the same commands it always did. Played out over a full
## AI turn on a real map, command for command, against a controller built from
## the shipped profile.
func test_capability_defaults_plan_exactly_like_the_shipped_profile() -> void:
	var shipped := _plan_a_turn(AIController.new(unit_db, AIProfile.load_default()))
	var defaults := _plan_a_turn(AIController.new(unit_db, AIProfile.new()))
	assert_gt(shipped.size(), 3, "the reference turn should be more than a formality")
	assert_eq(defaults, shipped, "profile defaults must plan a Normal turn command for command")


## Plays Blue's whole opening turn on first_steps and returns one string per
## command, which is what "identical planning" is checked on.
func _plan_a_turn(ai: AIController) -> Array[String]:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 7
	EndTurnCommand.new().apply(state)  # hand the turn to Blue, the AI side
	var log: Array[String] = []
	for i in 60:
		var command := ai.plan_next_command(state)
		log.append(_describe(command))
		command.apply(state)
		if command is EndTurnCommand:
			break
	return log


func _describe(command: Command) -> String:
	if command is AttackCommand:
		var attack := command as AttackCommand
		return "attack %s from %s" % [attack.target_cell, attack.path]
	if command is CaptureCommand:
		return "capture %s" % [(command as CaptureCommand).path]
	if command is MoveCommand:
		return "move %s" % [(command as MoveCommand).path]
	if command is BuildCommand:
		var build := command as BuildCommand
		return "build %s at %s" % [build.unit_type.id, build.cell]
	if command is PowerCommand:
		return "power"
	return "end turn"
