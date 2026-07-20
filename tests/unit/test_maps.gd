extends GutTest
## Playability lint over every map in maps/ — including maps added after this
## file was written, since it discovers the roster through MapCatalog instead of
## listing it.
##
## MapData.parse and GameState.create already reject *malformed* maps: ragged
## rows, unknown terrain or unit symbols, owners on non-property cells,
## out-of-bounds entries, two units on one cell, a unit standing on terrain it
## cannot enter. What neither catches is a map that loads perfectly and is then
## unplayable — and each assertion below is one of those:
##
## - A third, neutral HQ is a free win button: CaptureCommand sets `winner` on
##   *any* HQ, no matter who owned it.
## - A side with no base has no income engine and an AI that can never build.
## - A team-3 owner or unit parses today and then silently never plays, because
##   next_team() cycles GameState.TEAMS.
## - HQs walled off from each other make the HQ-capture win unreachable, which
##   quietly reduces the match to rout-only.
## - A map whose header claims symmetry and does not have it hands one side a
##   terrain or income edge that no amount of playtesting attributes correctly.
##
## Every failure names the map it failed on. "The roster is broken" is not an
## actionable failure message.

const HQ := &"hq"
const BASE := &"base"

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func test_every_map_parses_and_builds_a_game_state() -> void:
	var paths := MapCatalog.paths()
	assert_gt(paths.size(), 0, "maps/ should ship at least one map")
	for path in paths:
		var map := MapData.load_from_file(path, terrain_db)
		assert_not_null(map, "%s should parse" % path)
		if map != null:
			assert_not_null(GameState.create(map, unit_db), "%s should build a GameState" % path)


func test_every_map_gives_each_team_exactly_one_hq_it_owns() -> void:
	for map in _maps():
		var hq_owners := []
		for cell in _cells_of(map, HQ):
			hq_owners.append(map.owner_at(cell))
		assert_eq(
			hq_owners.size(),
			GameState.TEAMS.size(),
			(
				"%s: one HQ per team and no spares — an unowned HQ is a free win, " % _name(map)
				+ "since capturing any HQ ends the match"
			)
		)
		for team in GameState.TEAMS:
			assert_eq(
				hq_owners.count(team), 1, "%s: team %d should start on one HQ" % [_name(map), team]
			)


func test_every_map_gives_each_team_a_base() -> void:
	for map in _maps():
		for team in GameState.TEAMS:
			var bases := 0
			for cell in _cells_of(map, BASE):
				if map.owner_at(cell) == team:
					bases += 1
			assert_gt(
				bases,
				0,
				(
					(
						"%s: team %d owns no base, so it has no production and the AI "
						% [_name(map), team]
					)
					+ "has nothing to spend income on"
				)
			)


func test_no_map_uses_a_team_that_never_gets_a_turn() -> void:
	for map in _maps():
		var owners := map.initial_owners()
		for cell: Vector2i in owners:
			assert_has(
				GameState.TEAMS,
				int(owners[cell]),
				"%s: property %s is owned by a team that never plays" % [_name(map), cell]
			)
		for entry: Dictionary in map.starting_units:
			assert_has(
				GameState.TEAMS,
				int(entry.team),
				"%s: the unit on %s belongs to a team that never plays" % [_name(map), entry.cell]
			)


func test_every_map_keeps_its_hqs_reachable_on_foot() -> void:
	for map in _maps():
		assert_eq(
			_hq_connection_error(map),
			"",
			(
				"%s: infantry must be able to walk between the HQs, or the " % _name(map)
				+ "HQ-capture win condition can never happen"
			)
		)


func test_no_unit_starts_on_a_property() -> void:
	for map in _maps():
		for entry: Dictionary in map.starting_units:
			var cell: Vector2i = entry.cell
			assert_false(
				map.terrain_at(cell).is_property,
				(
					(
						"%s: a unit starts on the %s at %s — no side should open a "
						% [_name(map), map.terrain_at(cell).display_name, cell]
					)
					+ "capture ahead of turn one"
				)
			)


func test_maps_tagged_symmetric_really_are() -> void:
	var tagged := 0
	for map in _maps():
		if not map.symmetric:
			continue
		tagged += 1
		assert_eq(
			_mirror_error(map),
			"",
			"%s carries the `# symmetric` tag, so it has to mirror exactly" % _name(map)
		)
	assert_gt(tagged, 0, "at least one shipped map should be tagged `# symmetric`")


