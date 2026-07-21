extends GutTest
## The difficulty tier seam (plan DF1): the three tiers load, Normal is the
## shipped AI bit for bit, an unknown id still plays, and the wiring is not inert
## — Easy's profile must provably reach a different command than Normal's.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var db: DifficultyDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	db = DifficultyDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func test_the_three_tiers_load() -> void:
	assert_eq(db.size(), 3, "data/difficulty should hold easy, normal and hard")
	for id: StringName in [&"easy", &"normal", &"hard"]:
		assert_true(db.has(id), "missing difficulty tier '%s'" % id)
		assert_not_null(db.by_id(id).ai_profile, "tier '%s' has no AI profile" % id)


func test_tiers_are_listed_gentlest_first() -> void:
	var ids: Array[StringName] = []
	for tier in db.all():
		ids.append(tier.id)
	assert_eq(ids, [&"easy", &"normal", &"hard"] as Array[StringName])


func test_difficult_is_the_label_for_the_hard_id() -> void:
	# The UI says "Difficult"; the id stays short for flags and saves.
	assert_eq(db.by_id(&"hard").display_name, "Difficult")


## The pin that keeps Normal honest: it is the planner's own defaults, so a
## same-seed replay of an existing match stays identical. A new weight added to
## AIProfile without a default of "off" fails here, which is the point.
func test_normal_is_the_planner_defaults() -> void:
	var normal := db.by_id(&"normal").profile()
	var defaults := AIProfile.new()
	assert_almost_eq(normal.kill_bonus, defaults.kill_bonus, 0.0001)
	assert_almost_eq(normal.counter_weight, defaults.counter_weight, 0.0001)
	assert_almost_eq(normal.capture_score, defaults.capture_score, 0.0001)
	assert_almost_eq(normal.hq_capture_multiplier, defaults.hq_capture_multiplier, 0.0001)
	assert_almost_eq(normal.capture_progress_bonus, defaults.capture_progress_bonus, 0.0001)
	assert_almost_eq(normal.step_cost_penalty, defaults.step_cost_penalty, 0.0001)
	assert_almost_eq(normal.min_useful_score, defaults.min_useful_score, 0.0001)
	assert_almost_eq(normal.advance_score, defaults.advance_score, 0.0001)
	assert_eq(normal.retreat_hp, defaults.retreat_hp)
	assert_eq(normal.capture_unit_target, defaults.capture_unit_target)
	assert_eq(normal.build_priority, defaults.build_priority)


## Every Difficult-tier capability is off at Normal, so none of that code runs on
## the tier the game has always shipped.
func test_normal_leaves_every_capability_off() -> void:
	var normal := db.by_id(&"normal").profile()
	assert_almost_eq(normal.threat_aversion, 0.0, 0.0001)
	assert_almost_eq(normal.advance_threat_tiles, 0.0, 0.0001)
	assert_almost_eq(normal.focus_fire_bonus, 0.0, 0.0001)
	assert_almost_eq(normal.build_reactivity, 0.0, 0.0001)


## Difficult has to differ from Normal in the planner, not just on the label.
## focus_fire_bonus is deliberately 0: it measured negative on the DF4 ladder and
## is benched rather than deleted (docs/difficulty_check.md), so this pins both
## which capabilities carry the tier and which one is knowingly switched off.
func test_difficult_turns_the_capabilities_on() -> void:
	var hard := db.by_id(&"hard").profile()
	assert_gt(hard.threat_aversion, 0.0, "Difficult must actually weigh threat")
	assert_gt(hard.build_reactivity, 0.0, "Difficult must actually counter-build")
	# A weight this dial cannot act on is the same as no dial: below ~1.6 it
	# cannot buy a single tile away from a full-strength artillery shot, which is
	# how the tier once shipped a kill-zone refusal that never refused anything.
	assert_gt(
		hard.advance_threat_tiles,
		1.6,
		"Difficult's advance must be able to give up a whole tile, not just break ties"
	)
	assert_almost_eq(
		hard.focus_fire_bonus,
		0.0,
		0.0001,
		"focus fire is benched by measurement; switching it back on is a DF4 decision"
	)


## Easy's timidity is mechanical, not cosmetic: over-weighting danger is what the
## ladder found actually makes this planner weak, so Easy turns the same threat
## dial Difficult uses, the opposite way.
func test_easy_is_timid_rather_than_handicapped() -> void:
	var easy := db.by_id(&"easy").profile()
	var hard := db.by_id(&"hard").profile()
	assert_gt(
		easy.threat_aversion, hard.threat_aversion, "Easy should flinch harder than Difficult"
	)
	assert_gt(
		easy.advance_threat_tiles,
		hard.advance_threat_tiles,
		"Easy should hang back further than Difficult too"
	)
	assert_gt(easy.retreat_hp, db.by_id(&"normal").profile().retreat_hp, "Easy runs home earlier")


## No tier may touch anything but the AI's judgement — no tier resource carries a
## combat, economy or vision lever, because none exists to carry (D2/D3).
func test_a_tier_is_only_a_profile_and_a_label() -> void:
	var fields: Array[String] = []
	for property in Difficulty.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(String(property["name"]))
	assert_eq(fields, ["id", "display_name", "ai_profile"])


func test_unknown_id_falls_back_to_normal() -> void:
	var tier := db.by_id(&"nightmare")
	assert_eq(tier.id, &"normal", "an id that is not a tier must still play")


## A tier whose profile file went missing plays with the shipped defaults rather
## than taking the AI out entirely.
func test_a_tier_without_a_profile_still_yields_one() -> void:
	var orphan := Difficulty.new()
	assert_null(orphan.ai_profile)
	assert_not_null(orphan.profile())


## Guards against inert wiring: a tier that is loaded but never reaches the
## planner would pass every test above. Easy drops md_tank from its build list,
## so with the funds for one the two tiers must buy different units.
func test_easy_reaches_a_different_command_than_normal() -> void:
	var map_text := "[terrain]\nB....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0\n1 i 4 0"

	var normal_state := _state(map_text)
	normal_state.funds[1] = 20000
	for unit in normal_state.units:
		unit.acted = true
	var normal_pick := AIController.new(unit_db, db.by_id(&"normal").profile()).plan_next_command(
		normal_state
	)
	assert_true(normal_pick is BuildCommand, "expected a build, got %s" % normal_pick)
	assert_eq((normal_pick as BuildCommand).unit_type.id, &"md_tank")

	var easy_state := _state(map_text)
	easy_state.funds[1] = 20000
	for unit in easy_state.units:
		unit.acted = true
	var easy_pick := AIController.new(unit_db, db.by_id(&"easy").profile()).plan_next_command(
		easy_state
	)
	assert_true(easy_pick is BuildCommand)
	assert_eq(
		(easy_pick as BuildCommand).unit_type.id,
		&"tank",
		"Easy fields no md_tank, so the same funds buy the lesser hammer"
	)
	assert_eq(easy_pick.validate(easy_state), "")


## Easy over-buys infantry: it wants a fourth capture unit where Normal is
## already satisfied with three.
func test_easy_keeps_buying_capture_units_longer() -> void:
	var map_text := "[terrain]\nB...\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0"

	var easy_state := _state(map_text)
	easy_state.funds[1] = 20000
	for unit in easy_state.units:
		unit.acted = true
	var easy_pick := AIController.new(unit_db, db.by_id(&"easy").profile()).plan_next_command(
		easy_state
	)
	assert_true(easy_pick is BuildCommand)
	assert_eq((easy_pick as BuildCommand).unit_type.id, &"infantry")
