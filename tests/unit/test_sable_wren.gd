extends GutTest
## Sable Wren, and with her the reworked Vanish (D4) — the one doctrine that
## makes seeing a cell and seeing the unit on it different questions.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, with_sable: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if with_sable:
		state.set_commander(1, commander_db.by_id(&"sable_wren"))
	return state


func _fire_power(state: GameState) -> void:
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


# --- the doctrine ------------------------------------------------------------


## Woods are 2 stars; hers count as 3. Tank vs Infantry in woods:
## 25 * (1 - 0.3) = 17.5 -> 18, against 25 * 0.8 = 20.
func test_her_units_get_an_extra_star_in_woods() -> void:
	var state := _state("[terrain]\n.F\n[units]\n2 t 0 0\n1 i 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		18
	)


## Roads have no cover to begin with, so the penalty is pure downside:
## 25 * (200 - 90)/100 = 27.5 -> 28, against 25 flat.
func test_her_units_are_softer_on_roads() -> void:
	var state := _state("[terrain]\n==\n[units]\n2 t 0 0\n1 i 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		28
	)


func test_open_ground_is_untouched() -> void:
	var map_text := "[terrain]\n..\n[units]\n2 t 0 0\n1 i 1 0"
	var sable := _state(map_text)
	var neutral := _state(map_text, false)
	assert_eq(
		(
			CombatResolver
			. forecast(sable, sable.units[0], Vector2i(0, 0), sable.units[1])
			. attack_damage
		),
		(
			CombatResolver
			. forecast(neutral, neutral.units[0], Vector2i(0, 0), neutral.units[1])
			. attack_damage
		)
	)


# --- Vanish ------------------------------------------------------------------


## The rework, and the reason for it. Woods already hide a unit from anyone more
## than a tile away, for every commander — so the original wording was a no-op
## and only hiding from an *adjacent* enemy is a real effect.
func test_woods_already_hide_from_range_for_everyone() -> void:
	var state := _state("[terrain]\n..F\n...\n[units]\n1 i 2 0\n2 t 0 0", false)
	state.fog_enabled = true
	var visible := Vision.visible_cells(state, 2)
	assert_false(visible.has(Vector2i(2, 0)), "two tiles away and in woods: already hidden")


func test_vanish_hides_her_woods_units_from_an_adjacent_enemy() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	var hidden := state.units[0]
	var visible := Vision.visible_cells(state, 2)
	assert_true(visible.has(Vector2i(1, 0)), "adjacent, so the cell itself is seen")
	assert_true(Vision.can_see_unit(state, 2, hidden, visible), "and normally so is she")

	_fire_power(state)
	visible = Vision.visible_cells(state, 2)
	assert_true(visible.has(Vector2i(1, 0)), "the cell is still visible")
	assert_false(Vision.can_see_unit(state, 2, hidden, visible), "but the unit on it is not")


func test_vanish_does_not_hide_her_units_in_the_open() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	_fire_power(state)
	var visible := Vision.visible_cells(state, 2)
	assert_true(Vision.can_see_unit(state, 2, state.units[0], visible), "no cover, no ambush")


func test_she_can_always_see_her_own_hidden_units() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	_fire_power(state)
	var visible := Vision.visible_cells(state, 1)
	assert_true(Vision.can_see_unit(state, 1, state.units[0], visible))


## Fog off means nothing is hidden from anyone, power or not.
func test_vanish_does_nothing_without_fog() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	_fire_power(state)
	var visible := Vision.visible_cells(state, 2)
	assert_true(Vision.can_see_unit(state, 2, state.units[0], visible))


## The ambush half: attacking out of cover while the power runs.
## Infantry vs Tank from woods, base 5: 5 * 1.4 * 0.9 = 6.3 -> 6, against 5.
func test_the_ambush_bonus_applies_from_woods() -> void:
	var state := _state("[terrain]\nF.\n[units]\n1 i 0 0\n2 t 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		5
	)
	_fire_power(state)
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		6
	)


func test_the_ambush_bonus_does_not_apply_from_open_ground() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	_fire_power(state)
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(1, 0), 10
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 0)


## ROUND, like Hold the Line: an ambush that expired at the end of her own turn
## would never be there when the opponent walked into it.
func test_vanish_covers_the_opponents_turn() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	_fire_power(state)
	EndTurnCommand.new().apply(state)
	var visible := Vision.visible_cells(state, 2)
	assert_false(
		Vision.can_see_unit(state, 2, state.units[0], visible), "still hidden on blue's turn"
	)
	EndTurnCommand.new().apply(state)
	visible = Vision.visible_cells(state, 2)
	assert_true(Vision.can_see_unit(state, 2, state.units[0], visible), "and back as hers opens")
