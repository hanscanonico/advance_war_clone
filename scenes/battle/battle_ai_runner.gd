class_name BattleAiRunner
extends RefCounted
## Plays a full computer turn: plan one command, animate it, repeat until the AI
## ends its turn or the per-turn safety cap trips.
##
## Split out of Battle the same way BattleView, BattleAnimator and
## BattleScenarioDriver were — it is the AI's side of the interaction flow, and
## like the scenario driver it drives Battle's own entry points (the same
## animations, the same turn hand-off, the same victory check) rather than
## reaching past them, so an AI turn resolves and animates exactly as a player's
## does. Battle holds one of these for the whole scene and calls `run()` when a
## computer team's turn opens.

## Safety net: a planner bug can never hang the match, only force a turn to end.
## Read from the harness rather than declared here, because the headless engine
## applies the identical cut (balance plan D7) — if the two drifted apart, a
## watched match could be trimmed where its headless row was let run, and the
## replay-fidelity check would fail for a reason that has nothing to do with the
## sim.
const MAX_COMMANDS_PER_TURN := BalanceMatchEngine.MAX_COMMANDS_PER_TURN

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Plays the whole AI turn. Fire-and-forget async, like the player flow it
## mirrors: it awaits its own animations and never blocks Battle's frame.
func run() -> void:
	var game := _battle.game
	# Opens just after the day banner has cleared — however long the active tier
	# holds that banner, which is why the wait is computed here and not fixed.
	var start_delay := _speed().start_delay_seconds()
	await _battle.get_tree().create_timer(start_delay).timeout
	for i in MAX_COMMANDS_PER_TURN:
		if game.winner != 0:
			_leave()
			return
		# Asked per command, not cached for the turn: an EndTurnCommand hands play
		# to the other side mid-loop, and in watch mode that side has a planner of
		# its own.
		var command := _battle.planner_for(game.current_team).plan_next_command(game)
		var error := command.validate(game)
		if error != "":
			push_error("AI command rejected (%s); ending the AI turn" % error)
			command = EndTurnCommand.new()
			if command.validate(game) != "":
				_leave()
				return
		var ended := command is EndTurnCommand
		await _execute(command)
		if game.winner != 0:
			_leave()
			return
		if ended:
			return
		await _think()
	push_error("AI hit the per-turn command cap; forcing end of turn")
	var end_turn := EndTurnCommand.new()
	if end_turn.validate(game) == "":
		await _execute(end_turn)
	else:
		_leave()


## The tier this turn is paced at. The animator owns the answer, so a computer
## turn and a player's move obey the same setting — and a capture, which pins its
## own tier there, pins this too.
func _speed() -> GameSpeed:
	return _battle.animator.speed()


## The think-beat between two commands, so the turn reads as decisions rather
## than a slideshow.
##
## Instant drops the wait to a single frame rather than to nothing: the board
## still repaints once per command, so a forty-command turn is forty frames the
## eye can track as a fast flicker, the window keeps pumping events, and the
## per-turn safety cap above keeps meaning what it says.
func _think() -> void:
	var delay := _speed().command_delay_seconds()
	if delay <= 0.0:
		await _battle.get_tree().process_frame
		return
	await _battle.get_tree().create_timer(delay).timeout


## Every bail-out from the loop lands here, so a planner bug can never leave the
## scene stuck in AI_TURN with all input blocked and no banner.
func _leave() -> void:
	if _battle.game.winner != 0:
		_battle._enter_victory()
	else:
		_battle.state = Battle.State.IDLE


## Applies one AI command with the same animations the player flow uses.
## Attack/Capture are checked before Move because each is its own Command
## subclass; the cursor follows so the player can watch.
func _execute(command: Command) -> void:
	var game := _battle.game
	var view := _battle.view
	var animator := _battle.animator
	if command is AttackCommand:
		var attack := command as AttackCommand
		var target := game.unit_at(attack.target_cell)
		_battle.set_cursor_cell(attack.path[attack.path.size() - 1])
		await animator.animate_path(view.sprite_for(attack.unit), attack.path)
		_battle.set_cursor_cell(attack.target_cell)
		command.apply(game)
		EventBus.unit_moved.emit(attack.unit)
		await animator.animate_combat(attack.result, attack.unit, target)
	elif command is CaptureCommand:
		var capture := command as CaptureCommand
		var dest: Vector2i = capture.path[capture.path.size() - 1]
		_battle.set_cursor_cell(dest)
		await animator.animate_path(view.sprite_for(capture.unit), capture.path)
		command.apply(game)
		EventBus.unit_moved.emit(capture.unit)
		if game.owner_at(dest) == capture.unit.team:
			EventBus.property_captured.emit(dest, capture.unit.team)
			view.repaint_property(dest)
		view.refresh_sprite(capture.unit)
	elif command is DiveCommand:
		var dive := command as DiveCommand
		_battle.set_cursor_cell(dive.path[dive.path.size() - 1])
		await animator.animate_path(view.sprite_for(dive.unit), dive.path)
		command.apply(game)
		EventBus.unit_moved.emit(dive.unit)
		view.refresh_sprite(dive.unit)
	elif command is MoveCommand:
		var move := command as MoveCommand
		_battle.set_cursor_cell(move.path[move.path.size() - 1])
		await animator.animate_path(view.sprite_for(move.unit), move.path)
		command.apply(game)
		EventBus.unit_moved.emit(move.unit)
		view.refresh_sprite(move.unit)
	elif command is PowerCommand:
		command.apply(game)
		_battle._announce_power(command as PowerCommand)
		view.sync_sprites()  # the one-shot half may have healed or refuelled
	elif command is BuildCommand:
		var build := command as BuildCommand
		_battle.set_cursor_cell(build.cell)
		command.apply(game)
		view.spawn_sprite_for(build.built_unit)
		EventBus.unit_built.emit(build.built_unit)
	elif command is EndTurnCommand:
		command.apply(game)
		_battle._on_turn_started()
	_battle._refresh_fog()
	_battle._refresh_panel()
	_battle._refresh_hud()
