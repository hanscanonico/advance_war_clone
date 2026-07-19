class_name Battle
extends Node2D
## Battle scene root: renders map + units, drives cursor/camera, and runs the
## interaction flow — selection, movement, menus, targeting, transport, AI
## turns, and victory. All rules live in core/; this scene only issues commands
## and animates the results.
##
## `confirm_at`, `set_cursor_cell`, and `leave_handoff` are public because they
## are the entry points player input arrives at, and BattleScenarioDriver
## stands in for a player through exactly those.

const MAP_PATH := "res://maps/first_steps.txt"
const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"
const MAX_ZOOM := 5.0
const MOVE_STEP_SECONDS := 0.06
const BANNER_SECONDS := 1.2
const AI_COMMAND_DELAY := 0.2
const AI_MAX_COMMANDS_PER_TURN := 300
## The AI opens its turn just after the turn banner has cleared.
const AI_TURN_START_DELAY := BANNER_SECONDS + 0.1

enum State {
	IDLE,
	UNIT_SELECTED,
	ANIMATING,
	MENU,
	TARGETING,
	DROP_TARGETING,
	VICTORY,
	AI_TURN,
	HANDOFF,
}

const DIR_ACTIONS: Array = [
	[&"cursor_up", Vector2i.UP],
	[&"cursor_down", Vector2i.DOWN],
	[&"cursor_left", Vector2i.LEFT],
	[&"cursor_right", Vector2i.RIGHT],
]

# Only the nodes Battle itself drives. Everything the view draws on is handed
# over in _build_view and deliberately kept out of reach here.
@onready var cursor: Sprite2D = $Cursor
@onready var camera: Camera2D = $Camera2D
@onready var action_menu: ActionMenu = %ActionMenu
@onready var turn_banner: PanelContainer = %TurnBanner
@onready var banner_label: Label = %BannerLabel
@onready var victory_screen: PanelContainer = %VictoryScreen
@onready var victory_label: Label = %VictoryLabel
@onready var victory_sub_label: Label = %VictorySubLabel
@onready var rematch_button: Button = %RematchButton
@onready var menu_button: Button = %MenuButton
@onready var handoff_screen: Panel = %HandoffScreen
@onready var handoff_label: Label = %HandoffLabel
@onready var handoff_button: Button = %HandoffButton

var db: TerrainDB
var unit_db: UnitDB
var map: MapData
var game: GameState
var ai: AIController
## Teams played by the computer. Blue by default; `--hotseat` clears it.
var ai_teams: Array[int] = [2]
var cursor_cell := Vector2i.ZERO

var state := State.IDLE
var selected: Unit
var move_range: MovementResolver.MoveRange
var planned_path: Array[Vector2i] = []
var _attack_targets: Array[Vector2i] = []
var _drop_targets: Array[Vector2i] = []
var _pending_special_actions: Array[Dictionary] = []
var _menu_context: StringName = &"unit"
var _build_cell := Vector2i.ZERO

## Everything this scene draws. Battle decides what happens; the view decides
## how it looks. Nothing here reaches past it into a TileMapLayer or a sprite.
var view: BattleView

var _zoom := 2.0
var _min_zoom := 1.0
var _banner_tween: Tween
## Set only when the command line asks for a scripted capture; see _ready.
var _scenario_driver: BattleScenarioDriver
## True for a run that exists to be photographed. Suppresses the presentation's
## two open-ended animations — see _start_cursor_pulse and _shake_camera — so
## captured frames of the same scenario can be compared to each other.
var _capturing := false


