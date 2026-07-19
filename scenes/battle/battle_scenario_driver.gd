class_name BattleScenarioDriver
extends RefCounted
## Dev-only: parses the capture command line and drives Battle through scripted
## flows for automated screenshots (`make screenshot`, `make smoke`).
##
## Depends on Battle; nothing on the gameplay path depends on this. Scenarios
## drive the same entry points player input reaches — `confirm_at`,
## `set_cursor_cell`, and the real ActionMenu — rather than calling commands
## directly, so a scenario that stops working means the flow it exercises
## broke, not that the driver drifted from the game.
##
## Battle holds the driver in a member for the duration: `run` awaits, and a
## RefCounted nobody references is freed mid-scenario.

## `Godot --path . -- --screenshot=/abs/path.png [--select=x,y | --demo=MODE]`
## boots the scene, optionally drives a demo, saves one frame, and quits.
## --select previews a unit's movement; see `_run_demo` for the demo modes.
const SCREENSHOT_ARG := "--screenshot="
const SELECT_ARG := "--select="
const DEMO_ARG := "--demo="

## Demos fix the seed so a capture of the same scenario is the same frame.
const DEMO_SEED := 2026

var _battle: Battle
var _shot_path := ""
var _select_cell := Vector2i(-1, -1)
var _demo := ""


func _init(battle: Battle) -> void:
	_battle = battle
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SCREENSHOT_ARG):
			_shot_path = arg.get_slice("=", 1)
		elif arg.begins_with(SELECT_ARG):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_select_cell = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with(DEMO_ARG):
			_demo = arg.get_slice("=", 1)


## True when the command line asked for any scripted flow at all. Battle skips
## building a driver otherwise, so an ordinary match never pays for one.
func requested() -> bool:
	return _shot_path != "" or _select_cell.x >= 0 or _demo != ""


func run() -> void:
	if not requested():
		return
	# Demos and captures drive the board, so neither the handoff panel nor the
	# day-1 banner may sit on top of the frame.
	_battle.leave_handoff()
	_battle.hide_banner()
	if _demo != "":
		await _run_demo(_demo)
	elif _select_cell.x >= 0:
		_demo_select(_select_cell)
	if _shot_path != "":
		await _save_screenshot_and_quit(_shot_path)


## Drives real flows through the same handlers a player's input reaches:
## attack stops at the targeting preview and resolve fires, both with the
## frontline tanks; capture takes the city at (3,4) with the infantry at (4,3);
## build buys at the red base and buildmenu stops at its open shop list;
## endturn hands the turn to Blue; aiturn does the same and then waits out
## Blue's whole AI turn, back to Red's next turn;
## transport runs load -> drive -> drop, and load, cargo, and drop stop that
## same chain at the Load menu, the loaded APC's panel, and the drop-target
## picker; supply holds the APC next to its infantry so Supply is offered;
## mapmenu stops at the map menu (End Turn / Save); victory routs Blue through
## a real attack so the victory screen comes up.
##
## Modes that stop early return without falling through to the rest of the
## chain; `run` still takes the capture.
func _run_demo(mode: String) -> void:
	var tree := _battle.get_tree()
	await tree.process_frame
	_battle.game.rng.seed = DEMO_SEED  # deterministic demo
	match mode:
		"attack", "resolve":
			_battle.confirm_at(Vector2i(8, 8))  # select the red tank
			_battle.confirm_at(Vector2i(8, 8))  # fire in place
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"fire")
			await _until_state(Battle.State.TARGETING)
			if mode == "attack":
				return
			_battle.confirm_at(_battle.cursor_cell)  # fire at the blue tank
			await _until_state(Battle.State.IDLE)
		"capture":
			_battle.confirm_at(Vector2i(4, 3))  # select the red infantry
			_battle.confirm_at(Vector2i(3, 4))  # move onto the neutral city
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"capture")
			await _until_state(Battle.State.IDLE)
			_battle.set_cursor_cell(Vector2i(3, 4))  # show capture progress
		"build", "buildmenu":
			_battle.set_cursor_cell(Vector2i(3, 2))  # red base
			_battle.confirm_at(Vector2i(3, 2))  # open the build menu (funds 2000)
			await _until_state(Battle.State.MENU)
			if mode == "buildmenu":
				return
			_battle.action_menu.choose(&"infantry")
			await _until_state(Battle.State.IDLE)
		"endturn":
			_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"end_turn")
			await tree.process_frame
		"load", "cargo", "drop", "transport":
			await _run_transport_demo(mode)
		"supply":
			_battle.confirm_at(Vector2i(3, 3))  # select the red APC
			_battle.confirm_at(Vector2i(3, 3))  # stay put -> menu offers Supply
			await _until_state(Battle.State.MENU)
		"mapmenu":
			_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> End Turn / Save
			await _until_state(Battle.State.MENU)
		"victory":
			await _run_victory_demo()
		"aiturn":
			# hand the turn to the Blue AI and wait until it plays back to Red
			_battle.confirm_at(Vector2i(10, 5))
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"end_turn")
			while (
				_battle.game.winner == 0
				and not (_battle.game.current_team == 1 and _battle.state == Battle.State.IDLE)
			):
				await tree.process_frame


