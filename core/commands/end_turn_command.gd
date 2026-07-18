class_name EndTurnCommand
extends Command
## Hands the turn to the next team; the day advances when the rotation wraps
## back to the first team. Start-of-turn effects run for the new team.


func validate(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	return ""


func apply(state: GameState) -> void:
	var next := state.next_team()
	if next == GameState.TEAMS[0]:
		state.day += 1
	state.current_team = next
	TurnRules.begin_turn(state)
