extends GutTest
## Tomas Reed: the infantry attack bonus, capture strength, and Popular Uprising.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, with_tomas: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if with_tomas:
		state.set_commander(1, commander_db.by_id(&"tomas_reed"))
	return state


func _fire_power(state: GameState) -> void:
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


# --- the doctrine ------------------------------------------------------------


## Mech vs Tank on plains, base 55: 55 * 1.15 * 0.9 = 56.925 -> 57, against
## 55 * 0.9 = 49.5 -> 50 flat.
func test_foot_units_hit_harder() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 m 0 0\n2 t 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		57
	)


## Tank vs Infantry on plains: 25 * 0.9 * 0.9 = 20.25 -> 20, against 23 flat.
func test_vehicles_hit_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		20
	)


## The plan's worked example: a 10-HP infantry chips 12 points, not 10.
func test_capture_chips_twenty_percent_harder() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	var infantry := state.units[0]
	assert_eq(CaptureCommand.capture_strength(state, infantry), 12)
	CaptureCommand.new(infantry, [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	assert_eq(state.capture_progress[Vector2i(1, 0)], GameState.CAPTURE_POINTS - 12)


## Rounded down, so a damaged unit does not quietly gain a point.
func test_the_capture_bonus_rounds_down() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	state.units[0].hp = 70  # 7 displayed: 7 * 120 / 100 = 8.4 -> 8
	assert_eq(CaptureCommand.capture_strength(state, state.units[0]), 8)


func test_a_neutral_commander_chips_its_displayed_hp() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0", false)
	assert_eq(CaptureCommand.capture_strength(state, state.units[0]), 10)


# --- Popular Uprising --------------------------------------------------------


## Uprising's +100 is percentage points on top of his standing +20, not a
## separate doubling — so 10 displayed HP chips 22, comfortably clearing the 20
## a fresh property is worth. The point of the power is the one-turn capture.
func test_the_power_takes_a_property_in_one_turn() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	_fire_power(state)
	assert_eq(CaptureCommand.capture_strength(state, state.units[0]), 22)
	CaptureCommand.new(state.units[0], [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	assert_eq(state.owner_at(Vector2i(1, 0)), 1, "captured outright")
	assert_false(state.capture_progress.has(Vector2i(1, 0)))


func test_the_power_moves_foot_units_only() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0\n1 t 0 1")
	var infantry := state.units[0]
	var tank := state.units[1]
	_fire_power(state)
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points + 1)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points)


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0")
	_fire_power(state)
	assert_eq(CaptureCommand.capture_strength(state, state.units[0]), 22)
	EndTurnCommand.new().apply(state)
	assert_eq(CaptureCommand.capture_strength(state, state.units[0]), 12, "back to the passive")