## load -> drive -> drop, with three modes stopping partway along the chain.
func _run_transport_demo(mode: String) -> void:
	_battle.confirm_at(Vector2i(4, 3))  # select the red infantry
	_battle.confirm_at(Vector2i(3, 3))  # onto the APC -> Load menu
	await _until_state(Battle.State.MENU)
	if mode == "load":
		return
	_battle.action_menu.choose(&"load")
	await _until_state(Battle.State.IDLE)
	if mode == "cargo":
		_battle.set_cursor_cell(Vector2i(3, 3))  # panel shows the APC's [+Infantry]
		return
	_battle.confirm_at(Vector2i(3, 3))  # select the loaded APC
	_battle.confirm_at(Vector2i(3, 5))  # drive it south
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"drop")
	await _until_state(Battle.State.DROP_TARGETING)
	if mode == "drop":
		return
	_battle.confirm_at(_battle.cursor_cell)  # drop at the first offered cell
	await _until_state(Battle.State.IDLE)
	_battle.set_cursor_cell(Vector2i(3, 5))  # show the APC in the panel


## Leaves Blue one nearly-dead unit, then wins through the ordinary
## select -> Fire flow so the real victory handler runs.
func _run_victory_demo() -> void:
	for unit in _battle.game.units.duplicate():
		if unit.team == 2 and unit.cell != Vector2i(9, 8):
			_battle.game.remove_unit(unit)
	var last_blue := _battle.game.unit_at(Vector2i(9, 8))
	last_blue.hp = 1
	_battle.sync_sprites_to_state()  # the sim was edited behind the scene's back
	_battle.confirm_at(Vector2i(8, 8))  # select the red tank
	_battle.confirm_at(Vector2i(8, 8))  # fire in place
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"fire")
	await _until_state(Battle.State.TARGETING)
	_battle.confirm_at(_battle.cursor_cell)  # kill the last blue unit -> rout
	await _until_state(Battle.State.VICTORY)


## Parks on a unit and previews its movement out to the farthest cell it could
## actually stop on, which is the frame `--select` exists to capture.
func _demo_select(cell: Vector2i) -> void:
	if not _battle.map.in_bounds(cell):
		return
	_battle.set_cursor_cell(cell)
	_battle.confirm_at(cell)
	if _battle.state != Battle.State.UNIT_SELECTED:
		return
	var farthest := cell
	var best_cost := -1
	var move_range := _battle.move_range
	for candidate in move_range.cells():
		if move_range.can_stop_at(candidate) and move_range.costs[candidate] > best_cost:
			best_cost = move_range.costs[candidate]
			farthest = candidate
	_battle.set_cursor_cell(farthest)


## Scenarios advance by waiting on the scene's own state machine rather than a
## fixed frame count, so they stay correct when animation timings change.
func _until_state(wanted: Battle.State) -> void:
	while _battle.state != wanted:
		await _battle.get_tree().process_frame


func _save_screenshot_and_quit(path: String) -> void:
	await ScreenshotUtil.capture_and_quit(_battle, path)
