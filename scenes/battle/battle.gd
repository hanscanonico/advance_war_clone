extends Node2D
## Battle scene root (M1 scope): paints the map, drives cursor + camera, and
## feeds the terrain info panel. All game state lives in core/ classes; this
## scene only presents it.

const TILE := 16
const MAP_PATH := "res://maps/first_steps.txt"
const ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"
const ATLAS_SOURCE_ID := 0
const MAX_ZOOM := 5.0

const DIR_ACTIONS: Array = [
	[&"cursor_up", Vector2i.UP],
	[&"cursor_down", Vector2i.DOWN],
	[&"cursor_left", Vector2i.LEFT],
	[&"cursor_right", Vector2i.RIGHT],
]

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var cursor: Sprite2D = $Cursor
@onready var camera: Camera2D = $Camera2D
@onready var terrain_panel: PanelContainer = %TerrainPanel

var db: TerrainDB
var map: MapData
var cursor_cell := Vector2i.ZERO

var _zoom := 2.0
var _min_zoom := 1.0


func _ready() -> void:
	db = TerrainDB.load_default()
	map = MapData.load_from_file(MAP_PATH, db)
	assert(map != null, "failed to load %s" % MAP_PATH)
	terrain_layer.tile_set = _build_tile_set()
	_paint_map()
	_setup_camera()
	var red_cells := map.cells_owned_by(1)
	_set_cursor_cell(red_cells[0] if not red_cells.is_empty() else Vector2i.ZERO)
	camera.position = cursor.position
	camera.reset_smoothing()
	_start_cursor_pulse()
	_check_screenshot_mode()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"zoom_in"):
		_set_zoom(_zoom + 1.0)
	elif event.is_action_pressed(&"zoom_out"):
		_set_zoom(_zoom - 1.0)
	elif event is InputEventMouseMotion:
		var cell := Vector2i((get_global_mouse_position() / TILE).floor())
		if map.in_bounds(cell) and cell != cursor_cell:
			_set_cursor_cell(cell)
	else:
		for dir: Array in DIR_ACTIONS:
			if event.is_action_pressed(dir[0], true):
				var next: Vector2i = cursor_cell + dir[1]
				if map.in_bounds(next):
					_set_cursor_cell(next)
				return


## The TileSet is derived from TerrainDB at runtime: one atlas column per
## terrain, team-colored rows for properties. No hand-maintained .tres TileSet.
func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(ATLAS_PATH)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	for terrain in db.all():
		atlas.create_tile(Vector2i(terrain.atlas_col, 0))
		if terrain.team_tinted:
			atlas.create_tile(Vector2i(terrain.atlas_col, 1))
			atlas.create_tile(Vector2i(terrain.atlas_col, 2))
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


func _paint_map() -> void:
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var terrain := map.terrain_at(cell)
			var row := map.owner_at(cell) if terrain.team_tinted else 0
			terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))


func _setup_camera() -> void:
	var map_px := Vector2(map.size() * TILE)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map_px.x)
	camera.limit_bottom = int(map_px.y)
	var view := get_viewport().get_visible_rect().size
	_min_zoom = maxf(view.x / map_px.x, view.y / map_px.y)
	_set_zoom(_zoom)


func _set_zoom(zoom: float) -> void:
	_zoom = clampf(zoom, ceilf(_min_zoom * 100.0) / 100.0, MAX_ZOOM)
	camera.zoom = Vector2(_zoom, _zoom)


func _set_cursor_cell(cell: Vector2i) -> void:
	cursor_cell = cell
	cursor.position = Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0
	camera.position = cursor.position
	terrain_panel.show_terrain(map.terrain_at(cell), map.owner_at(cell))
	terrain_panel.set_side(cursor.position.x < camera.get_screen_center_position().x)
	EventBus.cursor_moved.emit(cell)


func _start_cursor_pulse() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(cursor, "scale", Vector2(1.15, 1.15), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cursor, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## `Godot --path . -- --screenshot=/abs/path.png` boots the scene, saves one
## frame, and quits. Used for automated visual verification.
func _check_screenshot_mode() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_save_screenshot_and_quit(arg.get_slice("=", 1))


func _save_screenshot_and_quit(path: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("screenshot: saved to %s (err=%d)" % [path, err])
	get_tree().quit()