func _ready() -> void:
	db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	ai = AIController.new(unit_db)
	var chart: DamageChart = load(DAMAGE_CHART_PATH)
	# Match setup comes from the main menu; command-line flags override it.
	var map_path := MatchConfig.map_path
	ai_teams = MatchConfig.ai_teams.duplicate()
	var fog := MatchConfig.fog_enabled
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_path = "res://maps/%s.txt" % arg.get_slice("=", 1)
	if "--hotseat" in OS.get_cmdline_user_args():
		ai_teams = []
	if "--fog" in OS.get_cmdline_user_args():
		fog = true
	if MatchConfig.load_save and SaveGame.has_save():
		MatchConfig.load_save = false
		var loaded := SaveGame.load_game(db, unit_db, chart)
		if loaded != null:
			game = loaded.state
			ai_teams = loaded.ai_teams
			map = game.map
	if game == null:
		map = MapData.load_from_file(map_path, db)
		if map == null and map_path != MAP_PATH:
			push_error("failed to load %s; falling back to %s" % [map_path, MAP_PATH])
			map_path = MAP_PATH
			map = MapData.load_from_file(map_path, db)
		assert(map != null, "failed to load %s" % map_path)
		game = GameState.create(map, unit_db, chart)
		assert(game != null, "failed to build game state from %s" % map_path)
		game.map_path = map_path
		game.fog_enabled = fog
		game.rng.randomize()
	view = _build_view()
	view.setup()
	action_menu.action_chosen.connect(_on_menu_action)
	rematch_button.pressed.connect(_rematch)
	menu_button.pressed.connect(_go_to_main_menu)
	handoff_button.pressed.connect(leave_handoff)
	_setup_camera()
	set_cursor_cell(Vector2i.ZERO)
	# Dev-only capture flows. The driver is held for the whole scene: `run`
	# awaits, and a RefCounted nobody references is freed mid-scenario.
	var driver := BattleScenarioDriver.new(self)
	_capturing = driver.requested()
	# The cursor pulse loops forever, so a captured frame catches it at whatever
	# phase the tween happens to be in. That alone made otherwise identical
	# frames differ, which is exactly the noise that hides a real regression —
	# so a run that exists to be photographed doesn't start it.
	if not _capturing:
		_start_cursor_pulse()
	_on_turn_started()  # day 1 gets the same banner/cursor/event as every turn
	camera.position = cursor.position
	camera.reset_smoothing()
	if _capturing:
		_scenario_driver = driver
		_scenario_driver.run()


## Hands the view the nodes it draws on. Assignment rather than a constructor
## argument list keeps the dependency one-way: the view never learns what a
## Battle is.
func _build_view() -> BattleView:
	var built := BattleView.new()
	built.terrain_layer = $TerrainLayer
	built.move_overlay = $MoveOverlay
	built.attack_overlay = $AttackOverlay
	built.fog_layer = $FogLayer
	built.path_line = $PathLine
	built.units_root = $Units
	built.cursor = cursor
	built.camera = camera
	built.terrain_panel = %TerrainPanel
	built.damage_preview = %DamagePreview
	built.atk_label = %AtkLabel
	built.counter_label = %CounterLabel
	built.turn_label = %TurnLabel
	built.db = db
	built.map = map
	built.game = game
	return built


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Replays the setup of the match actually running — including one resumed
## from a save — rather than whatever the menu last wrote to MatchConfig.
func _rematch() -> void:
	MatchConfig.map_path = game.map_path
	MatchConfig.fog_enabled = game.fog_enabled
	MatchConfig.ai_teams = ai_teams.duplicate()
	MatchConfig.load_save = false
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.HANDOFF:
		# Only "I'm ready" gets through while the device is being passed over.
		var clicked := (
			event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed
		)
		if event.is_action_pressed(&"confirm") or clicked:
			leave_handoff()
		return
	if state in [State.ANIMATING, State.MENU, State.VICTORY, State.AI_TURN]:
		return  # the menu handles its own input; the rest block input entirely
	if event.is_action_pressed(&"zoom_in"):
		_set_zoom(_zoom + 1.0)
	elif event.is_action_pressed(&"zoom_out"):
		_set_zoom(_zoom - 1.0)
	elif event is InputEventMouseMotion:
		var cell := _mouse_cell()
		if map.in_bounds(cell) and cell != cursor_cell:
			set_cursor_cell(cell)
	elif (
		event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	):
		var cell := _mouse_cell()
		if map.in_bounds(cell):
			if cell != cursor_cell:
				set_cursor_cell(cell)
			confirm_at(cursor_cell)
	elif event.is_action_pressed(&"confirm"):
		confirm_at(cursor_cell)
	elif event.is_action_pressed(&"cancel"):
		_cancel()
	else:
		for dir: Array in DIR_ACTIONS:
			if event.is_action_pressed(dir[0], true):
				var next: Vector2i = cursor_cell + dir[1]
				if map.in_bounds(next):
					set_cursor_cell(next)
				return


