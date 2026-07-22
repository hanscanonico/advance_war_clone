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
## - A port with no sailable water beside it builds hulls that can never leave
##   the dock, and two ports on separate bodies of water build two fleets that
##   can never meet — the naval plan's R1, which the AI cannot plan its way out
##   of because it cannot ferry.
## - A shoal is road that also floats: identical cost for every land class, plus
##   lander access. That makes a careless one a bridge, and a bridge across water
##   silently deletes whatever the water was there to separate.
##
## Every failure names the map it failed on. "The roster is broken" is not an
## actionable failure message.

const HQ := &"hq"
const BASE := &"base"
const PORT := &"port"
const SHOAL := &"shoal"

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
		for cell in _cells_of_terrain(map, HQ):
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
			for cell in _cells_of_terrain(map, BASE):
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


## A port is only a port if something can sail out of it. Nothing in the parser
## notices one dropped a cell inland, and the failure it produces is silent: the
## build menu offers hulls, they spawn, and they are stuck on the dock forever.
func test_every_port_opens_onto_water_a_hull_can_use() -> void:
	for map in _maps():
		for cell in _cells_of_terrain(map, PORT):
			var sailable := false
			for step in MovementResolver.DIRECTIONS:
				var next: Vector2i = cell + step
				if map.in_bounds(next) and map.terrain_at(next).is_passable(TerrainType.SHIP):
					sailable = true
					break
			assert_true(
				sailable,
				(
					(
						"%s: the port at %s has no sailable cell beside it, so every "
						% [_name(map), cell]
					)
					+ "hull it builds is trapped on the dock"
				)
			)


## Naval plan R1, as a test rather than a paragraph: the AI never builds
## transports, so it can only fight a fleet it can sail to. Two ports on two
## separate seas give it a navy that shells nothing, which reads to a player as
## "the AI is broken" rather than "this map is".
func test_all_ports_on_a_map_share_one_body_of_water() -> void:
	for map in _maps():
		var ports := _cells_of_terrain(map, PORT)
		if ports.size() < 2:
			continue
		var reachable := _flood(map, ports[0], TerrainType.SHIP)
		for port in ports:
			assert_true(
				reachable.has(port),
				(
					(
						"%s: no hull can sail from %s to %s, so fleets built at "
						% [_name(map), ports[0], port]
					)
					+ "the two ports can never engage each other"
				)
			)


## Shoals cost every land class exactly what road does, so a shoal is walkable by
## everything that drives. One placed carelessly — or a chain of them — is a ford
## across water that no header mentions and no other test sees. Comparing the
## land graph with and without them says the real thing: beaches may extend a
## coast, never join two of them.
func test_no_shoal_joins_two_landmasses() -> void:
	for map in _maps():
		if _cells_of_terrain(map, SHOAL).is_empty():
			continue
		assert_eq(
			_land_components(map, true),
			_land_components(map, false),
			(
				"%s: its shoals merge landmasses the water separates — a beach may " % _name(map)
				+ "extend a coast, but a chain of them is a bridge for everything that drives"
			)
		)


## A beach nothing can land on is decoration wearing design's clothes. Shoals
## exist so a lander can put armour ashore, and a lander comes from a port — so
## every beach has to be sailable to from one. Catches the two ways to get this
## wrong: a shoal walled off from the sea, and a shoal on water no dock opens
## onto.
func test_every_shoal_can_be_reached_by_a_landing_craft() -> void:
	for map in _maps():
		var shoals := _cells_of_terrain(map, SHOAL)
		if shoals.is_empty():
			continue
		var beachable := {}
		for port in _cells_of_terrain(map, PORT):
			beachable.merge(_flood(map, port, TerrainType.LANDER))
		for shoal in shoals:
			assert_true(
				beachable.has(shoal),
				(
					(
						"%s: no lander can sail from any port to the beach at %s, "
						% [_name(map), shoal]
					)
					+ "so nothing can ever land on it"
				)
			)


## The two lints above pass on every shipped map, which is only reassuring if
## they can fail at all. These two check the mechanism against a board built to
## break it, so "green" keeps meaning something after the next map lands.
func test_the_shared_water_lint_can_tell_two_seas_apart() -> void:
	# Two one-cell harbours with dry land between them.
	var map := MapData.parse("[terrain]\nPSS.SSP\n", terrain_db)
	assert_not_null(map)
	var ports := _cells_of_terrain(map, PORT)
	assert_eq(ports.size(), 2, "the fixture should have a dock at each end")
	assert_false(
		_flood(map, ports[0], TerrainType.SHIP).has(ports[1]),
		"a hull cannot sail across dry land, and the lint has to notice"
	)


