extends GutTest
## The Aurora Compact three — Lyra Quill, Orin Flux and Cassian Rook — plus
## Cass Orlov, who shares their remaining hook needs. Grouped because between
## them they cover the last three things wave 2 added: the luck-range hooks, a
## power that reaches across the table, and HP-threshold targeting.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, commander: StringName) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if commander != &"":
		state.set_commander(1, commander_db.by_id(commander))
	return state


func _fire_power(state: GameState) -> void:
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


# --- Lyra Quill: the luck hooks ----------------------------------------------


## Her floor is 4, so a Tank that would roll 23-32 against Infantry rolls 27-32.
## Checked over many seeds rather than one, since the point is the range.
func test_her_luck_never_rolls_low() -> void:
	for seed_value in 40:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0", &"lyra_quill")
		state.rng.seed = seed_value
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		assert_between(result.attack_damage, 23 + 4, 23 + 9, "seed %d" % seed_value)


func test_her_units_are_slightly_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0", &"lyra_quill")
	# Tank into her Infantry: 25 * (200 - 95)/100 * 0.9 = 23.625 -> 24, against 23.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		24
	)


## Perfect Solution: maximum luck every time, plus +10% attack.
## 25 * 1.1 * 0.9 = 24.75 -> 25, and always +9.
func test_her_power_removes_the_roll() -> void:
	for seed_value in 10:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0", &"lyra_quill")
		state.rng.seed = seed_value
		_fire_power(state)
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		assert_eq(result.attack_damage, 25 + 9, "seed %d" % seed_value)


## Determinism still holds: a narrowed range must draw exactly one number from
## the seeded RNG, or a replay recorded on that seed falls out of step.
func test_a_narrowed_luck_range_stays_replayable() -> void:
	var damages: Array[int] = []
	for run in 2:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 t 1 0", &"lyra_quill")
		state.rng.seed = 99
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		damages.append(result.attack_damage)
		damages.append(result.counter_damage)
	assert_eq(damages[0], damages[2])
	assert_eq(damages[1], damages[3])


# --- Orin Flux: reaching across the table ------------------------------------


func test_his_scouts_see_further() -> void:
	var state := _state("[terrain]\n......\n......\n[units]\n1 r 0 0", &"orin_flux")
	state.fog_enabled = true
	var visible := Vision.visible_cells(state, 1)
	# Recon sees 5 tiles of Manhattan reach; his sees 6.
	assert_true(visible.has(Vector2i(5, 1)), "his Recon reaches 6")
	var neutral := _state("[terrain]\n......\n......\n[units]\n1 r 0 0", &"")
	neutral.fog_enabled = true
	assert_false(Vision.visible_cells(neutral, 1).has(Vector2i(5, 1)), "an ordinary one does not")


func test_signal_jam_strips_enemy_fuel_and_ammo() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 r 0 0\n2 t 2 0", &"orin_flux")
	var enemy := state.units[1]
	var friendly := state.units[0]
	var friendly_fuel := friendly.fuel
	enemy.ammo = 5
	_fire_power(state)
	assert_eq(enemy.fuel, enemy.type.max_fuel - 10, "10 fuel gone")
	assert_eq(enemy.ammo, 4, "and one shell")
	assert_eq(friendly.fuel, friendly_fuel, "his own army is untouched")


func test_signal_jam_shortens_enemy_vision() -> void:
	var state := _state("[terrain]\n......\n......\n[units]\n1 r 0 0\n2 r 5 1", &"orin_flux")
	state.fog_enabled = true
	var far := Vector2i(1, 1)  # 4 + 0 = Manhattan 4 from the enemy recon at (5,1)
	assert_true(Vision.visible_cells(state, 2).has(far), "recon sees 5")
	_fire_power(state)
	assert_true(state.power_active(1))
	var jammed := Vision.visible_cells(state, 2)
	assert_true(jammed.has(Vector2i(2, 1)), "still sees 4")
	assert_false(jammed.has(Vector2i(0, 1)), "but no longer 5")


## ROUND duration, so "until their next turn" means it is still up while the
## opponent actually plays.
func test_signal_jam_lasts_through_the_opponents_turn() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 r 0 0\n2 t 2 0", &"orin_flux")
	_fire_power(state)
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "still jamming while blue plays")
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1))


# --- Cassian Rook: movement ---------------------------------------------------


func test_his_light_units_are_faster_and_his_heavy_ones_softer() -> void:
	var state := _state(
		"[terrain]\n....\n....\n[units]\n1 r 0 0\n1 t 0 1\n2 i 3 0", &"cassian_rook"
	)
	var recon := state.units[0]
	var tank := state.units[1]
	assert_eq(MovementResolver.move_budget(state, recon), recon.type.move_points + 1)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points, "treads unchanged")
	# Tank vs Infantry: 25 * 0.9 * 0.9 = 20.25 -> 20, against 23.
	assert_eq(
		CombatResolver.forecast(state, tank, Vector2i(0, 1), state.units[2]).attack_damage, 20
	)


## Rapid Redeployment moves everything and costs the turn's damage to do it.
func test_his_power_trades_damage_for_movement() -> void:
	var state := _state(
		"[terrain]\n....\n....\n[units]\n1 r 0 0\n1 t 0 1\n2 i 3 0", &"cassian_rook"
	)
	var recon := state.units[0]
	var tank := state.units[1]
	_fire_power(state)
	assert_eq(MovementResolver.move_budget(state, recon), recon.type.move_points + 3, "1 + 2")
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points + 2)
	# Tank now at -30 total: 25 * 0.7 * 0.9 = 15.75 -> 16.
	assert_eq(
		CombatResolver.forecast(state, tank, Vector2i(0, 1), state.units[2]).attack_damage, 16
	)


# --- Cass Orlov: HP-threshold targeting ---------------------------------------


func test_she_hits_nearly_dead_units_harder() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", &"cass_orlov")
	var target := state.units[1]
	# Healthy: no bonus. 25 * 0.9 = 22.5 -> 23.
	assert_eq(
		CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), target).attack_damage, 23
	)
	target.hp = 50  # 5 displayed: inside her threshold
	# 25 * 1.15 * (1 - 0.1 * 1 * 0.5) = 27.3125 -> 27
	assert_eq(
		CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), target).attack_damage, 27
	)


func test_her_own_units_are_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0", &"cass_orlov")
	# Tank into her Infantry: 25 * (200 - 90)/100 * 0.9 = 24.75 -> 25, against 23.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		25
	)


## No Escape widens "damaged" from nearly-dead to anything short of full.
func test_her_power_widens_what_counts_as_damaged() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", &"cass_orlov")
	var target := state.units[1]
	target.hp = 90  # 9 displayed: outside the passive, inside the power
	var fight := Engagement.create(state.units[0], Vector2i(0, 0), 10, target, Vector2i(1, 0), 9)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 0, "passive needs 5 HP or less")
	_fire_power(state)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 30)
