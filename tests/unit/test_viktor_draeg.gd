extends GutTest
## Viktor Draeg: the armour bonus and the foot penalty that pays for it, and
## Armoured Breakthrough's star pierce.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, with_viktor: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if with_viktor:
		state.set_commander(1, commander_db.by_id(&"viktor_draeg"))
	return state


func _damage(state: GameState, attacker: Unit, defender: Unit) -> int:
	return CombatResolver.forecast(state, attacker, attacker.cell, defender).attack_damage


# --- the doctrine ------------------------------------------------------------


## Tank vs Infantry on plains: 25 * 1.15 * 0.9 = 25.875 -> 26, against 23 flat.
func test_tanks_hit_harder() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[1]), 26)


## Infantry vs Tank on plains: 5 * 0.9 * 0.9 = 4.05 -> 4, against 4.5 -> 5.
func test_foot_units_hit_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	assert_eq(_damage(state, state.units[0], state.units[1]), 4)


func test_everything_else_is_untouched() -> void:
	var map_text := "[terrain]\n..\n[units]\n1 r 0 0\n2 i 1 0"
	var neutral := _state(map_text, false)
	var viktor := _state(map_text)
	assert_eq(
		_damage(viktor, viktor.units[0], viktor.units[1]),
		_damage(neutral, neutral.units[0], neutral.units[1]),
		"Recon is neither armour nor foot"
	)


func test_the_doctrine_does_not_reach_the_other_side() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	# Blue has no commander, so its Tank shoots at the plain rate.
	# 55 * 1.0 * 0.9 = 49.5 -> 50; red's shoots at 55 * 1.15 * 0.9 = 56.925 -> 57.
	assert_eq(_damage(state, state.units[1], state.units[0]), 50, "blue: neutral")
	assert_eq(_damage(state, state.units[0], state.units[1]), 57, "red: Viktor")


# --- Armoured Breakthrough ---------------------------------------------------


func _fire_power(state: GameState) -> void:
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


## A city is 3 stars; Breakthrough makes the Tank fight it as 2.
##   plain:        25 * 1.15 * (1 - 0.3) = 20.125 -> 20
##   breakthrough: 25 * 1.15 * (1 - 0.2) = 23
func test_the_power_pierces_one_terrain_star() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 t 0 0\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[1]), 20)
	_fire_power(state)
	assert_eq(_damage(state, state.units[0], state.units[1]), 23)


func test_stars_clamp_at_zero() -> void:
	# A road has no cover to pierce, so the power is simply no gain there.
	var state := _state("[terrain]\n==\n[units]\n1 t 0 0\n2 i 1 0")
	var before := _damage(state, state.units[0], state.units[1])
	_fire_power(state)
	assert_eq(_damage(state, state.units[0], state.units[1]), before)


func test_the_power_moves_treads_only() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 t 0 0\n1 i 0 1")
	var tank := state.units[0]
	var infantry := state.units[1]
	_fire_power(state)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points + 1, "treads")
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points, "foot")


func test_foot_units_do_not_pierce_under_the_power() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 i 0 0\n2 i 1 0")
	var before := _damage(state, state.units[0], state.units[1])
	_fire_power(state)
	assert_eq(_damage(state, state.units[0], state.units[1]), before, "Breakthrough is armour only")


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n.C\n[units]\n1 t 0 0\n2 i 1 0")
	_fire_power(state)
	assert_eq(_damage(state, state.units[0], state.units[1]), 23)
	EndTurnCommand.new().apply(state)
	assert_eq(_damage(state, state.units[0], state.units[1]), 20, "back to the passive alone")
