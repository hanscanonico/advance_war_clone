extends GutTest
## The faction-identity resolver (plan FI2): the full §2 resolution table, both
## mirror collision orders included. Node-free, like the resolver it exercises.
##
## Rows are the atlas order the art pipeline writes and SideIdentity maps to:
## 0 neutral, 1 meridian(red), 2 aurora(blue), 3 iron, 4 verdant. Names are the
## faction display strings CommanderVisuals maps.

const MERIDIAN := "Meridian Coalition"
const IRON := "Iron Dominion"
const AURORA := "Aurora Compact"
const VERDANT := "Verdant League"


## A commander with just the one field the resolver reads. An empty faction is
## the neutral (commander-less) side.
func _co(faction: String) -> CommanderType:
	var commander := CommanderType.new()
	commander.faction = faction
	return commander


func _resolve(faction_1: String, faction_2: String) -> SideIdentity:
	return SideIdentity.resolve({1: _co(faction_1), 2: _co(faction_2)})


func _key(identity: SideIdentity, team: int) -> StringName:
	return identity.theme(team).key


# --- commander-less: exactly today -------------------------------------------


func test_no_commanders_is_red_then_blue() -> void:
	# The control group: a match with no commanders must render exactly as it did
	# before factions — side 1 red on row 1, side 2 blue on row 2.
	var identity := _resolve("", "")
	assert_eq(_key(identity, 1), &"meridian")
	assert_eq(_key(identity, 2), &"aurora")
	assert_eq(identity.atlas_row(1), 1)
	assert_eq(identity.atlas_row(2), 2)
	assert_eq(identity.display_name(1), "First Army")
	assert_eq(identity.display_name(2), "Second Army")


func test_generic_theme_matches_commander_visuals() -> void:
	# The generic sides wear the actual classic themes, not a private copy of the
	# colours — the whole reason the duplicated consts get deleted.
	var identity := _resolve("", "")
	assert_eq(identity.theme(1).color, CommanderVisuals.theme_for_key(&"meridian").color)
	assert_eq(identity.theme(2).color, CommanderVisuals.theme_for_key(&"aurora").color)


# --- faction sides, no clash -------------------------------------------------


func test_two_distinct_factions_keep_their_colours() -> void:
	var identity := _resolve(IRON, VERDANT)
	assert_eq(_key(identity, 1), &"iron")
	assert_eq(_key(identity, 2), &"verdant")
	assert_eq(identity.atlas_row(1), 3)
	assert_eq(identity.atlas_row(2), 4)
	assert_eq(identity.display_name(1), IRON)
	assert_eq(identity.display_name(2), VERDANT)


func test_faction_colour_matches_commander_visuals() -> void:
	var identity := _resolve(VERDANT, IRON)
	assert_eq(identity.theme(1).color, CommanderVisuals.theme_for_key(&"verdant").color)
	assert_eq(identity.theme(2).color, CommanderVisuals.theme_for_key(&"iron").color)


# --- mirror matches: fall back by hue, keep the name -------------------------


func test_iron_mirror_is_slate_plus_blue() -> void:
	var identity := _resolve(IRON, IRON)
	assert_eq(_key(identity, 1), &"iron", "first Iron keeps slate")
	assert_eq(_key(identity, 2), &"aurora", "second Iron borrows the first hue-distinct classic")
	assert_eq(identity.atlas_row(1), 3)
	assert_eq(identity.atlas_row(2), 2, "the borrowed side draws in the borrowed row's art")
	assert_eq(identity.display_name(1), IRON, "both mirror sides keep the faction name")
	assert_eq(identity.display_name(2), IRON)


func test_aurora_mirror_is_blue_plus_red() -> void:
	# Aurora blue is not hue-distinct from Aurora blue, so the second slot skips it
	# and takes Meridian red.
	var identity := _resolve(AURORA, AURORA)
	assert_eq(_key(identity, 1), &"aurora")
	assert_eq(_key(identity, 2), &"meridian")
	assert_eq(identity.atlas_row(1), 2)
	assert_eq(identity.atlas_row(2), 1)


