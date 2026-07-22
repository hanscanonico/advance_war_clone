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

const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const MAX_ZOOM := 5.0

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
	INFO,
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
@onready var victory_screen: PanelContainer = %VictoryScreen
@onready var victory_portrait: TextureRect = %VictoryPortrait
@onready var victory_faction_label: Label = %VictoryFactionLabel
@onready var victory_label: Label = %VictoryLabel
@onready var victory_sub_label: Label = %VictorySubLabel
@onready var rematch_button: Button = %RematchButton
@onready var menu_button: Button = %MenuButton
@onready var handoff_screen: Panel = %HandoffScreen
@onready var handoff_label: Label = %HandoffLabel
@onready var handoff_button: Button = %HandoffButton
@onready var commander_info_sheet: CommanderInfoSheet = %CommanderInfoSheet

var db: TerrainDB
var unit_db: UnitDB
var commander_db: CommanderDB
var map: MapData
var game: GameState
## team -> AIController. One planner per team rather than one for the scene:
## a normal match gives both entries the same tier's planner and nothing changes,
## while watch mode (balance plan BS3) can put a different commander *and* a
## different tier on each side and have each plan with its own profile and its
## own per-turn threat map.
var planners: Dictionary = {}
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
## Everything this scene animates. Hands it an outcome that is already decided;
## it never picks one.
var animator: BattleAnimator
## Plays computer turns — the AI's side of the interaction flow. Held for the
## whole scene; `run()` is fired when a computer team's turn opens.
var _ai_runner: BattleAiRunner

var _zoom := 2.0
var _min_zoom := 1.0
## Set only when the command line asks for a scripted capture; see _ready.
var _scenario_driver: BattleScenarioDriver
## True for a run that exists to be photographed. Suppresses the presentation's
## two open-ended animations — see BattleAnimator — so captured frames of the
## same scenario can be compared to each other.
var _capturing := false
## True for a `make balance-watch` run: both sides are the computer's and the
## match came from a Balance Lab spec. Makes the scene announce its result and
## exit, which is what turns BS3's replay-fidelity check into a diff.
var _watching := false
## Watch mode's day cap, from `--days=`. Read **only** while `_watching`: normal
## play has no day limit and must not grow one, so a hot-seat or player-vs-AI
## match is untouched by this.
var _watch_days_cap := BalanceMatchEngine.DEFAULT_DAYS
## The team the victory lockup and the watch line report. `game.winner` for a
## match the board decided; a watched match stopped by the day cap is scored on
## BalanceMatchEngine.tiebreak instead — the harness's own authority, so the
## window and the CSV row agree — and that scored winner is not sim state.
var _result_winner := 0


func _ready() -> void:
	db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	commander_db = CommanderDB.load_default()
	_ai_runner = BattleAiRunner.new(self)
	# Which match this is, BattleSetup decides; from here the scene just runs it.
	var built := BattleSetup.build(db, unit_db, commander_db)
	map = built.map
	game = built.game
	ai_teams = built.ai_teams
	_watching = built.watching
	_watch_days_cap = built.days_cap
	_build_planners(built)
	view = _build_view()
	view.setup()
	animator = _build_animator()
	action_menu.action_chosen.connect(_on_menu_action)
	view.commander_chip.fire_button.pressed.connect(_fire_command_power)
	rematch_button.pressed.connect(_rematch)
	menu_button.pressed.connect(_go_to_main_menu)
	handoff_button.pressed.connect(leave_handoff)
	commander_info_sheet.closed.connect(_close_commander_info)
	_setup_camera()
	set_cursor_cell(Vector2i.ZERO)
	# Dev-only capture flows. The driver is held for the whole scene: `run`
	# awaits, and a RefCounted nobody references is freed mid-scenario.
	var driver := BattleScenarioDriver.new(self)
	_capturing = driver.requested()
	animator.capturing = _capturing
	animator.start_cursor_pulse()
	_on_turn_started()  # day 1 gets the same banner/cursor/event as every turn
	camera.position = cursor.position
	camera.reset_smoothing()
	if _capturing:
		# Smoothing glides the camera toward the cursor over several frames, so
		# how far it has travelled when the shutter opens depends on real
		# elapsed time — enough to shift a whole frame by a pixel between runs.
		# Captures show where the view settles, which is the position UI is
		# already anchored to anyway (see BattleView.screen_pos_for_cell).
		camera.position_smoothing_enabled = false
		_scenario_driver = driver
		_scenario_driver.run()


