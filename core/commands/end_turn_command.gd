class_name EndTurnCommand
extends Command
## Hands the turn to the next team; the day advances when the rotation wraps
## back to the first team. Start-of-turn effects run for the new team.


func validate(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	return ""


func apply(state: GameState) -> void:
	_expire_power(state, state.current_team)
	var next := state.next_team()
	if next == GameState.TEAMS[0]:
		state.day += 1
	state.current_team = next
	TurnRules.begin_turn(state)


## An OWNER_TURN Command Power lasts exactly the turn it was fired on, so it
## comes down as that turn ends. A ROUND power deliberately survives this and
## expires at its owner's next turn start instead — see TurnRules.begin_turn.
## Those two lines are the only places a power is ever taken down.
static func _expire_power(state: GameState, team: int) -> void:
	var co_state := state.commander_state(team)
	if co_state.power_active and co_state.type.power_duration == CommanderType.Duration.OWNER_TURN:
		co_state.power_active = false