func test_meridian_mirror_is_red_plus_blue() -> void:
	var identity := _resolve(MERIDIAN, MERIDIAN)
	assert_eq(_key(identity, 1), &"meridian")
	assert_eq(_key(identity, 2), &"aurora")


func test_verdant_mirror_borrows_blue() -> void:
	var identity := _resolve(VERDANT, VERDANT)
	assert_eq(_key(identity, 1), &"verdant")
	assert_eq(_key(identity, 2), &"aurora")


# --- generic sides resolve after factions, never steal a colour --------------


func test_generic_versus_meridian_yields_meridian_red_generic_blue() -> void:
	# Meridian (side 2) claims red first; the commander-less side 1 gets blue, not
	# the reverse — generic sides resolve after faction sides.
	var identity := _resolve("", MERIDIAN)
	assert_eq(_key(identity, 2), &"meridian")
	assert_eq(identity.atlas_row(2), 1)
	assert_eq(_key(identity, 1), &"aurora")
	assert_eq(identity.atlas_row(1), 2)
	assert_eq(identity.display_name(2), MERIDIAN)
	assert_eq(identity.display_name(1), "First Army")


func test_meridian_versus_generic_keeps_today_layout() -> void:
	var identity := _resolve(MERIDIAN, "")
	assert_eq(_key(identity, 1), &"meridian")
	assert_eq(_key(identity, 2), &"aurora")


func test_generic_versus_aurora_gives_generic_red() -> void:
	# Aurora (side 2) takes blue; the generic side 1 falls to red, the first
	# classic left.
	var identity := _resolve("", AURORA)
	assert_eq(_key(identity, 2), &"aurora")
	assert_eq(_key(identity, 1), &"meridian")


# --- totality and determinism ------------------------------------------------


func test_two_sides_never_share_a_colour() -> void:
	for pair: Array in [["", ""], [IRON, IRON], [AURORA, AURORA], ["", MERIDIAN], [IRON, VERDANT]]:
		var identity := _resolve(pair[0], pair[1])
		assert_ne(_key(identity, 1), _key(identity, 2), "%s vs %s share a colour" % pair)


func test_same_picks_resolve_the_same() -> void:
	var a := _resolve(IRON, IRON)
	var b := _resolve(IRON, IRON)
	assert_eq(_key(a, 1), _key(b, 1))
	assert_eq(_key(a, 2), _key(b, 2))
	assert_eq(a.display_name(2), b.display_name(2))


func test_neutral_owner_and_unresolved_team_are_row_zero() -> void:
	var identity := _resolve(IRON, VERDANT)
	assert_eq(identity.atlas_row(0), 0, "a neutral property owner draws in the neutral row")
	assert_eq(identity.atlas_row(9), 0, "a side that never resolved falls to neutral")


func test_unknown_faction_string_falls_to_generic() -> void:
	# A .tres naming a faction the visuals were never taught resolves neutral,
	# so it is treated as a commander-less side rather than crashing.
	var identity := SideIdentity.resolve({1: _co("Nonexistent Order"), 2: _co(IRON)})
	assert_eq(_key(identity, 2), &"iron")
	assert_eq(_key(identity, 1), &"meridian", "unknown faction takes the first free classic")


# --- for_game reads the sim's commander picks --------------------------------


func test_for_game_reads_commander_of() -> void:
	var terrain_db := TerrainDB.load_default()
	var unit_db := UnitDB.load_default()
	var map := MapData.parse("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", terrain_db)
	var state := GameState.create(map, unit_db)
	state.set_commander(1, _co(IRON))
	state.set_commander(2, _co(VERDANT))
	var identity := SideIdentity.for_game(state)
	assert_eq(_key(identity, 1), &"iron")
	assert_eq(_key(identity, 2), &"verdant")
