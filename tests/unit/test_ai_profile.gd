extends GutTest
## The AIProfile seam: the shipped profile must still hold the numbers the
## planner used when they were constants, and the planner must actually read
## the profile it was handed rather than a hardcoded copy.

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


func test_default_profile_loads() -> void:
	var profile := AIProfile.load_default()
	assert_not_null(profile, "res://data/ai/default.tres should load")


## The shipped file and the script's own defaults have to be the same numbers.
## ai_profile.gd promises exactly that, and load_default() leans on it: a match
## played with the file missing must be the match the file would have produced,
## or a broken install quietly plays a different game.
##
## Compared field by field off the property list rather than value by value, so
## tuning a weight means one edit to the .tres and one to the default beside it —
## and forgetting either is what fails here. That makes it the tripwire the
## hand-written version was, without being a chore every time a weight is added.
func test_default_profile_matches_the_built_in_defaults() -> void:
	var shipped := AIProfile.load_default()
	var defaults := AIProfile.new()
	var checked := 0
	for property in defaults.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = property.name
		assert_eq(shipped.get(field), defaults.get(field), "data/ai/default.tres: %s" % field)
		checked += 1
	assert_gt(checked, 10, "the profile should expose its weights as script variables")


## A controller built without a profile must behave exactly like one built with
## the shipped profile — that is what keeps every existing caller unchanged.
func test_omitted_profile_falls_back_to_the_default() -> void:
	var implicit := AIController.new(unit_db)
	var explicit := AIController.new(unit_db, AIProfile.load_default())
	var map_text := "[terrain]\n....\n[units]\n1 t 1 0\n2 i 0 0\n2 g 2 0"
	var from_implicit := implicit.plan_next_command(_state(map_text))
	var from_explicit := explicit.plan_next_command(_state(map_text))
	assert_true(from_implicit is AttackCommand)
	assert_eq(
		(from_implicit as AttackCommand).target_cell, (from_explicit as AttackCommand).target_cell
	)


## Proves the profile is wired through rather than stored and ignored: an
## infantry one step from a city normally captures it, but a profile that
## values capturing at nothing must make it do something else.
func test_profile_actually_drives_the_decision() -> void:
	var map_text := "[terrain]\n.C\n[units]\n1 i 0 0"

	var default_ai := AIController.new(unit_db)
	assert_true(
		default_ai.plan_next_command(_state(map_text)) is CaptureCommand,
		"the shipped profile should capture an adjacent city"
	)

	var indifferent := AIProfile.new()
	indifferent.capture_score = 0.0
	indifferent.hq_capture_multiplier = 0.0
	indifferent.capture_progress_bonus = 0.0
	var tuned_ai := AIController.new(unit_db, indifferent)
	assert_false(
		tuned_ai.plan_next_command(_state(map_text)) is CaptureCommand,
		"a profile that scores captures at zero should not choose one"
	)


## The HQ multiplier is what makes the AI walk past a city to reach the enemy
## HQ. Neutralising it should flip that preference to the nearer property.
func test_hq_preference_comes_from_the_profile() -> void:
	var map_text := "[terrain]\nQC.\n[owners]\n2 0 0\n[units]\n1 i 2 0"

	var default_pick := AIController.new(unit_db).plan_next_command(_state(map_text))
	assert_true(default_pick is CaptureCommand)
	var hq_path: Array[Vector2i] = (default_pick as CaptureCommand).path
	assert_eq(hq_path[hq_path.size() - 1], Vector2i(0, 0), "shipped profile should prefer the HQ")

	var no_hq_bias := AIProfile.new()
	no_hq_bias.hq_capture_multiplier = 1.0
	var flat_pick := AIController.new(unit_db, no_hq_bias).plan_next_command(_state(map_text))
	assert_true(flat_pick is CaptureCommand)
	var flat_path: Array[Vector2i] = (flat_pick as CaptureCommand).path
	assert_eq(
		flat_path[flat_path.size() - 1],
		Vector2i(1, 0),
		"without the HQ multiplier the closer city wins on step cost"
	)
