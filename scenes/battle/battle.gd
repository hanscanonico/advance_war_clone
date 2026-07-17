extends Node2D
## Battle scene root (M2 scope): renders map + units, drives cursor/camera,
## and runs the selection → move → Wait/Cancel flow. All rules live in core/;
## this scene only issues commands and animates the results.

const TILE := 16
const MAP_PATH := "res://maps/first_steps.txt"
const ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"
const OVERLAY_PATH := "res://assets/tiles/overlay.png"
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"
const ATLAS_SOURCE_ID := 0
const MAX_ZOOM := 5.0
const MOVE_STEP_SECONDS := 0.06

const UNIT_SPRITE_SCENE := preload("res://scenes/battle/unit_sprite.tscn")

enum State { IDLE, UNIT_SELECTED, ANIMATING, MENU, TARGETING }

const DIR_ACTIONS: Array = [
	[&"cursor_up", Vector2i.UP],
	[&"cursor_down", Vector2i.DOWN],
	[&"cursor_left", Vector2i.LEFT],
	[&"cursor_right", Vector2i.RIGHT],
]

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var move_overlay: TileMapLayer = $MoveOverlay
@onready var attack_overlay: TileMapLayer = $AttackOverlay
@onready var path_line: Line2D = $PathLine
@onready var units_root: Node2D = $Units
@onready var cursor: Sprite2D = $Cursor
@onready var camera: Camera2D = $Camera2D
@onready var terrain_panel: PanelContainer = %TerrainPanel
@onready var action_menu: ActionMenu = %ActionMenu
@onready var damage_preview: PanelContainer = %DamagePreview
@onready var atk_label: Label = %AtkLabel
@onready var counter_label: Label = %CounterLabel

var db: TerrainDB
var unit_db: UnitDB
var map: MapData
var game: GameState
var cursor_cell := Vector2i.ZERO

var state := State.IDLE
var selected: Unit
var move_range: MovementResolver.MoveRange
var planned_path: Array[Vector2i] = []
var _attack_targets: Array[Vector2i] = []

var _sprites: Dictionary = {}  # Unit -> UnitSprite
var _zoom := 2.0
var _min_zoom := 1.0


func _ready() -> void:
	db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	map = MapData.load_from_file(MAP_PATH, db)
	assert(map != null, "failed to load %s" % MAP_PATH)
	game = GameState.create(map, unit_db, load(DAMAGE_CHART_PATH))
	assert(game != null, "failed to build game state from %s" % MAP_PATH)
	game.rng.randomize()
	terrain_layer.tile_set = _build_tile_set()
	move_overlay.tile_set = _build_overlay_tile_set()
	attack_overlay.tile_set = move_overlay.tile_set
	_paint_map()
	_spawn_unit_sprites()
	action_menu.action_chosen.connect(_on_menu_action)
	_setup_camera()
	var red_cells := map.cells_owned_by(1)
	_set_cursor_cell(red_cells[0] if not red_cells.is_empty() else Vector2i.ZERO)
	camera.position = cursor.position
	camera.reset_smoothing()
	_start_cursor_pulse()
	_check_screenshot_mode()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.ANIMATING or state == State.MENU:
		return  # the menu handles its own input; animations block input
	if event.is_action_pressed(&"zoom_in"):
		_set_zoom(_zoom + 1.0)
	elif event.is_action_pressed(&"zoom_out"):
		_set_zoom(_zoom - 1.0)
	elif event is InputEventMouseMotion:
		var cell := _mouse_cell()
		if map.in_bounds(cell) and cell != cursor_cell:
			_set_cursor_cell(cell)
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _mouse_cell()
		if map.in_bounds(cell):
			if cell != cursor_cell:
				_set_cursor_cell(cell)
			_confirm_at(cursor_cell)
	elif event.is_action_pressed(&"confirm"):
		_confirm_at(cursor_cell)
	elif event.is_action_pressed(&"cancel"):
		_cancel()
	else:
		for dir: Array in DIR_ACTIONS:
			if event.is_action_pressed(dir[0], true):
				var next: Vector2i = cursor_cell + dir[1]
				if map.in_bounds(next):
					_set_cursor_cell(next)
				return