## Gives every team its planner. The tier is the one lever difficulty pulls —
## which AIProfile weighs the moves, never the economy, vision, damage or luck
## (difficulty plan D2/D3) — so a per-side tier is a per-side profile and nothing
## more. Each team gets its own AIController even when the tiers match, because a
## controller caches a threat map for the turn it is planning and two teams
## sharing one would be reading each other's.
func _build_planners(built: BattleSetup.BuiltMatch) -> void:
	for team in GameState.TEAMS:
		var tier: Difficulty = built.per_team_difficulty.get(team, built.difficulty)
		planners[team] = AIController.new(unit_db, tier.profile())


## The planner for a team. Never null: a team the setup did not name still gets
## the match's tier, so nothing can reach a turn with nobody to plan it.
func planner_for(team: int) -> AIController:
	if not planners.has(team):
		planners[team] = AIController.new(unit_db)
	return planners[team]


## The banner belongs to the animator, but dismissing it is something a caller
## asks the *scene* to do — the scenario driver clears it before a capture.
func hide_banner() -> void:
	animator.hide_banner()


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
	built.commander_chip = %CommanderChip
	built.db = db
	built.map = map
	built.game = game
	built.ai_teams = ai_teams
	return built


## Same assignment-not-constructor shape as _build_view, and for the same
## reason: the animator never learns what a Battle is.
func _build_animator() -> BattleAnimator:
	var built := BattleAnimator.new()
	built.node = self
	built.view = view
	built.camera = camera
	built.cursor = cursor
	built.turn_banner = %TurnBanner
	built.banner_label = %BannerLabel
	built.power_banner = %CommanderBanner
	return built


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _rematch() -> void:
	BattleSetup.remember(game, ai_teams)
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
	if state in [State.ANIMATING, State.MENU, State.VICTORY, State.AI_TURN, State.INFO]:
		return  # the menu and info sheet handle their own input; the rest block it
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
			elif _is_own_empty_factory(cell):
				_open_build_menu(cell)
			elif unit == null:
				_open_map_menu()
		State.UNIT_SELECTED:
			if move_range.has(cell) and move_range.can_stop_at(cell):
				planned_path = move_range.path_to(cell)
				_animate_move()
			elif move_range.has(cell):
				# Occupied but reachable: maybe a Load or Join destination.
				var special := BattleMenus.destination_actions(
					game, selected, move_range.path_to(cell)
				)
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
	await animator.animate_path(view.sprite_for(selected), planned_path)
	_on_move_animation_done()


func _on_move_animation_done() -> void:
	state = State.MENU
	_menu_context = &"unit"
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	if not _pending_special_actions.is_empty():
		# Load/Join destination: only the special action (and Cancel) applies.
		var special := _pending_special_actions
		_pending_special_actions = []
		special.append(BattleMenus.CANCEL)
		action_menu.open(special, view.screen_pos_for_cell(dest))
		return
	_attack_targets = _attackable_cells(selected, dest, planned_path.size() > 1)
	var actions := BattleMenus.unit_actions(
		game,
		selected,
		planned_path,
		not _attack_targets.is_empty(),
		not _drop_cells(dest).is_empty()
	)
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
			# The refresh inside _commit hides the boarded sprite.
			_commit(action, LoadCommand.new(selected, planned_path))
		&"supply":
			_commit(action, SupplyCommand.new(selected, planned_path))
		&"dive", &"surface":
			# Going under changes what the *other* side can see, so the fog pass
			# _commit ends with is load-bearing here rather than incidental:
			# without it the boat would keep the look it had.
			_commit(action, DiveCommand.new(selected, planned_path, action == &"dive"))
		&"wait":
			_commit(action, MoveCommand.new(selected, planned_path))
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
		&"cancel":
			_undo_move_preview()