# --- selection / movement flow -----------------------------------------------


func confirm_at(cell: Vector2i) -> void:
	match state:
		State.IDLE:
			var unit := game.unit_at(cell)
			if unit != null and unit.team == game.current_team and not unit.acted:
				_select(unit)
			elif _is_own_empty_base(cell):
				_open_build_menu(cell)
			elif unit == null:
				_open_map_menu()
		State.UNIT_SELECTED:
			if move_range.has(cell) and move_range.can_stop_at(cell):
				planned_path = move_range.path_to(cell)
				_animate_move()
			elif move_range.has(cell):
				# Occupied but reachable: maybe a Load or Join destination.
				var special := _special_dest_actions(cell)
				if not special.is_empty():
					_pending_special_actions = special
					planned_path = move_range.path_to(cell)
					_animate_move()
		State.TARGETING:
			if cell in _attack_targets:
				_execute_attack(cell)
		State.DROP_TARGETING:
			if cell in _drop_targets:
				_execute_drop(cell)


func _cancel() -> void:
	if state == State.UNIT_SELECTED:
		_clear_selection()
	elif state == State.TARGETING:
		_exit_targeting_to_menu()
	elif state == State.DROP_TARGETING:
		view.paint_move_overlay([])
		_drop_targets = []
		_on_move_animation_done()  # back to the unit menu


## Menu entries offered when confirming onto a reachable friendly-occupied
## cell: boarding a transport with room, or merging into a damaged twin.
## The commands themselves decide what is legal, so the menu never drifts
## from core/'s rules.
func _special_dest_actions(cell: Vector2i) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var path := move_range.path_to(cell)
	if path.is_empty():
		return actions
	if LoadCommand.new(selected, path).validate(game) == "":
		actions.append({"id": &"load", "label": "Load"})
	if JoinCommand.new(selected, path).validate(game) == "":
		actions.append({"id": &"join", "label": "Join"})
	return actions


func _select(unit: Unit) -> void:
	Sfx.play(&"select")
	selected = unit
	move_range = MovementResolver.reachable(game, unit)
	planned_path = [unit.cell]
	view.paint_move_overlay(move_range.cells())
	view.update_path_line(planned_path)
	state = State.UNIT_SELECTED


func _clear_selection() -> void:
	selected = null
	move_range = null
	planned_path = []
	_attack_targets = []
	view.paint_move_overlay([])
	view.paint_attack_overlay([])
	view.update_path_line([])
	view.update_damage_preview(null, cursor_cell)
	state = State.IDLE
	_refresh_fog()


func _animate_move() -> void:
	state = State.ANIMATING
	view.paint_move_overlay([])
	view.update_path_line([])
	await _animate_path(view.sprite_for(selected), planned_path)
	_on_move_animation_done()


