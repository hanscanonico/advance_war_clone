extends Node
## Device preferences: what this machine likes, as opposed to what this match
## is. Today that is exactly one thing — how fast the battle's theatre plays out.
##
## Deliberately not MatchConfig and deliberately not in the save file: resuming
## a three-day-old save should play at the speed you like *today*, and a hot-seat
## pair share one screen anyway. Nothing here is ever handed to core/ or ai/, so
## the sim cannot observe a preference it never receives — see GameSpeed.
##
## Persisted to user://settings.cfg with ConfigFile, beside SaveGame's
## user://save.json.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"
const SPEED_KEY := "speed"
## Overrides the stored tier for one launch, in the family of --map / --fog /
## --difficulty. Deliberately un-persisted: a scripted run must not edit what
## the player chose.
const SPEED_ARG := "--speed="

## How fast moves and battles play out on screen. Never null. Callers read it at
## the moment they animate rather than caching it, so a mid-match change takes
## effect on the very next animation.
var speed: GameSpeed = GameSpeed.default_speed()

## False once `--speed=` has spoken for this launch, so nothing written later
## reaches the file.
var _persistent := true


func _ready() -> void:
	_load()
	_apply_cmdline()


## Changes the tier and writes it back. The only way the speed ever moves.
func set_speed(id: StringName) -> void:
	speed = GameSpeed.by_id(id)
	if _persistent:
		_save()


## A missing or malformed file is not an error: the defaults simply stand, which
## is what a first launch on a new machine looks like.
func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var stored: Variant = config.get_value(SECTION, SPEED_KEY, "")
	if stored is String:
		speed = GameSpeed.by_id(StringName(stored))


func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep any key a later version of the game wrote
	config.set_value(SECTION, SPEED_KEY, String(speed.id))
	if config.save(SETTINGS_PATH) != OK:
		push_error("Settings: cannot write %s" % SETTINGS_PATH)


func _apply_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SPEED_ARG):
			speed = GameSpeed.by_id(StringName(arg.get_slice("=", 1).strip_edges()))
			_persistent = false
