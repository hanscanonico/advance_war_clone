class_name BattleView
extends RefCounted
## Draws battle state: terrain, unit sprites, movement and attack overlays,
## fog, the HUD, and the terrain and damage panels.
##
## Reads simulation state to present it and never mutates it — no commands, no
## rules, no turn flow. Battle owns the flow and tells the view what to draw.
## The view never calls back into Battle, so the dependency runs one way and a
## renderer can never quietly become a second rules engine.
##
## Fog is enforced here rather than in the sim, which stays permissive:
## `Vision` decides what a team can see, and the view refuses to draw the rest.
## Battle picks *whose* eyes to use and passes the team in.
##
## Battle assigns the node fields and then calls `setup`; the view is
## constructed with no arguments so it never holds a reference to Battle.

const TILE := 16
## Terrain atlas cells are 4x the world grid so the PixVoxel property buildings
## keep their detail; TerrainLayer is scaled down to compensate.
const TERRAIN_PX := 64
const ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"
const OVERLAY_PATH := "res://assets/tiles/overlay.png"
const ATLAS_SOURCE_ID := 0

const UNIT_SPRITE_SCENE := preload("res://scenes/battle/unit_sprite.tscn")

var terrain_layer: TileMapLayer
## Painted beyond the map edges — a darkened continuation of the board that
## fills the screen when the camera is far enough out to show the whole map.
var backdrop_layer: TileMapLayer
var move_overlay: TileMapLayer
var attack_overlay: TileMapLayer
var fog_layer: TileMapLayer
var path_line: Line2D
var units_root: Node2D
var cursor: Sprite2D
var camera: Camera2D
var terrain_panel: TerrainPanel
var damage_preview: PanelContainer
var atk_label: Label
var counter_label: Label
var turn_label: Label
## The current side's portrait identity and charge meter. Hides itself for a side
## with no Command Power, so a commander-less match keeps the pre-commander HUD.
var commander_chip: CommanderHudChip

var db: TerrainDB
var map: MapData
var game: GameState
## Who each side is and what it wears — resolved once at match setup from the
## commander picks (SideIdentity). Every team-to-paint and team-to-name answer
## the board draws comes from here; the sim keeps its team ints. Battle builds it
## and assigns it, like everything else the view draws with.
var identity: SideIdentity
## Teams the computer plays. The view only needs them to know whose controls it
## must not offer; Battle owns the list and hands it over, as with everything.
var ai_teams: Array[int] = []

var _sprites: Dictionary = {}  # Unit -> UnitSprite
## Cells the viewing team can see; refreshed by `refresh_fog` after commits.
var _visible_cells: Dictionary = {}
## Whose eyes the board is drawn from; set by the same pass. Starts on the
## opening team, which is who is looking before the first fog refresh runs.
var _viewing_team: int = GameState.TEAMS[0]
## True while a hot-seat handoff blacks the board out for everyone; set by the
## same pass, and the one case where even your own units are hidden.
var _blacked_out := false


## Builds the tile sets from data and paints the opening board. Call once, after
## the node fields and `db`/`map`/`game` are set.
func setup() -> void:
	terrain_panel.identity = identity  # the panel names and tints sides through the same resolver
	terrain_layer.tile_set = _build_tile_set()
	# The terrain atlas is drawn at 4x the world grid (see TERRAIN_PX), so the
	# layer is scaled back down to keep one cell = TILE. Overlays and the cursor
	# stay at 1x and are unaffected.
	terrain_layer.scale = Vector2.ONE * (float(TILE) / float(TERRAIN_PX))
	backdrop_layer.tile_set = terrain_layer.tile_set
	backdrop_layer.scale = terrain_layer.scale
	move_overlay.tile_set = _build_overlay_tile_set()
	attack_overlay.tile_set = move_overlay.tile_set
	fog_layer.tile_set = _build_fog_tile_set()
	_paint_map()
	_paint_backdrop()
	_spawn_unit_sprites()
	_apply_camera_limits()


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


