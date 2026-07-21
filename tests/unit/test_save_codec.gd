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

	var loaded := _decode(SaveCodec.encode(state, [1] as Array[int], &"hard"))
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 5)
	assert_eq(loaded.state.current_team, 2)
	assert_eq(loaded.state.funds[1], 3300)
	assert_eq(loaded.state.rng.state, expected_rng, "the RNG stream must survive a round trip")
	assert_eq(loaded.ai_teams, [1] as Array[int])
	assert_eq(loaded.difficulty, &"hard", "a resumed match keeps the tier it was played at")


## The literal is a tripwire: bumping the format is a decision, and this is where
## it gets noticed. What matters when the number does move is the line below it —
## every version ever written still has to load, since a save on someone's disk
## does not get upgraded when the game does.
func test_encoded_save_declares_the_current_version() -> void:
	assert_eq(int(_encoded()["version"]), 3)
	assert_eq(SaveCodec.VERSION, 3)
	assert_eq(SaveGame.VERSION, SaveCodec.VERSION, "the facade must report the codec's version")
	for version in range(1, SaveCodec.VERSION + 1):
		assert_has(
			SaveCodec.READABLE_VERSIONS,
			version,
			"version %d saves exist in the wild and must still load" % version
		)


## Every save written before difficulty existed carries no such key. Those
## matches were played against the shipped AI, which is exactly Normal — so they
## resume rather than being rejected or resuming at some other tier. An encode
## that is not told a tier records Normal for the same reason.
func test_a_save_without_a_difficulty_resumes_as_normal() -> void:
	assert_eq(String(_encoded()["difficulty"]), "normal", "an unspecified tier encodes as normal")
	var data := _encoded()
	data.erase("difficulty")
	assert_eq(SaveCodec.validate(data), "", "difficulty is optional, never required")
	var loaded := _decode(data)
	assert_not_null(loaded)
	assert_eq(loaded.difficulty, &"normal")


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


func test_a_version_this_codec_cannot_read_is_rejected() -> void:
	var data := _encoded()
	data["version"] = 99
	assert_string_contains(SaveCodec.validate(data), "version")


# --- commanders and version 1 -------------------------------------------------


func test_commanders_survive_the_round_trip() -> void:
	var commander_db := CommanderDB.load_default()
	var state := _first_steps_state()
	state.set_commander(1, commander_db.by_id(&"alina_ward"))
	state.set_commander(2, commander_db.by_id(&"viktor_draeg"))
	state.add_charge(1, 4000)
	state.commander_state(1).power_active = true

	var data := SaveCodec.encode(state, [] as Array[int])
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart, commander_db)
	assert_not_null(loaded)
	assert_eq(loaded.state.commander_of(1).id, &"alina_ward")
	assert_eq(loaded.state.commander_of(2).id, &"viktor_draeg")
	assert_eq(loaded.state.commander_state(1).charge, 4000)
	assert_true(loaded.state.power_active(1), "a power that was up stays up across a save")
	assert_false(loaded.state.power_active(2))


## R4: a save written before commanders existed has no commander block at all.
## It must load as the no-commander match it recorded, not fail.
func test_a_version_1_save_loads_as_a_no_commander_match() -> void:
	var data := _encoded()
	data["version"] = 1
	data.erase("commanders")
	assert_eq(SaveCodec.validate(data), "", "version 1 is still readable")
	var loaded := _decode(data)
	assert_not_null(loaded)
	for team in GameState.TEAMS:
		assert_eq(loaded.state.commander_of(team).id, CommanderType.NEUTRAL_ID)
		assert_eq(loaded.state.commander_state(team).charge, 0)
		assert_false(loaded.state.power_active(team))


func test_a_commander_who_no_longer_exists_falls_back_to_neutral() -> void:
	var data := _encoded()
	data["commanders"] = {"1": {"id": "a_general_who_was_cut", "charge": 9000, "active": true}}
	var loaded := _decode(data)
	assert_not_null(loaded)
	assert_eq(loaded.state.commander_of(1).id, CommanderType.NEUTRAL_ID)
	assert_eq(loaded.state.commander_state(1).charge, 0, "and banks nothing, having no power")
	assert_false(loaded.state.power_active(1))


func test_a_hand_edited_meter_is_still_capped() -> void:
	var commander_db := CommanderDB.load_default()
	var data := _encoded()
	data["commanders"] = {"1": {"id": "alina_ward", "charge": 999999, "active": false}}
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart, commander_db)
	assert_not_null(loaded)
	assert_eq(loaded.state.commander_state(1).charge, loaded.state.commander_of(1).power_cost)


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