## The shape every plain unit action shares: refuse to run a command the rules
## turn down, then apply it and put the board back in step. The menu only offers
## legal actions, so a rejection here is a bug rather than a player mistake — it
## is reported and the uncommitted move is rolled back rather than half-applied.
##
## Capture and Join are not routed through this: each has work of its own between
## the apply and the refresh, which is the only reason they read differently.
func _commit(action: StringName, command: Command) -> void:
	var error := command.validate(game)
	if error != "":
		push_error("%s rejected: %s" % [action, error])
		_undo_move_preview()
		return
	command.apply(game)
	EventBus.unit_moved.emit(selected)
	view.refresh_sprite(selected)
	_clear_selection()
	_refresh_panel()


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
	if action == &"power":
		_fire_command_power()
		return
	if action == &"commanders":
		_open_commander_info()
		return
	if action == &"save":
		if SaveGame.save(game, ai_teams, SaveGame.SAVE_PATH, MatchConfig.difficulty):
			animator.show_banner("Saved")
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


## Fires the current team's Command Power. Reached from the HUD button and from
## the map menu; both go through PowerCommand, like every other action. Guarded
## rather than assumed legal, because the HUD button sits outside the selection
## flow — it is reachable mid-move — and the command is the authority on that.
func _fire_command_power() -> void:
	var command := PowerCommand.new()
	if state not in [State.IDLE, State.MENU] or command.validate(game) != "":
		return
	command.apply(game)
	_announce_power(command)
	# A power can change movement, vision and HP at once, so the whole board is
	# redrawn, and the selection — plus any menu the HUD button fired over, whose
	# rows would otherwise act on it — belongs to rules that no longer apply.
	action_menu.close()
	view.sync_sprites()
	_clear_selection()
	_refresh_panel()
	_refresh_hud()


## The banner, sting and event a fired power raises. Shared, because the AI
## fires powers through the same command and should look the same doing it.
func _announce_power(fired: PowerCommand) -> void:
	Sfx.play(&"fanfare")
	animator.show_power_banner(fired.commander)
	EventBus.power_activated.emit(fired.team, fired.commander)


## A production property of ours standing empty. Which terrains those are is the
## terrain's own data, so a port and an airport open the build menu through this
## same check — and offer only what they build, see _open_build_menu.
func _is_own_empty_factory(cell: Vector2i) -> bool:
	return (
		not map.terrain_at(cell).builds.is_empty()
		and game.owner_at(cell) == game.current_team
		and game.unit_at(cell) == null
	)


func _open_build_menu(cell: Vector2i) -> void:
	_menu_context = &"base"
	_build_cell = cell
	state = State.MENU
	var actions := BattleMenus.build_actions(game, unit_db, map.terrain_at(cell), game.current_team)
	action_menu.open(actions, view.screen_pos_for_cell(cell))


func _open_map_menu() -> void:
	_menu_context = &"map"
	state = State.MENU
	action_menu.open(BattleMenus.map_actions(game), view.screen_pos_for_cell(cursor_cell))


## Opens the both-sides commander reference over the board. A modal, like the
## victory and handoff screens: the INFO state blocks board input, and the sheet
## takes focus and closes itself. Reached from the map menu, never from a hover.
func _open_commander_info() -> void:
	state = State.INFO
	commander_info_sheet.open(game.commander_of(1), game.commander_of(2))


func _close_commander_info() -> void:
	if state == State.INFO:
		state = State.IDLE


func _on_turn_started() -> void:
	view.set_active_team(game.current_team)
	if _needs_handoff():
		_enter_handoff()
		return
	_begin_turn()


## Everything the incoming team is allowed to see, run once the device has
## actually changed hands (immediately, outside fogged hot-seat).
func _begin_turn() -> void:
	# Units can be lost between turns with no shot fired: an air or sea unit that
	# ran its tank dry is already gone from the sim by now, so the board is
	# resynced before it is drawn — and a side wiped out by its own fuel gauge
	# ends the match here, exactly as one shot to pieces does.
	view.sync_sprites()
	_refresh_fog()
	_refresh_hud()
	_refresh_panel()
	if game.winner != 0:
		_enter_victory()
		return
	if _end_watch_on_day_cap():
		return
	Sfx.play(&"fanfare", -8.0)
	var team_name: String = TerrainPanel.TEAM_NAMES.get(game.current_team, str(game.current_team))
	animator.show_banner("Day %d - %s" % [game.day, team_name])
	var homes := game.properties_of(game.current_team)
	if not homes.is_empty():
		set_cursor_cell(homes[0])
	EventBus.turn_started.emit(game.current_team, game.day)
	if game.current_team in ai_teams:
		state = State.AI_TURN
		_ai_runner.run()
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
	animator.hide_banner()
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
## first human team while the AI plays. The AI sees everything bar one thing:
## a unit a doctrine hides is hidden from it too — see Vision.is_hidden_from.
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