# --- terrain -----------------------------------------------------------------


## The TileSet is derived from TerrainDB at runtime: one atlas column per
## terrain, team-colored rows for properties. No hand-maintained .tres TileSet.
func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TERRAIN_PX, TERRAIN_PX)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(ATLAS_PATH)
	atlas.texture_region_size = Vector2i(TERRAIN_PX, TERRAIN_PX)
	for terrain in db.all():
		atlas.create_tile(Vector2i(terrain.atlas_col, 0))
		if terrain.team_tinted:
			# Rows 1-4, one per faction — a property can be owned by any side, and
			# which faction row that side draws in is the resolver's call, not the
			# owner int. The atlas carries all four (FI1); this registers them.
			for row in range(1, SideIdentity.FACTION_ROWS + 1):
				atlas.create_tile(Vector2i(terrain.atlas_col, row))
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


func _build_overlay_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(OVERLAY_PATH)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	atlas.create_tile(Vector2i.ZERO)
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


## The fog gets its own tile rather than sharing the move/attack overlay's.
## `overlay.png` carries a brighter one-pixel border, which is what rings a single
## range cell — but painted across a whole fogged region that border becomes a
## grid of dark outlines around every cell, and the shroud reads as a field of
## hard-edged boxes instead of one drawn-down curtain. A flat, seam-free cell
## closes the region up; its colour and depth stay the FogLayer's modulate.
func _build_fog_tile_set() -> TileSet:
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	atlas.create_tile(Vector2i.ZERO)
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


func _paint_map() -> void:
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var terrain := map.terrain_at(cell)
			var row := identity.atlas_row(game.owner_at(cell)) if terrain.team_tinted else 0
			terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))


## Fills a ring of cells beyond the map edges so that when the whole map is in
## view (see min_zoom) the rest of the screen reads as darkened out-of-bounds
## ground, not engine-clear void. Each cell extends its nearest edge terrain;
## properties fall back to plains so no building appears to stand off the board.
## The ring is sized to the most min_zoom can expose, and the darkening is the
## layer's modulate in the scene — the tiles themselves are the terrain atlas.
func _paint_backdrop() -> void:
	var plains := db.by_id(&"plains")
	var map_px := Vector2(map.size() * TILE)
	var exposed := _viewport_size() / min_zoom()
	var margin := Vector2i(
		ceili(maxf(0.0, (exposed.x - map_px.x) / 2.0) / TILE) + 1,
		ceili(maxf(0.0, (exposed.y - map_px.y) / 2.0) / TILE) + 1
	)
	for y in range(-margin.y, map.height + margin.y):
		for x in range(-margin.x, map.width + margin.x):
			if x >= 0 and x < map.width and y >= 0 and y < map.height:
				continue
			var src := Vector2i(clampi(x, 0, map.width - 1), clampi(y, 0, map.height - 1))
			var terrain := map.terrain_at(src)
			if terrain.team_tinted:
				terrain = plains
			backdrop_layer.set_cell(Vector2i(x, y), ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, 0))


## Recolors one property to its current owner, after a capture — but only for a
## cell the viewer can currently see. A capture inside the viewer's fog must not
## paint through the translucent fog layer (it would leak enemy expansion and
## income), so a hidden cell keeps its last-seen colour and the repaint is
## deferred to `refresh_fog`, which lands it the moment the viewer's vision
## reaches the cell.
func repaint_property(cell: Vector2i) -> void:
	if not _can_see_cell(cell):
		return
	var terrain := map.terrain_at(cell)
	if terrain.team_tinted:
		terrain_layer.set_cell(
			cell,
			ATLAS_SOURCE_ID,
			Vector2i(terrain.atlas_col, identity.atlas_row(game.owner_at(cell)))
		)


# --- unit sprites ------------------------------------------------------------


