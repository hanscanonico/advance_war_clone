extends Node
## Device preferences: what this machine likes, as opposed to what this match is.
## Two of them today — how fast the battle's theatre plays out, and whether a
## resolved attack cuts to the full-screen battle animation at all.
##
## Deliberately not MatchConfig and deliberately not in the save file: resuming a
## three-day-old save should play at the speed you like *today* and watch battles
## the way you like *today*, and a hot-seat pair share one screen anyway. Both are
## presentation only — nothing here may ever change a rule, a number, or what the
## sim does, so two players' "same seed, same commands" keep meaning the same
## result. Nothing here is ever handed to core/ or ai/, so the sim cannot observe
## a preference it never receives — see GameSpeed.
##
## Persisted to user://settings.cfg with ConfigFile, beside SaveGame's
## user://save.json.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"
const SPEED_KEY := "speed"
const BATTLE_ANIMATIONS_KEY := "battle_animations"
## Overrides the stored tier for one launch, in the family of --map / --fog /
## --difficulty. Deliberately un-persisted: a scripted run must not edit what
## the player chose.
const SPEED_ARG := "--speed="
## Turns the battle cut-in off for one launch, same family as --speed= and just
## as un-persisted: how a capture run keeps `make screenshot` byte-stable without
## touching the stored preference.
const NO_ANIM_ARG := "--no-battle-anim"

## How fast moves and battles play out on screen. Never null. Callers read it at
## the moment they animate rather than caching it, so a mid-match change takes
## effect on the very next animation.
var speed: GameSpeed = GameSpeed.default_speed()

## Whether a resolved attack plays the full-screen battle cut-in. Off falls back
## to the on-map hit flash and shake, which is how combat looked before the
## cut-in existed — see BattleAnimator.animate_combat.
var battle_animations := true

## False once anything has spoken for this launch, so nothing written later
## reaches the file.
var _persistent := true
## True once `--speed=` has spoken. A capture pins the tier it needs, but an
## explicit flag outranks even that: it is the most specific thing anyone said,
## and asking for a capture *of* a tier is how you look at one you are tuning.
var _flag_wins := false


func _ready() -> void:
	_load()
	_apply_cmdline()


## Changes the tier and writes it back. The only way the speed ever moves.
func set_speed(id: StringName) -> void:
	speed = GameSpeed.by_id(id)
	if _persistent:
		_save()


## The setter the menu's checkbox is wired to. Mirrors set_speed: writes through
## immediately so a preference set in one session is honoured in the next even if
## the game is closed the hard way, but a pinned or scripted launch (see pin and
## _apply_cmdline) never touches the file.
func set_battle_animations(enabled: bool) -> void:
	battle_animations = enabled
	if _persistent:
		_save()


## Pins a tier for this launch and latches the file shut behind it. Captures and
## scripted scenario runs pin, so a frame never depends on which machine took it
## — and it is pinned *here* rather than inside the animator because the setting
## has one owner: the in-battle menu row reads its label off this too, and a
## capture whose animations were pinned but whose label was not would photograph
## the preference it was meant to ignore.
func pin(id: StringName) -> void:
	_persistent = false
	if not _flag_wins:
		speed = GameSpeed.by_id(id)


## A missing or malformed file is not an error: the defaults simply stand, which
## is what a first launch on a new machine looks like.
func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var stored: Variant = config.get_value(SECTION, SPEED_KEY, "")
	if stored is String:
		speed = GameSpeed.by_id(StringName(stored))
	var stored_anim: Variant = config.get_value(SECTION, BATTLE_ANIMATIONS_KEY, battle_animations)
	if stored_anim is bool:
		battle_animations = stored_anim


func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep any key a later version of the game wrote
	config.set_value(SECTION, SPEED_KEY, String(speed.id))
	config.set_value(SECTION, BATTLE_ANIMATIONS_KEY, battle_animations)
	if config.save(SETTINGS_PATH) != OK:
		push_error("Settings: cannot write %s" % SETTINGS_PATH)


func _apply_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SPEED_ARG):
			var wanted := StringName(arg.get_slice("=", 1).strip_edges())
			# Checked here rather than inside pin(), which is only ever handed an
			# id from the source: a capture must not pay for the check or risk a
			# spurious error. A name nothing answers to is said out loud and then
			# dropped entirely — the shape battle_setup answers an unknown --map=
			# with. Half-applying it would be worse than ignoring it: the pin
			# below latches the file shut, so a typo would silently stop writing
			# every speed the player picked for the rest of the session.
			if not GameSpeed.has_id(wanted):
				push_error(
					(
						"Settings: unknown speed '%s'; keeping %s. Known: %s"
						% [wanted, speed.id, ", ".join(GameSpeed.ids())]
					)
				)
				continue
			pin(wanted)
			# Latched after that pin, so the flag's own lands and every later
			# one — a capture's — is declined.
			_flag_wins = true
		elif arg == NO_ANIM_ARG:
			# Same family as --speed=: a per-launch override that never reaches
			# the file. Latches it shut exactly as a pin does, so a scripted or
			# capture run cannot rewrite what the player chose.
			_persistent = false
			battle_animations = false
