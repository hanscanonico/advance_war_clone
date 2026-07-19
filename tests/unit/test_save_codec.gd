extends GutTest
## SaveCodec on its own: no file on disk, no JSON text. Every case here builds
## or edits a plain dictionary, which is the point of splitting the codec out
## of SaveGame — malformed-save handling is testable without a filesystem.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _first_steps_state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return state


func _encoded() -> Dictionary:
	return SaveCodec.encode(_first_steps_state(), [2] as Array[int])


func _decode(data: Dictionary) -> SaveCodec.LoadedMatch:
	return SaveCodec.decode(data, terrain_db, unit_db, chart)


# --- round trip ---------------------------------------------------------------


func test_encode_decode_restores_the_match_without_touching_disk() -> void:
	var state := _first_steps_state()
	state.day = 5
	state.current_team = 2
	state.funds[1] = 3300
	state.rng.seed = 99
	var expected_rng := state.rng.state

	var loaded := _decode(SaveCodec.encode(state, [1] as Array[int]))
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 5)
	assert_eq(loaded.state.current_team, 2)
	assert_eq(loaded.state.funds[1], 3300)
	assert_eq(loaded.state.rng.state, expected_rng, "the RNG stream must survive a round trip")
	assert_eq(loaded.ai_teams, [1] as Array[int])


func test_encoded_save_declares_version_1() -> void:
	assert_eq(int(_encoded()["version"]), 1)
	assert_eq(SaveCodec.VERSION, 1)
	assert_eq(SaveGame.VERSION, SaveCodec.VERSION, "the facade must report the codec's version")


func test_a_carried_unit_survives_the_round_trip() -> void:
	var state := _first_steps_state()
	var infantry := state.unit_at(Vector2i(4, 3))
	var apc := state.unit_at(Vector2i(3, 3))
	infantry.carrier = apc
	infantry.cell = apc.cell

	var loaded := _decode(SaveCodec.encode(state, [] as Array[int]))
	assert_not_null(loaded)
	var cargo := loaded.state.cargo_of(loaded.state.unit_at(Vector2i(3, 3)))
	assert_eq(cargo.size(), 1, "the APC should still be carrying its passenger")


# --- structural validation ----------------------------------------------------


func test_validate_accepts_an_encoded_save() -> void:
	assert_eq(SaveCodec.validate(_encoded()), "")


func test_wrong_version_is_rejected() -> void:
	var data := _encoded()
	data["version"] = 2
	assert_string_contains(SaveCodec.validate(data), "version")


func test_missing_required_key_is_named() -> void:
	var data := _encoded()
	data.erase("rng_state")
	assert_string_contains(SaveCodec.validate(data), "rng_state")


func test_malformed_unit_entry_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0].erase("hp")
	assert_string_contains(SaveCodec.validate(data), "hp")


func test_missing_funds_for_a_team_is_rejected() -> void:
	var data := _encoded()
	(data["funds"] as Dictionary).erase("2")
	assert_string_contains(SaveCodec.validate(data), "funds")


# --- carrier relationships ----------------------------------------------------
#
# Carrier links are indices into the unit list, so a corrupt save can point
# anywhere. Before, an out-of-range index was silently dropped and a unit that
# should have been cargo reappeared on the board; a self-carrying unit or a
# cycle was wired up as-is.


func test_carrier_index_past_the_end_of_the_list_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["carrier"] = 999
	assert_null(_decode(data), "an out-of-range carrier index must fail, not be ignored")
	assert_push_error("unit 0 has carrier index 999")


func test_negative_carrier_index_other_than_the_sentinel_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["carrier"] = -7
	assert_null(_decode(data))
	assert_push_error("outside the")


func test_a_unit_carrying_itself_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["carrier"] = 0
	assert_null(_decode(data), "a unit cannot be its own carrier")
	assert_push_error("unit 0 is its own carrier")


func test_a_carrier_cycle_is_rejected() -> void:
	var data := _encoded()
	var units: Array = data["units"]
	units[0]["carrier"] = 1
	units[1]["carrier"] = 0
	assert_null(_decode(data), "two units carrying each other must fail rather than hang")
	assert_push_error("carrying each other")


func test_a_longer_carrier_cycle_is_rejected() -> void:
	var data := _encoded()
	var units: Array = data["units"]
	units[0]["carrier"] = 1
	units[1]["carrier"] = 2
	units[2]["carrier"] = 0
	assert_null(_decode(data))
	assert_push_error("carrying each other")


## The sentinel must keep meaning "on the board" — the validation above must not
## have made an ordinary save stricter.
func test_every_unit_on_the_board_is_still_valid() -> void:
	var data := _encoded()
	for entry: Dictionary in data["units"]:
		assert_eq(int(entry["carrier"]), SaveCodec.NO_CARRIER)
	assert_not_null(_decode(data))