func _spawn_unit_sprites() -> void:
	for unit in game.units:
		spawn_sprite_for(unit)


func spawn_sprite_for(unit: Unit) -> void:
	var sprite: UnitSprite = UNIT_SPRITE_SCENE.instantiate()
	units_root.add_child(sprite)
	sprite.fogged = _is_fogged(unit)
	sprite.setup(unit, game.current_team, identity.atlas_row(unit.team))
	_sprites[unit] = sprite


func sprite_for(unit: Unit) -> UnitSprite:
	return _sprites.get(unit)


## Brings one sprite back in step with the sim, fog included: the answer is
## written onto the sprite, which then draws itself from it.
##
## Deciding it here and storing it there is what makes it stick. A sprite that
## worked visibility out for itself would un-hide a fogged enemy every time
## anything redrew it — and `UnitSprite` redraws on three different calls — so
## the decision is made in one place and remembered rather than re-derived.
func refresh_sprite(unit: Unit) -> void:
	var sprite: UnitSprite = _sprites.get(unit)
	if sprite == null:
		return
	sprite.fogged = _is_fogged(unit)
	sprite.refresh()


## Whether the board currently hides `unit` from whoever is looking. Vision owns
## the rule; the blackout is the view's own, since a hot-seat handoff hides even
## your own units.
func _is_fogged(unit: Unit) -> bool:
	return _blacked_out or not can_see_unit(unit)


## Hands the sprite over and stops tracking the unit, for callers that animate
## a departure themselves (a merged-away twin, a unit dying in combat). The
## caller owns the returned sprite from here on.
func release_sprite(unit: Unit) -> UnitSprite:
	var sprite: UnitSprite = _sprites.get(unit)
	_sprites.erase(unit)
	return sprite


## Re-tints every sprite for the team about to play. Safe to call outside a fog
## pass: setting the team redraws the sprite, and a redraw keeps whatever
## `refresh_sprite` last decided about seeing it.
func set_active_team(team: int) -> void:
	for unit in game.units:
		_sprites[unit].set_active_team(team)


## Brings every sprite back in step with the sim in one pass, for the changes
## that touch more of the board than a caller can name unit by unit.
##
## Two of those. A death can take units the combat result never mentions —
## cargo goes down with its transport — so any sprite whose unit has left
## `game.units` is freed. And a Command Power can heal or refuel a whole side at
## once, so every surviving sprite is redrawn rather than just the one that
## acted. Survivors go through `refresh_sprite`, so the pass re-applies fog
## instead of leaking whatever the last fog pass hid.
func sync_sprites() -> void:
	for unit: Unit in _sprites.keys():
		if unit in game.units:
			refresh_sprite(unit)
			continue
		var sprite: UnitSprite = _sprites[unit]
		_sprites.erase(unit)
		sprite.queue_free()


## Dev capture only, so underscored and reached into by the scenario driver like
## the rest of the scene it drives: a scenario that swaps a side's commander after
## the board is built re-resolves the identity and repaints to match — units, the
## property tiles, the HUD name — so a staged commander recolours its army the way
## it would in a real match (plan R3). Real play never calls this: commanders are
## fixed before the board is ever drawn, so _build_view's resolve is the only one.
func _restage_identity() -> void:
	identity = SideIdentity.for_game(game)
	terrain_panel.identity = identity
	_paint_map()
	for unit: Unit in _sprites:
		var sprite: UnitSprite = _sprites[unit]
		sprite.fogged = _is_fogged(unit)
		sprite.setup(unit, game.current_team, identity.atlas_row(unit.team))
	refresh_hud()


# --- overlays ----------------------------------------------------------------


## Highlights reachable cells — a unit's movement range, or where a transport
## could unload. An empty list clears the overlay, so callers never need a
## separate "and now hide it" call.
func paint_move_overlay(cells: Array[Vector2i]) -> void:
	move_overlay.clear()
	for cell in cells:
		move_overlay.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)