func test_the_shoal_lint_can_tell_a_beach_from_a_bridge() -> void:
	var islands := MapData.parse("[terrain]\nSSSSS\nS.S.S\nSSSSS\n", terrain_db)
	assert_not_null(islands)
	assert_eq(_land_components(islands, true), 2, "two islands with water between them")
	var bridged := MapData.parse("[terrain]\nSSSSS\nS._.S\nSSSSS\n", terrain_db)
	assert_not_null(bridged)
	assert_eq(_land_components(bridged, false), 2, "the same two islands, beach ignored")
	assert_eq(
		_land_components(bridged, true),
		1,
		"the beach joins them into one landmass — exactly what the lint is for"
	)


## The bridge check works by counting components, so anything that adds a
## component fails it. An offshore beach — a landing point out in open water,
## touching no land at all — is one of those, and it is the one shape that would
## make the lint accuse a map of the opposite of what it did.
func test_the_shoal_lint_does_not_mistake_an_offshore_beach_for_a_bridge() -> void:
	var offshore := MapData.parse("[terrain]\nSSSSS\nS.S.S\nSSSSS\nSS_SS\n", terrain_db)
	assert_not_null(offshore)
	assert_eq(
		_cells_of_terrain(offshore, SHOAL).size(), 1, "the fixture should have one offshore beach"
	)
	assert_eq(
		_land_components(offshore, true),
		_land_components(offshore, false),
		"a beach no land touches is a lander waypoint, not a bridge, and the lint has to say so"
	)
	assert_eq(_land_components(offshore, true), 2, "the two islands are still the only landmasses")


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


## Every cell of one terrain, row-major, over the whole grid rather than the
## property cache — so it answers for shoals and reefs, which nobody captures,
## as readily as for HQs and ports.
func _cells_of_terrain(map: MapData, terrain_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			if map.terrain_at(cell).id == terrain_id:
				cells.append(cell)
	return cells


## Every cell `move_class` can reach from `start`, `start` included.
func _flood(map: MapData, start: Vector2i, move_class: StringName) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in MovementResolver.DIRECTIONS:
			var next: Vector2i = cell + step
			if seen.has(next) or not map.in_bounds(next):
				continue
			if not map.terrain_at(next).is_passable(move_class):
				continue
			seen[next] = true
			queue.append(next)
	return seen


## How many separate landmasses the map has. Infantry is the yardstick for the
## same reason _hq_connection_error uses it — the only class that enters every
## land terrain, so its components *are* the landmasses. With `with_shoals`
## false, beaches count as water, which is what makes the pair of counts
## comparable.
##
## A component of nothing but shoals is not a landmass, and is not counted in
## either pass: an offshore beach — a lander waypoint no land touches — exists
## only in the with-shoals graph, and counting it would read as a bridge that
## appeared out of open water, which is the opposite of what it is.
func _land_components(map: MapData, with_shoals: bool) -> int:
	var seen := {}
	var components := 0
	for y in map.height:
		for x in map.width:
			var start := Vector2i(x, y)
			if seen.has(start) or not _is_land(map, start, with_shoals):
				continue
			seen[start] = true
			var solid := map.terrain_at(start).id != SHOAL
			var queue: Array[Vector2i] = [start]
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_back()
				for step in MovementResolver.DIRECTIONS:
					var next: Vector2i = cell + step
					if seen.has(next) or not map.in_bounds(next):
						continue
					if not _is_land(map, next, with_shoals):
						continue
					seen[next] = true
					solid = solid or map.terrain_at(next).id != SHOAL
					queue.append(next)
			if solid:
				components += 1
	return components


func _is_land(map: MapData, cell: Vector2i, with_shoals: bool) -> bool:
	var terrain := map.terrain_at(cell)
	if terrain == null or not terrain.is_passable(TerrainType.FOOT):
		return false
	return with_shoals or terrain.id != SHOAL


## Flood fills from one HQ over every cell infantry can enter and reports the
## first HQ it fails to reach. Infantry is the yardstick because it is the only
## class that can cross every land terrain, so "unreachable on foot" means
## unreachable, full stop.
func _hq_connection_error(map: MapData) -> String:
	var hqs := _cells_of_terrain(map, HQ)
	if hqs.size() < 2:
		return ""  # the HQ-count assertion owns this case
	var seen := _flood(map, hqs[0], TerrainType.FOOT)
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
