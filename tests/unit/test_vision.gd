extends GutTest

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func _state(map_text: String, fog := true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	state.fog_enabled = fog
	return state


func test_fog_disabled_sees_everything() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0", false)
	var cells := Vision.visible_cells(state, 1)
	assert_eq(cells.size(), 8)


func test_unit_vision_is_manhattan_range() -> void:
	# infantry vision 2 in an open 7x7 field
	var rows := (
		"[terrain]\n"
		+ "\n".join([".......", ".......", ".......", ".......", ".......", ".......", "......."])
	)
	var state := _state(rows + "\n[units]\n1 i 3 3")
	var cells := Vision.visible_cells(state, 1)
	assert_true(cells.has(Vector2i(3, 1)))
	assert_true(cells.has(Vector2i(5, 3)))
	assert_false(cells.has(Vector2i(3, 0)), "distance 3 is past infantry vision")
	assert_false(cells.has(Vector2i(6, 3)))


func test_woods_hide_beyond_adjacency() -> void:
	var state := _state("[terrain]\n..FF\n[units]\n1 i 0 0")
	var cells := Vision.visible_cells(state, 1)
	assert_true(cells.has(Vector2i(1, 0)), "plains at range 1")
	assert_false(cells.has(Vector2i(2, 0)), "woods at range 2 stay dark")
	var close := _state("[terrain]\n.F..\n[units]\n1 i 0 0")
	assert_true(Vision.visible_cells(close, 1).has(Vector2i(1, 0)), "adjacent woods are revealed")


func test_owned_properties_watch_their_surroundings() -> void:
	var state := _state("[terrain]\nC....\n[owners]\n1 0 0")
	var cells := Vision.visible_cells(state, 1)
	assert_true(cells.has(Vector2i(2, 0)))
	assert_false(cells.has(Vector2i(3, 0)))


func test_carried_units_see_nothing() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n1 r 1 0")
	var recon := state.units[1]
	recon.carrier = state.units[0]
	recon.cell = state.units[0].cell
	var cells := Vision.visible_cells(state, 1)
	# APC vision is 1; the boarded recon's vision 5 must not apply
	assert_false(cells.has(Vector2i(3, 0)))


func test_enemy_units_do_not_reveal_for_us() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0\n2 r 5 0")
	var cells := Vision.visible_cells(state, 1)
	assert_false(cells.has(Vector2i(5, 0)))


## Concealment is a terrain flag now, not the id "woods", so a reef hides a hull
## exactly as woods hide a tank: seen from next door, invisible from further off.
func test_reefs_conceal_like_woods() -> void:
	var state := _state("[terrain]\nS*SS*\n[units]\n1 s 0 0")
	var cells := Vision.visible_cells(state, 1)
	assert_true(cells.has(Vector2i(1, 0)), "the sub sees the reef right beside it")
	assert_true(cells.has(Vector2i(3, 0)), "and open water three tiles off")
	assert_false(cells.has(Vector2i(4, 0)), "but not the reef at that same range")


## The doctrine that sees through cover sees through both kinds — it would be a
## strange power that peered into a wood and not a reef.
##
## The tank is the control: it is not marching, so with the identical power up and
## the identical sight range it still cannot read its reef. That is what makes
## this a test of the cover rule rather than of the vision bonus beside it.
func test_seeing_into_cover_covers_reefs_too() -> void:
	var state := _state("[terrain]\n...*\n...*\n[units]\n1 i 0 0\n1 t 0 1")
	state.set_commander(1, CommanderDB.load_default().by_id(&"nia_rowan"))
	assert_false(
		Vision.visible_cells(state, 1).has(Vector2i(3, 1)),
		"before the power, the tank's reef is cover at three tiles"
	)
	state.commander_state(1).power_active = true
	var cells := Vision.visible_cells(state, 1)
	assert_true(cells.has(Vector2i(3, 0)), "Ghost March should read the marching unit's reef")
	assert_false(
		cells.has(Vector2i(3, 1)), "and leave the tank, which is not marching, blind to its"
	)