## Highlights the cells a unit may fire at. Empty clears, as above.
func paint_attack_overlay(cells: Array[Vector2i]) -> void:
	attack_overlay.clear()
	for cell in cells:
		attack_overlay.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)


## Traces the planned route. A path too short to draw clears the line.
func update_path_line(path: Array[Vector2i]) -> void:
	path_line.clear_points()
	if path.size() < 2:
		return
	for cell in path:
		path_line.add_point(cell_center(cell))


# --- fog ---------------------------------------------------------------------


## Recomputes visibility and repaints the fog layer plus unit visibility.
## Called after every committed action and turn change (not per cursor move).
## With fog off the layer stays clear and nothing is ever hidden; when
## `blacked_out` (a hot-seat handoff) nobody may look and the board is hidden
## entirely.
##
## Only the *cells* are worked out here. Each sprite is then redrawn through
## `refresh_sprite`, which is where hiding a unit is decided — for this pass and
## for every other one.
func refresh_fog(viewing_team: int, blacked_out: bool) -> void:
	fog_layer.clear()
	_viewing_team = viewing_team
	_blacked_out = blacked_out
	_visible_cells = {}
	if game.fog_enabled:
		if not blacked_out:
			_visible_cells = Vision.visible_cells(game, viewing_team)
		for y in map.height:
			for x in map.width:
				var cell := Vector2i(x, y)
				if _visible_cells.has(cell):
					# In view: show the true owner. A capture the gate in
					# repaint_property deferred while the cell was fogged reveals
					# here, so the board never leaks an ownership change the viewer
					# has not scouted, yet shows the truth the instant it is seen.
					repaint_property(cell)
				else:
					fog_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)
	for unit in game.units:
		refresh_sprite(unit)


## Whether the viewing team can see a unit — the question to ask before drawing
## or targeting one. Deliberately not "can it see that cell": a doctrine can hide
## a unit standing somewhere the viewer sees perfectly well, so the two came
## apart. Vision owns the rule, as it owns every other one; this only supplies
## the cells already computed for the fog pass.
func can_see_unit(unit: Unit) -> bool:
	return Vision.can_see_unit(game, _viewing_team, unit, _visible_cells)


## The unit on `cell` the viewing team can actually see, or null when the tile
## reads empty to them — a fogged enemy included. The panel and the menu-opening
## decisions ask this instead of `game.unit_at` so a hidden occupant can't change
## what a click offers and turn an apparently-empty cell into a free fog probe.
## The sim stays the authority on what lands there: a build onto a secretly
## occupied cell is still refused by BuildCommand.validate.
func _visible_unit_at(cell: Vector2i) -> Unit:
	var unit := game.unit_at(cell)
	if unit != null and not can_see_unit(unit):
		return null
	return unit


