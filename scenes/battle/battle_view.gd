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
var charge_bar: ProgressBar
var charge_label: Label
var power_button: Button

var db: TerrainDB
var map: MapData
var game: GameState
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
	terrain_layer.tile_set = _build_tile_set()
	# The terrain atlas is drawn at 4x the world grid (see TERRAIN_PX), so the
	# layer is scaled back down to keep one cell = TILE. Overlays and the cursor
	# stay at 1x and are unaffected.
	terrain_layer.scale = Vector2.ONE * (float(TILE) / float(TERRAIN_PX))
	move_overlay.tile_set = _build_overlay_tile_set()
	attack_overlay.tile_set = move_overlay.tile_set
	fog_layer.tile_set = move_overlay.tile_set
	_paint_map()
	_spawn_unit_sprites()
	var map_px := Vector2(map.size() * TILE)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map_px.x)
	camera.limit_bottom = int(map_px.y)


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
			atlas.create_tile(Vector2i(terrain.atlas_col, 1))
			atlas.create_tile(Vector2i(terrain.atlas_col, 2))
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


func _paint_map() -> void:
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var terrain := map.terrain_at(cell)
			var row := game.owner_at(cell) if terrain.team_tinted else 0
			terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))


## Recolors one property to its current owner, after a capture.
func repaint_property(cell: Vector2i) -> void:
	var terrain := map.terrain_at(cell)
	if terrain.team_tinted:
		terrain_layer.set_cell(
			cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, game.owner_at(cell))
		)


# --- unit sprites ------------------------------------------------------------


func _spawn_unit_sprites() -> void:
	for unit in game.units:
		spawn_sprite_for(unit)


func spawn_sprite_for(unit: Unit) -> void:
	var sprite: UnitSprite = UNIT_SPRITE_SCENE.instantiate()
	units_root.add_child(sprite)
	sprite.fogged = _is_fogged(unit)
	sprite.setup(unit, game.current_team)
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
				if not _visible_cells.has(cell):
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


# --- HUD and panels ----------------------------------------------------------


func refresh_hud() -> void:
	turn_label.text = (
		"Day %d  -  %s  -  Funds %d"
		% [
			game.day,
			TerrainPanel.TEAM_NAMES.get(game.current_team, str(game.current_team)),
			game.funds[game.current_team],
		]
	)
	_refresh_charge_meter()


## The meter, the label and the button belong to whoever's turn it is. A side
## playing without a commander has no meter at all, so the whole group hides and
## the HUD looks exactly as it did before commanders existed.
func _refresh_charge_meter() -> void:
	var co_state := game.commander_state(game.current_team)
	var showing := co_state.type.has_power()
	charge_bar.visible = showing
	charge_label.visible = showing
	power_button.visible = showing
	if not showing:
		return
	charge_bar.value = co_state.charge_ratio()
	# An active power reads off the meter alone, which is empty either way while
	# it runs — so say so rather than leaving the player guessing.
	if co_state.power_active:
		charge_label.text = "%s  ACTIVE" % co_state.type.power_name
	else:
		charge_label.text = (
			"%s  %d/%d" % [co_state.type.display_name, co_state.charge, co_state.type.power_cost]
		)
	power_button.text = co_state.type.power_name
	# A charged computer opponent that chose not to spend still fills the meter,
	# and the click would be refused anyway — so the button says so up front
	# rather than looking live and doing nothing.
	power_button.disabled = not co_state.is_ready() or game.current_team in ai_teams


func refresh_panel(cell: Vector2i) -> void:
	terrain_panel.show_terrain(
		map.terrain_at(cell), game.owner_at(cell), game.capture_progress.get(cell, -1)
	)
	var hovered := game.unit_at(cell)
	if hovered != null and not can_see_unit(hovered):
		hovered = null  # hidden enemies stay hidden in the panel too
	var carrying := ""
	if hovered != null:
		var cargo := game.cargo_of(hovered)
		if not cargo.is_empty():
			carrying = cargo[0].type.display_name
	terrain_panel.show_unit(hovered, carrying)
	terrain_panel.set_side(cursor.position.x < camera.get_screen_center_position().x)


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


## The furthest out the player may zoom before the map stops filling the view.
## Battle owns the zoom level itself and clamps against this.
func min_zoom() -> float:
	var map_px := Vector2(map.size() * TILE)
	var view := _viewport_size()
	return maxf(view.x / map_px.x, view.y / map_px.y)


func _viewport_size() -> Vector2:
	return cursor.get_viewport().get_visible_rect().size


func screen_pos_for_cell(cell: Vector2i) -> Vector2:
	# Anchor to the camera's target (unsmoothed) position so UI placed during
	# a camera glide lands where the view settles, not where it happens to be.
	var world := cell_center(cell) + Vector2(TILE, -TILE) / 2.0
	var view_size := _viewport_size()
	var center := Vector2(
		clampf(
			camera.position.x,
			view_size.x / (2.0 * camera.zoom.x),
			camera.limit_right - view_size.x / (2.0 * camera.zoom.x)
		),
		clampf(
			camera.position.y,
			view_size.y / (2.0 * camera.zoom.y),
			camera.limit_bottom - view_size.y / (2.0 * camera.zoom.y)
		)
	)
	return (world - center) * camera.zoom + view_size / 2.0 + Vector2(6, 0)
