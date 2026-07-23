extends GutTest
## The two fields on CombatResult that exist for the battle cut-in and for
## nothing else (battle-animations plan D1).
##
## Split out of test_combat_resolver.gd because it is a different question. That
## file pins the *formula*; this one pins the record of what the formula was
## handed — the only part of the exchange the presentation layer is allowed to
## replay, and the only reason core/ knows the cut-in exists at all.
##
## Worth its own tests because a wrong snapshot is invisible in play: the cut-in
## would tick down from the wrong number and still look perfectly plausible.

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


## The animation is handed the result *after* the command applied, so both units
## already hold their post-combat HP. The snapshot is the only record of what
## they went in with.
func test_resolve_snapshots_the_hp_both_sides_went_in_with() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 11
	var attacker := state.units[0]
	var defender := state.units[1]
	attacker.hp = 55  # 6 displayed
	defender.hp = 74  # 8 displayed
	var result := CombatResolver.resolve(state, attacker, defender)
	assert_eq(result.attacker_hp_before, 6, "displayed HP, not internal")
	assert_eq(result.defender_hp_before, 8, "displayed HP, not internal")
	assert_lt(
		defender.displayed_hp(), result.defender_hp_before, "the unit itself has already moved on"
	)


## The one case with nothing left to read off the unit: a dead defender is gone
## from the state, so the cut-in's entire "this side was still standing a moment
## ago" comes from the snapshot.
func test_resolve_snapshots_survive_a_kill() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 7
	var defender := state.units[1]
	defender.hp = 10  # any hit kills
	var result := CombatResolver.resolve(state, state.units[0], defender)
	assert_true(result.defender_died)
	assert_eq(result.defender_hp_before, 1)
	assert_eq(result.attacker_hp_before, 10)
	assert_eq(defender.displayed_hp(), 0)


## The snapshot is taken off the Engagement the formula resolves, so it describes
## that exchange and no other. An indirect attack — no counter, no reply — still
## records both sides, because the cut-in stages both halves either way.
func test_resolve_snapshots_an_unanswered_volley() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 t 2 0")
	state.rng.seed = 3
	var attacker := state.units[0]
	attacker.hp = 41  # 5 displayed
	var result := CombatResolver.resolve(state, attacker, state.units[1])
	assert_false(result.countered)
	assert_eq(result.attacker_hp_before, 5)
	assert_eq(result.defender_hp_before, 10)
	assert_eq(attacker.displayed_hp(), 5, "nothing shot back, so the attacker is untouched")
