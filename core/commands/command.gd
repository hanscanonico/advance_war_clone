class_name Command
extends RefCounted
## Base class for all simulation actions (move, attack, capture, build, ...).
## Commands are validated against a GameState, then applied to mutate it.
## The AI issues the exact same commands as the player.


## Returns "" when the command is legal, otherwise a human-readable reason.
func validate(_state: GameState) -> String:
	return "not implemented"


## Mutates the state. Only call after validate() returned "".
func apply(_state: GameState) -> void:
	push_error("Command.apply not implemented")
