extends Node
## Carries the match setup from the main menu into the battle scene.
## Command-line flags (--map, --hotseat, --fog) still override these, so
## demos and tools keep working without the menu.

var map_path := "res://maps/first_steps.txt"
## Teams played by the computer.
var ai_teams: Array[int] = [2]
var fog_enabled := false
## When true, the battle scene resumes SaveGame.SAVE_PATH instead of
## starting fresh (and clears the flag).
var load_save := false