## Tweens a sprite along a path without touching the sim. Awaitable.
func _animate_path(sprite: UnitSprite, path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	Sfx.play(&"move", -6.0)
	var tween := create_tween()
	for i in range(1, path.size()):
		tween.tween_property(sprite, "position", BattleView.cell_center(path[i]), MOVE_STEP_SECONDS)
	await tween.finished


func _on_move_animation_done() -> void:
	state = State.MENU
	_menu_context = &"unit"
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	if not _pending_special_actions.is_empty():
		# Load/Join destination: only the special action (and Cancel) applies.
		var special := _pending_special_actions
		_pending_special_actions = []
		special.append({"id": &"cancel", "label": "Cancel"})
		action_menu.open(special, view.screen_pos_for_cell(dest))
		return
	_attack_targets = _attackable_cells(selected, dest, planned_path.size() > 1)
	var actions: Array[Dictionary] = []
	if not _attack_targets.is_empty():
		actions.append({"id": &"fire", "label": "Fire"})
	var dest_terrain := map.terrain_at(dest)
	if (
		selected.type.can_capture
		and dest_terrain.is_property
		and game.owner_at(dest) != selected.team
	):
		actions.append({"id": &"capture", "label": "Capture"})
	if not game.cargo_of(selected).is_empty() and not _drop_cells(dest).is_empty():
		actions.append({"id": &"drop", "label": "Drop"})
	if (
		selected.type.can_resupply
		and not SupplyCommand.new(selected, planned_path).adjacent_friendlies(game, dest).is_empty()
	):
		actions.append({"id": &"supply", "label": "Supply"})
	actions.append({"id": &"wait", "label": "Wait"})
	actions.append({"id": &"cancel", "label": "Cancel"})
	action_menu.open(actions, view.screen_pos_for_cell(dest))


func _on_menu_action(action: StringName) -> void:
	action_menu.close()
	match _menu_context:
		&"unit":
			_handle_unit_action(action)
		&"base":
			_handle_build_action(action)
		&"map":
			_handle_map_action(action)


func _handle_unit_action(action: StringName) -> void:
	match action:
		&"fire":
			_enter_targeting()
		&"drop":
			_enter_drop_targeting()
		&"load":
			var command := LoadCommand.new(selected, planned_path)
			var error := command.validate(game)
			if error != "":
				push_error("LoadCommand rejected: %s" % error)
				_undo_move_preview()
				return
			command.apply(game)
			EventBus.unit_moved.emit(selected)
			view.refresh_sprite(selected)  # hides the boarded sprite
			_clear_selection()
			_refresh_panel()
		&"join":
			var command := JoinCommand.new(selected, planned_path)
			var error := command.validate(game)
			if error != "":
				push_error("JoinCommand rejected: %s" % error)
				_undo_move_preview()
				return
			var dest: Vector2i = planned_path[planned_path.size() - 1]
			var mover_sprite := view.release_sprite(selected)
			command.apply(game)
			mover_sprite.die()  # fade the merged-away sprite; fire and forget
			view.refresh_sprite(game.unit_at(dest))
			_clear_selection()
			_refresh_panel()
		&"supply":
			var command := SupplyCommand.new(selected, planned_path)
			var error := command.validate(game)
			if error != "":
				push_error("SupplyCommand rejected: %s" % error)
				_undo_move_preview()
				return
			command.apply(game)
			EventBus.unit_moved.emit(selected)
			view.refresh_sprite(selected)
			_clear_selection()
			_refresh_panel()
		&"capture":
			var command := CaptureCommand.new(selected, planned_path)
			var error := command.validate(game)
			if error != "":
				# The UI only offers legal captures, so this is a bug guard.
				push_error("CaptureCommand rejected: %s" % error)
				_undo_move_preview()
				return
			var dest: Vector2i = planned_path[planned_path.size() - 1]
			command.apply(game)
			EventBus.unit_moved.emit(selected)
			if game.owner_at(dest) == selected.team:
				EventBus.property_captured.emit(dest, selected.team)
				view.repaint_property(dest)
			view.refresh_sprite(selected)
			_clear_selection()
			_refresh_panel()
			_refresh_hud()
			if game.winner != 0:
				_enter_victory()
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
			view.refresh_sprite(selected)
			_clear_selection()
			_refresh_panel()
		&"cancel":
			_undo_move_preview()


func _handle_build_action(action: StringName) -> void:
	if action == &"cancel":
		state = State.IDLE
		return
	var command := BuildCommand.new(game.current_team, unit_db.by_id(action), _build_cell)
	var error := command.validate(game)
	if error != "":
		push_error("BuildCommand rejected: %s" % error)
		state = State.IDLE
		return
	command.apply(game)
	view.spawn_sprite_for(command.built_unit)
	EventBus.unit_built.emit(command.built_unit)
	state = State.IDLE
	_refresh_fog()  # the new unit lifts fog around its base straight away
	_refresh_panel()
	_refresh_hud()


func _handle_map_action(action: StringName) -> void:
	state = State.IDLE
	if action == &"save":
		if SaveGame.save(game, ai_teams):
			_show_banner("Saved")
		return
	if action != &"end_turn":
		return
	var command := EndTurnCommand.new()
	var error := command.validate(game)
	if error != "":
		push_error("EndTurnCommand rejected: %s" % error)
		return
	command.apply(game)
	_on_turn_started()


func _is_own_empty_base(cell: Vector2i) -> bool:
	return (
		map.terrain_at(cell).id == &"base"
		and game.owner_at(cell) == game.current_team
		and game.unit_at(cell) == null
	)


func _open_build_menu(cell: Vector2i) -> void:
	_menu_context = &"base"
	_build_cell = cell
	state = State.MENU
	var actions: Array[Dictionary] = []
	for unit_type in unit_db.all():
		(
			actions
			. append(
				{
					"id": unit_type.id,
					"label": "%s  %d" % [unit_type.display_name, unit_type.cost],
					"disabled": game.funds[game.current_team] < unit_type.cost,
					"icon": UnitSprite.texture_for(unit_type, game.current_team),
				}
			)
		)
	actions.append({"id": &"cancel", "label": "Cancel"})
	action_menu.open(actions, view.screen_pos_for_cell(cell))


func _open_map_menu() -> void:
	_menu_context = &"map"
	state = State.MENU
	(
		action_menu
		. open(
			[
				{"id": &"end_turn", "label": "End Turn"},
				{"id": &"save", "label": "Save"},
				{"id": &"cancel", "label": "Cancel"},
			],
			view.screen_pos_for_cell(cursor_cell)
		)
	)


func _on_turn_started() -> void:
	view.set_active_team(game.current_team)
	if _needs_handoff():
		_enter_handoff()
		return
	_begin_turn()


## Everything the incoming team is allowed to see, run once the device has
## actually changed hands (immediately, outside fogged hot-seat).
func _begin_turn() -> void:
	_refresh_fog()
	_refresh_hud()
	_refresh_panel()
	Sfx.play(&"fanfare", -8.0)
	_show_banner(
		(
			"Day %d - %s"
			% [
				game.day,
				TerrainPanel.TEAM_NAMES.get(game.current_team, str(game.current_team)),
			]
		)
	)
	var homes := game.properties_of(game.current_team)
	if not homes.is_empty():
		set_cursor_cell(homes[0])
	EventBus.turn_started.emit(game.current_team, game.day)
	if game.winner == 0 and game.current_team in ai_teams:
		state = State.AI_TURN
		_run_ai_turn()
	else:
		state = State.IDLE


## Fogged hot-seat only: two humans sharing one screen must not see each
## other's vision, so the incoming player confirms before anything is painted.
## AI turns and fog-off matches never gate.
func _needs_handoff() -> bool:
	if not game.fog_enabled or game.winner != 0:
		return false
	if game.current_team in ai_teams:
		return false
	var humans := 0
	for team in GameState.TEAMS:
		if team not in ai_teams:
			humans += 1
	return humans > 1


func _enter_handoff() -> void:
	state = State.HANDOFF
	hide_banner()
	_refresh_fog()  # blanks the outgoing team's vision before the panel goes up
	handoff_label.text = (
		"%s — press confirm when ready"
		% TerrainPanel.TEAM_NAMES.get(game.current_team, str(game.current_team))
	)
	handoff_screen.show()
	handoff_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	handoff_button.grab_focus()


func leave_handoff() -> void:
	if state != State.HANDOFF:
		return
	handoff_screen.hide()
	state = State.IDLE  # _begin_turn paints the incoming team's vision, not a blackout
	_begin_turn()


## The perspective fog is drawn from: the human whose turn it is, or the
## first human team while the AI plays. The AI itself deliberately sees
## everything — a simple, openly-cheating opponent instead of a guessing one.
func _viewing_team() -> int:
	if game.current_team not in ai_teams:
		return game.current_team
	for team in GameState.TEAMS:
		if team not in ai_teams:
			return team
	return game.current_team


## Repaints fog after every committed action and turn change (not per cursor
## move). During a hot-seat handoff nobody may look, so the board is blacked
## out entirely — that is a flow decision, so it is made here and the view is
## told; working out what is visible is Vision's job, and drawing it is the
## view's.
func _refresh_fog() -> void:
	view.refresh_fog(_viewing_team(), state == State.HANDOFF)


# --- AI turns ----------------------------------------------------------------


## Plays the whole AI turn: plan one command, animate it, repeat until the AI
## ends its turn. The command cap is a safety net so a planner bug can never
## hang the match.
func _run_ai_turn() -> void:
	await get_tree().create_timer(AI_TURN_START_DELAY).timeout
	for i in AI_MAX_COMMANDS_PER_TURN:
		if game.winner != 0:
			_leave_ai_turn()
			return
		var command := ai.plan_next_command(game)
		var error := command.validate(game)
		if error != "":
			push_error("AI command rejected (%s); ending the AI turn" % error)
			command = EndTurnCommand.new()
			if command.validate(game) != "":
				_leave_ai_turn()
				return
		var ended := command is EndTurnCommand
		await _execute_ai_command(command)
		if game.winner != 0:
			_leave_ai_turn()
			return
		if ended:
			return
		await get_tree().create_timer(AI_COMMAND_DELAY).timeout
	push_error("AI hit the per-turn command cap; forcing end of turn")
	var end_turn := EndTurnCommand.new()
	if end_turn.validate(game) == "":
		await _execute_ai_command(end_turn)
	else:
		_leave_ai_turn()


## Every bail-out from the AI loop lands here, so a planner bug can never leave
## the scene stuck in AI_TURN with all input blocked and no banner.
func _leave_ai_turn() -> void:
	if game.winner != 0:
		_enter_victory()
	else:
		state = State.IDLE


## Applies one AI command with the same animations the player flow uses.
## Note: Attack/Capture are checked before Move because each is its own
## Command subclass; the cursor follows so the player can watch.
func _execute_ai_command(command: Command) -> void:
	if command is AttackCommand:
		var attack := command as AttackCommand
		var target := game.unit_at(attack.target_cell)
		set_cursor_cell(attack.path[attack.path.size() - 1])
		await _animate_path(view.sprite_for(attack.unit), attack.path)
		set_cursor_cell(attack.target_cell)
		command.apply(game)
		EventBus.unit_moved.emit(attack.unit)
		await _animate_combat(attack.result, attack.unit, target)
	elif command is CaptureCommand:
		var capture := command as CaptureCommand
		var dest: Vector2i = capture.path[capture.path.size() - 1]
		set_cursor_cell(dest)
		await _animate_path(view.sprite_for(capture.unit), capture.path)
		command.apply(game)
		EventBus.unit_moved.emit(capture.unit)
		if game.owner_at(dest) == capture.unit.team:
			EventBus.property_captured.emit(dest, capture.unit.team)
			view.repaint_property(dest)
		view.refresh_sprite(capture.unit)
	elif command is MoveCommand:
		var move := command as MoveCommand
		set_cursor_cell(move.path[move.path.size() - 1])
		await _animate_path(view.sprite_for(move.unit), move.path)
		command.apply(game)
		EventBus.unit_moved.emit(move.unit)
		view.refresh_sprite(move.unit)
	elif command is BuildCommand:
		var build := command as BuildCommand
		set_cursor_cell(build.cell)
		command.apply(game)
		view.spawn_sprite_for(build.built_unit)
		EventBus.unit_built.emit(build.built_unit)
	elif command is EndTurnCommand:
		command.apply(game)
		_on_turn_started()
	_refresh_fog()
	_refresh_panel()
	_refresh_hud()


func _enter_victory() -> void:
	state = State.VICTORY
	hide_banner()
	Sfx.play(&"fanfare")
	victory_label.text = "%s wins!" % TerrainPanel.TEAM_NAMES.get(game.winner, str(game.winner))
	victory_sub_label.text = "Day %d" % game.day
	victory_screen.show()
	victory_screen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rematch_button.grab_focus()


## Shows the banner immediately and cancels any pending auto-hide.
func _set_banner(text: String) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner_label.text = text
	turn_banner.show()
	turn_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _show_banner(text: String) -> void:
	_set_banner(text)
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_callback(turn_banner.hide)


## Dismisses the banner now, cancelling any pending auto-hide.
func hide_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	turn_banner.hide()


func _refresh_hud() -> void:
	view.refresh_hud()


## The move was never committed to the sim, so undo is just snapping the
## sprite back and returning to the range view (AW-style B-cancel).
func _undo_move_preview() -> void:
	view.refresh_sprite(selected)
	view.paint_move_overlay(move_range.cells())
	state = State.UNIT_SELECTED
	set_cursor_cell(selected.cell)
	planned_path = [selected.cell]
	view.update_path_line(planned_path)


# --- attack flow -------------------------------------------------------------


## Enemy cells the unit could fire at from `dest`. Indirect units lose their
## shot if they moved this turn, a dry unit has no shot at all, and carried
## enemies are not on the board to be shot at.
func _attackable_cells(unit: Unit, dest: Vector2i, moved: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var type := unit.type
	if type.max_range <= 0 or not unit.has_ammo():
		return cells
	if type.min_range > 1 and moved:
		return cells
	for other in game.units:
		if other.team == unit.team or other.carrier != null:
			continue
		if not view.can_see(other.cell):
			continue  # the player cannot target what they cannot see
		var dist := absi(other.cell.x - dest.x) + absi(other.cell.y - dest.y)
		if dist < type.min_range or dist > type.max_range:
			continue
		if game.damage_chart.can_attack(type.id, other.type.id):
			cells.append(other.cell)
	cells.sort()
	return cells


func _enter_targeting() -> void:
	state = State.TARGETING
	view.paint_attack_overlay(_attack_targets)
	set_cursor_cell(_attack_targets[0])


func _exit_targeting_to_menu() -> void:
	view.paint_attack_overlay([])
	view.update_damage_preview(null, cursor_cell)
	_on_move_animation_done()  # recomputes targets and reopens the menu


# --- transport flow ----------------------------------------------------------


## Adjacent cells where the selected transport (previewed at `dest`) could
## unload its passenger. The vacated origin cell counts as free.
func _drop_cells(dest: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var cargo := game.cargo_of(selected)
	if cargo.is_empty():
		return cells
	for dir in MovementResolver.DIRECTIONS:
		var cell := dest + dir
		var terrain := map.terrain_at(cell)
		if terrain == null or not terrain.is_passable(cargo[0].type.move_class):
			continue
		var occupant := game.unit_at(cell)
		if occupant != null and occupant != selected:
			continue
		cells.append(cell)
	return cells


func _enter_drop_targeting() -> void:
	state = State.DROP_TARGETING
	_drop_targets = _drop_cells(planned_path[planned_path.size() - 1])
	view.paint_move_overlay(_drop_targets)
	set_cursor_cell(_drop_targets[0])


func _execute_drop(drop_cell: Vector2i) -> void:
	var command := DropCommand.new(selected, planned_path, drop_cell)
	var error := command.validate(game)
	if error != "":
		# The UI only offers legal drops, so this is a bug guard.
		push_error("DropCommand rejected: %s" % error)
		_cancel()
		return
	var passenger: Unit = game.cargo_of(selected)[0]
	var transport := selected
	command.apply(game)
	EventBus.unit_moved.emit(transport)
	view.refresh_sprite(transport)
	view.refresh_sprite(passenger)  # reappears, exhausted, at the drop cell
	_drop_targets = []
	_clear_selection()
	_refresh_panel()


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
	view.paint_attack_overlay([])
	view.update_damage_preview(null, cursor_cell)
	view.update_path_line([])
	state = State.ANIMATING
	command.apply(game)
	EventBus.unit_moved.emit(attacker)
	await _animate_combat(command.result, attacker, target)
	_clear_selection()
	_refresh_panel()
	_refresh_hud()
	if game.winner != 0:
		_enter_victory()


func _animate_combat(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	var defender_sprite := view.sprite_for(defender)
	var attacker_sprite := view.sprite_for(attacker)
	attacker_sprite.refresh()  # snap to the committed destination
	Sfx.play(&"shot")
	await defender_sprite.flash_hit()
	_shake_camera()
	if result.defender_died:
		Sfx.play(&"explosion")
		view.release_sprite(defender)
		await defender_sprite.die()
	else:
		defender_sprite.refresh()
	if result.countered:
		Sfx.play(&"shot")
		await attacker_sprite.flash_hit()
	if result.attacker_died:
		view.release_sprite(attacker)
		await attacker_sprite.die()
	else:
		attacker_sprite.refresh()
	view.reap_dead_sprites()


## Whether a damage forecast applies at all is a flow question — only the
## targeting state, with a real target under the cursor, has one to show.
func _update_damage_preview() -> void:
	var target := game.unit_at(cursor_cell)
	if state != State.TARGETING or target == null or cursor_cell not in _attack_targets:
		view.update_damage_preview(null, cursor_cell)
		return
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	view.update_damage_preview(CombatResolver.forecast(game, selected, dest, target), cursor_cell)


# --- camera / cursor ---------------------------------------------------------


## How far the player may zoom out depends on the viewport, so the clamp is
## worked out here; the view owns the camera itself.
func _setup_camera() -> void:
	_min_zoom = view.min_zoom()
	_set_zoom(_zoom)


func _set_zoom(zoom: float) -> void:
	_zoom = clampf(zoom, ceilf(_min_zoom * 100.0) / 100.0, MAX_ZOOM)
	view.set_zoom(_zoom)


func _mouse_cell() -> Vector2i:
	return Vector2i((get_global_mouse_position() / BattleView.TILE).floor())


func set_cursor_cell(cell: Vector2i) -> void:
	cursor_cell = cell
	view.move_cursor_to(cell)
	_refresh_panel()
	if state == State.UNIT_SELECTED:
		if move_range.has(cell) and move_range.can_stop_at(cell):
			planned_path = move_range.path_to(cell)
		view.update_path_line(planned_path)
	elif state == State.TARGETING:
		_update_damage_preview()
	EventBus.cursor_moved.emit(cell)


func _refresh_panel() -> void:
	view.refresh_panel(cursor_cell, _viewing_team())


## Brief camera jitter on combat hits. Presentation-only randomness: this
## must never touch game.rng, which is reserved for deterministic sim luck.
##
## Skipped while capturing. The shake is still mid-tween when a frame is taken,
## so it offsets the whole board by a few pixels and makes two otherwise
## identical captures differ everywhere — noise that would hide a real
## rendering regression.
func _shake_camera(strength: float = 3.0) -> void:
	if _capturing:
		return
	var tween := create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, 0.04)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.04)


func _start_cursor_pulse() -> void:
	var tween := create_tween().set_loops()
	(
		tween
		. tween_property(cursor, "scale", Vector2(1.15, 1.15), 0.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	tween.tween_property(cursor, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