# --- selection / movement flow -----------------------------------------------


func _confirm_at(cell: Vector2i) -> void:
	match state:
		State.IDLE:
			var unit := game.unit_at(cell)
			if unit != null and not unit.acted:
				_select(unit)
		State.UNIT_SELECTED:
			if move_range.has(cell) and move_range.can_stop_at(cell):
				planned_path = move_range.path_to(cell)
				_animate_move()
		State.TARGETING:
			if cell in _attack_targets:
				_execute_attack(cell)


func _cancel() -> void:
	if state == State.UNIT_SELECTED:
		_clear_selection()
	elif state == State.TARGETING:
		_exit_targeting_to_menu()


func _select(unit: Unit) -> void:
	selected = unit
	move_range = MovementResolver.reachable(game, unit)
	planned_path = [unit.cell]
	_paint_move_overlay()
	_update_path_line()
	state = State.UNIT_SELECTED


func _clear_selection() -> void:
	selected = null
	move_range = null
	planned_path = []
	_attack_targets = []
	move_overlay.clear()
	attack_overlay.clear()
	path_line.clear_points()
	damage_preview.visible = false
	state = State.IDLE


func _animate_move() -> void:
	state = State.ANIMATING
	move_overlay.clear()
	path_line.clear_points()
	if planned_path.size() < 2:
		_on_move_animation_done()
		return
	var sprite: UnitSprite = _sprites[selected]
	var tween := create_tween()
	for i in range(1, planned_path.size()):
		tween.tween_property(sprite, "position", _cell_center(planned_path[i]), MOVE_STEP_SECONDS)
	tween.finished.connect(_on_move_animation_done)


func _on_move_animation_done() -> void:
	state = State.MENU
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	_attack_targets = _attackable_cells(selected, dest, planned_path.size() > 1)
	var actions: Array[Dictionary] = []
	if not _attack_targets.is_empty():
		actions.append({"id": &"fire", "label": "Fire"})
	actions.append({"id": &"wait", "label": "Wait"})
	actions.append({"id": &"cancel", "label": "Cancel"})
	action_menu.open(actions, _screen_pos_for_cell(dest))


func _on_menu_action(action: StringName) -> void:
	action_menu.close()
	match action:
		&"fire":
			_enter_targeting()
		&"wait":
			var command := MoveCommand.new(selected, planned_path)
			var error := command.validate(game)
			if error != "":
				# The UI only offers legal paths, so this is a bug guard.
				push_error("MoveCommand rejected: %s" % error)
				_undo_move_preview()
				return
			command.apply(game)
			EventBus.unit_moved.emit(selected)
			_sprites[selected].refresh()
			_clear_selection()
			_refresh_panel()
			_refresh_round_if_exhausted()
		&"cancel":
			_undo_move_preview()


## The move was never committed to the sim, so undo is just snapping the
## sprite back and returning to the range view (AW-style B-cancel).
func _undo_move_preview() -> void:
	_sprites[selected].refresh()
	_paint_move_overlay()
	state = State.UNIT_SELECTED
	_set_cursor_cell(selected.cell)
	planned_path = [selected.cell]
	_update_path_line()


## Placeholder for the M4 TurnManager: when every unit has acted, ready them
## all again so the M2 sandbox never dead-ends.
func _refresh_round_if_exhausted() -> void:
	for unit in game.units:
		if not unit.acted:
			return
	for unit in game.units:
		unit.acted = false
		_sprites[unit].refresh()
	_refresh_panel()


# --- attack flow -------------------------------------------------------------


