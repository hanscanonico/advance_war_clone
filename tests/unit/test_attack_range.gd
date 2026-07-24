extends GutTest
## AttackRange.threat_cells — the geometry the range overlay paints and the AI's
## ThreatMap is built from. One authority, so a red cell the player sees and a
## cell the planner fears are the same math. These pin the shape: a direct unit's
## reach is its move area grown by its range, an indirect unit's is a ring pinned
## to where it stands, and a friendly blocker deletes a firing cell and its fringe.

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	assert_not_null(map, "test map should parse")
	var state := GameState.create(map, unit_db)
	assert_not_null(state, "test state should build")
	return state


func _has(cells: Array[Vector2i], cell: Vector2i) -> bool:
	return cell in cells


## A direct unit fires from any cell it can stop on, so its threatened set is the
## movement diamond dilated by the weapon's range. Infantry: move 3, range 1, so
## every cell within manhattan distance 4 of the start, and nothing at 5.
func test_direct_reach_is_move_area_grown_by_range() -> void:
	var open := ".........\n".repeat(9)
	var state := _state("[terrain]\n%s[units]\n1 i 4 4" % open)
	var cells := AttackRange.threat_cells(state, state.units[0])
	assert_true(_has(cells, Vector2i(0, 4)), "distance 4 is reachable-then-fire")
	assert_true(_has(cells, Vector2i(4, 0)), "and so is the far edge on the other axis")
	assert_true(
		_has(cells, Vector2i(4, 4)), "the origin itself is covered by a neighbour firing back"
	)
	assert_false(_has(cells, Vector2i(0, 3)), "distance 5 is out of the grown diamond")


## An indirect unit cannot move and fire, so its ring hangs off the cell it stands
## on — not its movement range. Artillery: min 2, max 3. The min-range hole (the
## dead zone a gun cannot shoot inside) is the picture that sells the feature.
func test_indirect_ring_is_pinned_to_the_standing_cell() -> void:
	var open := ".........\n".repeat(9)
	var state := _state("[terrain]\n%s[units]\n1 g 4 4" % open)
	var cells := AttackRange.threat_cells(state, state.units[0])
	assert_true(_has(cells, Vector2i(4, 2)), "distance 2 is inside the ring")
	assert_true(_has(cells, Vector2i(4, 1)), "distance 3 is the outer edge")
	assert_false(_has(cells, Vector2i(4, 3)), "distance 1 sits in the min-range hole")
	assert_false(_has(cells, Vector2i(4, 4)), "and the gun cannot shoot its own cell")
	assert_false(_has(cells, Vector2i(4, 0)), "distance 4 is beyond max range")
	# Pinned to the standing cell, not the move range: the ring is exactly the
	# [2,3] band around (4,4), so a diagonal at distance 2 is in and nothing that
	# would only be reachable after a move appears.
	assert_true(_has(cells, Vector2i(3, 3)), "a diagonal at distance 2 is inside the ring")


## Truly unarmed units (a transport) reach nowhere, so nothing paints for them.
func test_unarmed_reaches_nowhere() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 2 0")
	assert_eq(AttackRange.threat_cells(state, state.units[0]), [] as Array[Vector2i])


## A friendly on a cell the unit would otherwise stop on removes it as a firing
## position, so the fringe only that cell could reach vanishes from the set. On a
## strip, a friendly three tiles out costs the unit the cell beyond its own reach.
func test_friendly_blocker_deletes_a_firing_cell_and_its_fringe() -> void:
	# Control: infantry alone reaches (3,0) to stop and fire on (4,0).
	var control := _state("[terrain]\n.......\n[units]\n1 i 0 0")
	assert_true(
		_has(AttackRange.threat_cells(control, control.units[0]), Vector2i(4, 0)),
		"with the lane clear, the far tile is under fire"
	)
	# A friendly on (3,0) can be passed but not stopped on, and (4,0) is a step too
	# far to reach directly — so the only firing cell that covered it is gone.
	var blocked := _state("[terrain]\n.......\n[units]\n1 i 0 0\n1 i 3 0")
	var cells := AttackRange.threat_cells(blocked, blocked.units[0])
	assert_false(_has(cells, Vector2i(4, 0)), "the blocker deletes the fringe cell")
	assert_true(_has(cells, Vector2i(2, 0)), "cells still reachable stay threatened")


## The ring is clipped to the board: a gun in the corner shows only its in-bounds
## arc, never a negative cell, and the min-range hole survives at the edge.
func test_board_edge_clips_the_ring() -> void:
	var open := ".........\n".repeat(9)
	var state := _state("[terrain]\n%s[units]\n1 g 0 0" % open)
	var cells := AttackRange.threat_cells(state, state.units[0])
	assert_true(_has(cells, Vector2i(2, 0)), "the in-bounds arc is present")
	assert_true(_has(cells, Vector2i(0, 3)), "on both axes")
	assert_false(_has(cells, Vector2i(1, 0)), "the min-range hole holds at the corner")
	for cell in cells:
		assert_true(state.map.terrain_at(cell) != null, "every cell is on the board")


## firing_cells is the primitive the union and the AI's attribution share: an
## indirect unit fires only from where it stands, whatever its move range.
func test_firing_cells_pins_indirect_to_its_cell() -> void:
	var state := _state("[terrain]\n.......\n[units]\n1 g 3 0")
	assert_eq(AttackRange.firing_cells(state, state.units[0]), [Vector2i(3, 0)] as Array[Vector2i])