func test_every_map_describes_itself_for_the_menu() -> void:
	for map in _maps():
		assert_ne(
			map.description,
			"",
			(
				"%s: the first comment line is the map dropdown's tooltip, so it " % _name(map)
				+ "has to be a one-line description of the board"
			)
		)


## The menu opens on item 0, so the order MapCatalog hands it decides the
## default match. Smallest board first makes that the quickest one.
func test_the_menu_offers_the_smallest_board_first() -> void:
	var maps := MapCatalog.ordered(terrain_db)
	assert_eq(maps.size(), MapCatalog.paths().size(), "every shipped map should reach the menu")
	for i in range(1, maps.size()):
		var previous := maps[i - 1]
		assert_lte(
			previous.width * previous.height,
			maps[i].width * maps[i].height,
			"%s should not come before %s" % [_name(previous), _name(maps[i])]
		)


# --- helpers -----------------------------------------------------------------


func _maps() -> Array[MapData]:
	var maps: Array[MapData] = []
	for path in MapCatalog.paths():
		var map := MapData.load_from_file(path, terrain_db)
		if map != null:
			maps.append(map)
	return maps


func _name(map: MapData) -> String:
	return map.source_path.get_file()


func _cells_of(map: MapData, terrain_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in map.property_cells():
		if map.terrain_at(cell).id == terrain_id:
			cells.append(cell)
	return cells


## Flood fills from one HQ over every cell infantry can enter and reports the
## first HQ it fails to reach. Infantry is the yardstick because it is the only
## class that can cross every land terrain, so "unreachable on foot" means
## unreachable, full stop.
func _hq_connection_error(map: MapData) -> String:
	var hqs := _cells_of(map, HQ)
	if hqs.size() < 2:
		return ""  # the HQ-count assertion owns this case
	var seen := {hqs[0]: true}
	var queue: Array[Vector2i] = [hqs[0]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in MovementResolver.DIRECTIONS:
			var next: Vector2i = cell + step
			if seen.has(next) or not map.in_bounds(next):
				continue
			if not map.terrain_at(next).is_passable(TerrainType.FOOT):
				continue
			seen[next] = true
			queue.append(next)
	for hq in hqs:
		if not seen.has(hq):
			return "no foot path from %s to %s" % [hqs[0], hq]
	return ""


## Checks the whole board against the 180-degree rotation, teams swapped, and
## reports the first cell that breaks it. Terrain, starting ownership and
## starting armies all have to mirror: any one of them alone is an edge.
func _mirror_error(map: MapData) -> String:
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var twin := map.mirrored(cell)
			if map.terrain_at(cell).id != map.terrain_at(twin).id:
				return (
					"%s is %s but %s is %s"
					% [
						cell,
						map.terrain_at(cell).id,
						twin,
						map.terrain_at(twin).id,
					]
				)
	var owners := map.initial_owners()
	for cell: Vector2i in owners:
		var twin: Vector2i = map.mirrored(cell)
		var twin_owner := int(owners.get(twin, MapData.NEUTRAL))
		if twin_owner != _opposing(int(owners[cell])):
			return (
				"%s starts owned by team %d, but %s does not mirror it" % [cell, owners[cell], twin]
			)
	var by_cell := {}
	for entry: Dictionary in map.starting_units:
		by_cell[entry.cell] = entry
	for entry: Dictionary in map.starting_units:
		var twin: Vector2i = map.mirrored(entry.cell)
		if not by_cell.has(twin):
			return "the unit on %s has no counterpart on %s" % [entry.cell, twin]
		var other: Dictionary = by_cell[twin]
		if other.symbol != entry.symbol or int(other.team) != _opposing(int(entry.team)):
			return "the unit on %s is not mirrored by the one on %s" % [entry.cell, twin]
	return ""


## The other side, read off GameState.TEAMS rather than hardcoded as `3 - team`,
## so this says what it means while the game stays two-sided.
func _opposing(team: int) -> int:
	var index := GameState.TEAMS.find(team)
	return GameState.TEAMS[(index + 1) % GameState.TEAMS.size()]