## Watch mode only (balance plan BS3), and true when it ended the match here. The
## harness plays while `day <= days_cap` and scores what is left on the board, so
## most of its rows terminate `day_cap`; without the same seam a watched replay of
## one would run forever and never print the line the fidelity check diffs. It is
## scored on the harness's own tiebreak and held beside the sim rather than
## written into `game.winner`, because the board did not decide this one. Gated on
## `_watching`: a hot-seat or player-versus-AI match has no day limit and must not
## grow one.
func _end_watch_on_day_cap() -> bool:
	if not _watching or game.winner != 0 or game.day <= _watch_days_cap:
		return false
	_result_winner = BalanceMatchEngine.tiebreak(game)
	_enter_victory()
	return true


## Idempotent: a rout resolved inside _begin_turn is seen again by whatever was
## driving that turn, and the match is only won once however many callers notice.
func _enter_victory() -> void:
	if state == State.VICTORY:
		return
	state = State.VICTORY
	if _result_winner == 0:
		_result_winner = game.winner
	animator.hide_banner()
	Sfx.play(&"fanfare")
	victory_label.text = _result_text()
	victory_sub_label.text = "Day %d" % game.day
	_bind_victory_commander()
	victory_screen.show()
	victory_screen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rematch_button.grab_focus()
	if _watching:
		_report_watched_result()


## "Blue wins!", or "Draw" for the one case that has no winner: a watched match
## that reached the day cap with every tiebreak measure level. A match the board
## decided always names a side.
func _result_text() -> String:
	if _result_winner == 0:
		return "Draw"
	return "%s wins!" % TerrainPanel.TEAM_NAMES.get(_result_winner, str(_result_winner))


## The one line BS3's replay-fidelity check reads: a watched match must end with
## the same winner on the same day as the matches.csv row it was launched from.
## Printed rather than asserted here, because the assertion belongs to whoever is
## comparing the two — and printing it is what lets that be a diff instead of
## someone watching a window and remembering.
##
## The wording is fixed, day-cap rows included: the row's `winner` and
## `day_ended` are what it is checked against, and a scored win is still that
## row's winner.
func _report_watched_result() -> void:
	print("watch: team %d wins on day %d" % [_result_winner, game.day])
	await get_tree().create_timer(1.5).timeout  # let the lockup land on screen
	get_tree().quit()


## Fronts the victory screen with the winning commander's portrait and faction. A
## side that played without one renders gracefully: the portrait and faction line
## simply hide, leaving the plain "<team> wins!" lockup — as does a draw, which
## has no winner to front at all.
func _bind_victory_commander() -> void:
	if _result_winner == 0:
		victory_portrait.visible = false
		victory_faction_label.visible = false
		return
	var winner := game.commander_of(_result_winner)
	var has_co := winner.id != CommanderType.NEUTRAL_ID
	victory_portrait.visible = has_co
	victory_faction_label.visible = has_co
	if has_co:
		victory_portrait.texture = CommanderVisuals.portrait_for(winner)
		var theme := CommanderVisuals.theme_for(winner)
		victory_faction_label.text = "%s · %s" % [winner.display_name, theme.display]
		victory_faction_label.add_theme_color_override("font_color", theme.color_light)


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
	if not unit.has_ammo() or (AttackRange.is_indirect(unit) and moved):
		return cells
	for other in game.units:
		if other.team == unit.team or other.carrier != null:
			continue
		if not view.can_see_unit(other):
			continue  # the player cannot target what they cannot see
		if not AttackRange.covers(game, unit, dest, other.cell):
			continue
		if AttackRange.can_engage(game, unit, other):
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
## unload its passenger, empty when it is somewhere it cannot unload from at all.
## The vacated origin cell counts as free.
func _drop_cells(dest: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var cargo := game.cargo_of(selected)
	if cargo.is_empty() or not selected.type.can_unload_from(map.terrain_at(dest).id):
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
	await animator.animate_combat(command.result, attacker, target)
	_clear_selection()
	_refresh_panel()
	_refresh_hud()
	if game.winner != 0:
		_enter_victory()


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
	view.refresh_panel(cursor_cell)