## Adjacent cells where `transport` (previewed at `dest`) could set `passenger`
## down: the transport must be somewhere it can unload from, the passenger must be
## able to stand on the cell, and the cell must hold no friendly and no visible
## enemy. The vacated origin counts as free, and a hidden enemy is left to foil the
## drop on apply rather than shown here, which would reveal it. A per-passenger
## query because a Lander's two riders need not share a move class. Underscored
## for the same reason as `_can_see_cell` below: Battle is the only caller and
## the view is at its public-method ceiling.
func _drop_cells(transport: Unit, dest: Vector2i, passenger: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if passenger == null or not transport.type.can_unload_from(map.terrain_at(dest).id):
		return cells
	for dir in MovementResolver.DIRECTIONS:
		var cell := dest + dir
		var terrain := map.terrain_at(cell)
		if terrain == null or not terrain.is_passable(passenger.type.move_class):
			continue
		var occupant := game.unit_at(cell)
		if occupant != null and occupant != transport and can_see_unit(occupant):
			continue
		cells.append(cell)
	return cells


## The transport's cargo that has at least one legal drop cell from `dest`, in load
## order. Empty when nothing aboard can step off here — which is how Battle knows
## whether to offer a Drop, and per passenger so each gets its own menu row.
## Underscored with its sibling above; Battle is the only caller.
func _droppable_passengers(transport: Unit, dest: Vector2i) -> Array[Unit]:
	var droppable: Array[Unit] = []
	for passenger in game.cargo_of(transport):
		if not _drop_cells(transport, dest, passenger).is_empty():
			droppable.append(passenger)
	return droppable


## Whether the viewing team may see activity on `cell` — the single authority in
## the view for cell-scoped visibility, as `can_see_unit` is for a unit. Ask it
## before disclosing anything a hidden unit could be doing on the tile, such as a
## capture in progress or (later) a fresh owner. With fog off every cell is
## visible; during a hot-seat blackout none is; otherwise it is whatever the last
## fog pass computed. Kept distinct from `can_see_unit` because a cell can be
## visible while a doctrine hides the unit standing on it, and vice versa.
## Underscored because it is the view's own; BattleAiRunner reaches in for it the
## same way it reaches into Battle's private flow, so as not to add a 21st public
## method here. It is still the one place the answer is computed — re-derive it
## nowhere else.
func _can_see_cell(cell: Vector2i) -> bool:
	if not game.fog_enabled:
		return true
	if _blacked_out:
		return false
	return _visible_cells.has(cell)


## The owner the board tile at `cell` is currently painted for, recovered from its
## atlas row. For a cell in view this equals the live owner (the fog pass just
## repainted it); for a fogged cell it is the viewer's last-seen owner. The
## terrain panel reads this instead of live truth on a hidden cell so its owner
## label names the same side the tile shows — never outing a capture out of sight.
func _last_seen_owner(cell: Vector2i) -> int:
	var row: int = terrain_layer.get_cell_atlas_coords(cell).y
	for team in GameState.TEAMS:
		if identity.atlas_row(team) == row:
			return team
	return MapData.NEUTRAL


# --- HUD and panels ----------------------------------------------------------


func refresh_hud() -> void:
	turn_label.text = (
		"Day %d  -  %s  -  Funds %d"
		% [
			game.day,
			identity.display_name(game.current_team),
			game.funds[game.current_team],
		]
	)
	# The chip belongs to whoever's turn it is. It hides itself for a side with no
	# power, and greys its Fire button for a computer commander — a charged AI
	# still fills the meter, but the click would be refused.
	commander_chip.update_state(
		game.commander_state(game.current_team), game.current_team in ai_teams
	)


func refresh_panel(cell: Vector2i) -> void:
	var hovered := _visible_unit_at(cell)  # hidden enemies stay hidden in the panel too
	var carrying := ""
	if hovered != null:
		var cargo := game.cargo_of(hovered)
		if not cargo.is_empty():
			carrying = cargo[0].type.display_name
	# A capture in progress belongs to whoever is standing on the property, so it
	# stays hidden on a cell the viewer cannot see — otherwise the panel would out
	# an enemy capturing inside your fog.
	var capture_left: int = game.capture_progress.get(cell, -1) if _can_see_cell(cell) else -1
	# The owner label follows the tile, not live truth: a property captured while
	# this cell was fogged keeps its last-seen owner until the viewer sees it, so
	# the panel never names a side change the board is still hiding.
	var owner: int = game.owner_at(cell) if _can_see_cell(cell) else _last_seen_owner(cell)
	terrain_panel.show_tile(
		map.terrain_at(cell), owner, game.current_team, capture_left, hovered, carrying
	)
	terrain_panel.set_side(cursor.position.x < camera.get_screen_center_position().x)
	# The chip is pinned to the top-left and, unlike the terrain panel, has no
	# free corner to flip to — the Day panel owns the other one. So it fades
	# instead: the board reads through it while the cursor is on a tile it covers.
	commander_chip.set_covering_cursor(
		commander_chip.get_global_rect().intersects(_screen_rect_for_cell(cell))
	)


## Shows the attack/counter forecast beside a cell. A null forecast — nothing
## worth previewing under the cursor — hides the panel.
func update_damage_preview(forecast: CombatResolver.Forecast, cell: Vector2i) -> void:
	damage_preview.visible = forecast != null and forecast.can_attack
	if not damage_preview.visible:
		return
	atk_label.text = "Atk %d%%" % forecast.attack_damage
	counter_label.text = (
		"Counter %d%%" % forecast.counter_damage if forecast.counter_damage >= 0 else "No counter"
	)
	var pos := screen_pos_for_cell(cell) + Vector2(4, -34)
	var view := _viewport_size()
	if pos.x > view.x - 100.0:
		pos.x -= 130.0
	damage_preview.position = pos.max(Vector2(4, 4))


# --- cursor and camera geometry ----------------------------------------------


## Moves the cursor sprite and the camera that follows it. The interaction
## state that hangs off a cursor move stays in Battle.
func move_cursor_to(cell: Vector2i) -> void:
	cursor.position = cell_center(cell)
	camera.position = cursor.position


func set_zoom(zoom: float) -> void:
	camera.zoom = Vector2(zoom, zoom)
	_apply_camera_limits()


## The furthest out the player may zoom: just far enough that the whole map is
## in view, with the backdrop filling whatever the map's aspect leaves over. On
## a map smaller than the viewport this sits above the default zoom, so a small
## map starts at its floor. Battle owns the zoom level and clamps against this.
func min_zoom() -> float:
	var map_px := Vector2(map.size() * TILE)
	var view := _viewport_size()
	return minf(view.x / map_px.x, view.y / map_px.y)


## Camera limits pin the view inside the map. On an axis where the view shows
## more than the whole map they expand just enough to centre it instead,
## splitting the exposed backdrop evenly. Floor/ceil keeps the limit span at
## least the visible extent, so the camera is never pushed against one edge.
func _apply_camera_limits() -> void:
	var map_px := Vector2(map.size() * TILE)
	var extra := ((_viewport_size() / camera.zoom.x - map_px) / 2.0).max(Vector2.ZERO)
	camera.limit_left = floori(-extra.x)
	camera.limit_top = floori(-extra.y)
	camera.limit_right = ceili(map_px.x + extra.x)
	camera.limit_bottom = ceili(map_px.y + extra.y)


func _viewport_size() -> Vector2:
	return cursor.get_viewport().get_visible_rect().size


func screen_pos_for_cell(cell: Vector2i) -> Vector2:
	var world := cell_center(cell) + Vector2(TILE, -TILE) / 2.0
	return (world - _screen_center()) * camera.zoom + _viewport_size() / 2.0 + Vector2(6, 0)


## Where the cell is actually drawn, in screen pixels — what a HUD panel has to
## be tested against to know whether it is sitting on top of it.
func _screen_rect_for_cell(cell: Vector2i) -> Rect2:
	var top_left := Vector2(cell * TILE) - _screen_center()
	return Rect2(top_left * camera.zoom + _viewport_size() / 2.0, Vector2(TILE, TILE) * camera.zoom)


## The world point the middle of the screen shows. Anchored to the camera's
## target (unsmoothed) position so UI placed during a camera glide lands where
## the view settles, not where it happens to be.
func _screen_center() -> Vector2:
	var view_size := _viewport_size()
	return Vector2(
		clampf(
			camera.position.x,
			camera.limit_left + view_size.x / (2.0 * camera.zoom.x),
			camera.limit_right - view_size.x / (2.0 * camera.zoom.x)
		),
		clampf(
			camera.position.y,
			camera.limit_top + view_size.y / (2.0 * camera.zoom.y),
			camera.limit_bottom - view_size.y / (2.0 * camera.zoom.y)
		)
	)