## Enemy cells the unit could fire at from `dest`. Indirect units lose their
## shot if they moved this turn.
func _attackable_cells(unit: Unit, dest: Vector2i, moved: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var type := unit.type
	if type.max_range <= 0:
		return cells
	if type.min_range > 1 and moved:
		return cells
	for other in game.units:
		if other.team == unit.team:
			continue
		var dist := absi(other.cell.x - dest.x) + absi(other.cell.y - dest.y)
		if dist < type.min_range or dist > type.max_range:
			continue
		if game.damage_chart.can_attack(type.id, other.type.id):
			cells.append(other.cell)
	cells.sort()
	return cells


func _enter_targeting() -> void:
	state = State.TARGETING
	attack_overlay.clear()
	for cell in _attack_targets:
		attack_overlay.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)
	_set_cursor_cell(_attack_targets[0])


func _exit_targeting_to_menu() -> void:
	attack_overlay.clear()
	damage_preview.visible = false
	_on_move_animation_done()  # recomputes targets and reopens the menu


func _execute_attack(target_cell: Vector2i) -> void:
	var target := game.unit_at(target_cell)
	var command := AttackCommand.new(selected, planned_path, target_cell)
	var error := command.validate(game)
	if error != "":
		# The UI only offers legal attacks, so this is a bug guard.
		push_error("AttackCommand rejected: %s" % error)
		_exit_targeting_to_menu()
		return
	var attacker := selected
	attack_overlay.clear()
	damage_preview.visible = false
	path_line.clear_points()
	state = State.ANIMATING
	command.apply(game)
	EventBus.unit_moved.emit(attacker)
	await _animate_combat(command.result, attacker, target)
	_clear_selection()
	_refresh_panel()
	_refresh_round_if_exhausted()


func _animate_combat(
	result: CombatResolver.CombatResult, attacker: Unit, defender: Unit
) -> void:
	var defender_sprite: UnitSprite = _sprites[defender]
	var attacker_sprite: UnitSprite = _sprites[attacker]
	attacker_sprite.refresh()  # snap to the committed destination
	await defender_sprite.flash_hit()
	if result.defender_died:
		_sprites.erase(defender)
		await defender_sprite.die()
	else:
		defender_sprite.refresh()
	if result.countered:
		await attacker_sprite.flash_hit()
	if result.attacker_died:
		_sprites.erase(attacker)
		await attacker_sprite.die()
	else:
		attacker_sprite.refresh()


func _update_damage_preview() -> void:
	var target := game.unit_at(cursor_cell)
	var valid := state == State.TARGETING and target != null and cursor_cell in _attack_targets
	damage_preview.visible = valid
	if not valid:
		return
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	var forecast := CombatResolver.forecast(game, selected, dest, target)
	atk_label.text = "Atk %d%%" % forecast.attack_damage
	counter_label.text = (
		"Counter %d%%" % forecast.counter_damage if forecast.counter_damage >= 0
		else "No counter"
	)
	var pos := _screen_pos_for_cell(cursor_cell) + Vector2(4, -34)
	var view := get_viewport().get_visible_rect().size
	if pos.x > view.x - 100.0:
		pos.x -= 130.0
	damage_preview.position = pos.max(Vector2(4, 4))


# --- rendering ---------------------------------------------------------------


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
			var row := map.owner_at(cell) if terrain.team_tinted else 0
			terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))


func _spawn_unit_sprites() -> void:
	for unit in game.units:
		var sprite: UnitSprite = UNIT_SPRITE_SCENE.instantiate()
		units_root.add_child(sprite)
		sprite.setup(unit)
		_sprites[unit] = sprite


func _paint_move_overlay() -> void:
	move_overlay.clear()
	for cell in move_range.cells():
		move_overlay.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)


func _update_path_line() -> void:
	path_line.clear_points()
	if planned_path.size() < 2:
		return
	for cell in planned_path:
		path_line.add_point(_cell_center(cell))


# --- camera / cursor ---------------------------------------------------------


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


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


func _mouse_cell() -> Vector2i:
	return Vector2i((get_global_mouse_position() / TILE).floor())


