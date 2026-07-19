extends Node
## Carries the match setup from the main menu into the battle scene.
## Command-line flags (--map, --hotseat, --fog, --co) still override these, so
## demos and tools keep working without the menu.

var map_path := "res://maps/first_steps.txt"
## Teams played by the computer.
var ai_teams: Array[int] = [2]
var fog_enabled := false
## team -> commander id. A team with no entry plays without a commander, which
## is the default and reproduces the pre-commander game exactly.
var commanders: Dictionary = {}
## When true, the battle scene resumes SaveGame.SAVE_PATH instead of
## starting fresh (and clears the flag).
var load_save := false