func _set_cursor_cell(cell: Vector2i) -> void:
	cursor_cell = cell
	cursor.position = _cell_center(cell)
	camera.position = cursor.position
	_refresh_panel()
	if state == State.UNIT_SELECTED:
		if move_range.has(cell) and move_range.can_stop_at(cell):
			planned_path = move_range.path_to(cell)
		_update_path_line()
	elif state == State.TARGETING:
		_update_damage_preview()
	EventBus.cursor_moved.emit(cell)


func _refresh_panel() -> void:
	terrain_panel.show_terrain(map.terrain_at(cursor_cell), map.owner_at(cursor_cell))
	terrain_panel.show_unit(game.unit_at(cursor_cell))
	terrain_panel.set_side(cursor.position.x < camera.get_screen_center_position().x)


func _screen_pos_for_cell(cell: Vector2i) -> Vector2:
	# Anchor to the camera's target (unsmoothed) position so UI placed during
	# a camera glide lands where the view settles, not where it happens to be.
	var world := _cell_center(cell) + Vector2(TILE, -TILE) / 2.0
	var view_size := get_viewport().get_visible_rect().size
	var center := Vector2(
		clampf(camera.position.x, view_size.x / (2.0 * camera.zoom.x),
			camera.limit_right - view_size.x / (2.0 * camera.zoom.x)),
		clampf(camera.position.y, view_size.y / (2.0 * camera.zoom.y),
			camera.limit_bottom - view_size.y / (2.0 * camera.zoom.y))
	)
	return (world - center) * camera.zoom + view_size / 2.0 + Vector2(6, 0)


func _start_cursor_pulse() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(cursor, "scale", Vector2(1.15, 1.15), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cursor, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- automated verification --------------------------------------------------


## `Godot --path . -- --screenshot=/abs/path.png [--select=x,y | --demo=MODE]`
## boots the scene, optionally drives a demo, saves one frame, and quits.
## --select previews a unit's movement; --demo=attack stops at the targeting
## preview; --demo=resolve fires and captures the post-combat state.
func _check_screenshot_mode() -> void:
	var shot_path := ""
	var select_cell := Vector2i(-1, -1)
	var demo := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			shot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--select="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				select_cell = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--demo="):
			demo = arg.get_slice("=", 1)
	if demo != "":
		_run_attack_demo(demo, shot_path)
		return
	if select_cell.x >= 0:
		_screenshot_demo_select(select_cell)
	if shot_path != "":
		_save_screenshot_and_quit(shot_path)


## Drives the real selection -> menu -> Fire -> target flow on the frontline
## tanks, through the same handlers a player's input reaches.
func _run_attack_demo(mode: String, shot_path: String) -> void:
	await get_tree().process_frame
	game.rng.seed = 2026  # deterministic demo
	_confirm_at(Vector2i(8, 8))  # select the red tank
	_confirm_at(Vector2i(8, 8))  # fire in place
	while state != State.MENU:
		await get_tree().process_frame
	action_menu.choose(&"fire")
	while state != State.TARGETING:
		await get_tree().process_frame
	if mode == "attack":
		if shot_path != "":
			_save_screenshot_and_quit(shot_path)
		return
	_confirm_at(cursor_cell)  # fire at the blue tank
	while state != State.IDLE:
		await get_tree().process_frame
	if shot_path != "":
		_save_screenshot_and_quit(shot_path)


func _screenshot_demo_select(cell: Vector2i) -> void:
	if not map.in_bounds(cell):
		return
	_set_cursor_cell(cell)
	_confirm_at(cell)
	if state != State.UNIT_SELECTED:
		return
	var farthest := cell
	var best_cost := -1
	for candidate in move_range.cells():
		if move_range.can_stop_at(candidate) and move_range.costs[candidate] > best_cost:
			best_cost = move_range.costs[candidate]
			farthest = candidate
	_set_cursor_cell(farthest)


func _save_screenshot_and_quit(path: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("screenshot: saved to %s (err=%d)" % [path, err])
	get_tree().quit()
