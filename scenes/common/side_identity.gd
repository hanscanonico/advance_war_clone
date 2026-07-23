class_name SideIdentity
extends RefCounted
## Resolves each side's presentation identity — theme colour, display name, and
## units/terrain atlas row — from the match's commander picks. One resolver,
## resolved once per match, read by every surface that used to say "Red"/"Blue"
## (Faction Identity plan D1/D2).
##
## Presentation only: the sim keeps its team ints everywhere, nothing here ever
## enters core/, and the identity is derived at scene setup and never stored — a
## resumed save re-resolves to the same answer because the commander picks are
## the same. The sim cannot disagree with the theatre about who is who because it
## never hears the question.
##
## No Node, no scene path: this sits in scenes/common/ beside CommanderVisuals,
## whose four faction themes it reads and never re-derives.

## Theme key -> the row the art pipeline draws that faction's units and property
## buildings at. MUST match tools/build_pixvoxel_atlases.sh ROW_PALETTE and
## tools/generate_tiles.gd's row order: 0 neutral, 1 meridian(red),
## 2 aurora(blue), 3 iron, 4 verdant.
const _ROW_FOR_KEY := {
	&"neutral": 0,
	&"meridian": 1,
	&"aurora": 2,
	&"iron": 3,
	&"verdant": 4,
}
## Team 0 (a neutral property owner) and any side that never resolved.
const NEUTRAL_ROW := 0
## The team-tinted rows, 1..FACTION_ROWS — one per faction, above the neutral
## row 0. The runtime property TileSet registers exactly these (BattleView).
const FACTION_ROWS := 4

## The two original side colours — "classic" themes. Meridian is red, Aurora is
## blue. A commander-less side or a mirror side falls back to one of these; a
## faction side never does.
##
## Generic (commander-less) sides claim classics in this order, meridian then
## aurora, so a match with no commanders at all renders exactly as it did before
## factions: side 1 red, side 2 blue (plan D4).
const _GENERIC_ORDER: Array[StringName] = [&"meridian", &"aurora"]
## A mirror side — one whose faction an earlier slot already wears — borrows a
## classic in this order instead, aurora then meridian, taking the first that is
## hue-distinct from what is already on the board (plan D3). Iron v Iron ->
## slate + blue; Aurora v Aurora -> blue + red.
const _MIRROR_ORDER: Array[StringName] = [&"aurora", &"meridian"]

var _theme_by_team: Dictionary = {}  # team -> CommanderVisuals.FactionTheme
var _name_by_team: Dictionary = {}  # team -> String


## The identity for a running match, read straight from its commander picks.
static func for_game(game: GameState) -> SideIdentity:
	var commanders := {}
	for team in GameState.TEAMS:
		commanders[team] = game.commander_of(team)
	return resolve(commanders)


## The identity for a hypothetical set of picks (team -> CommanderType). The
## selection page previews live from this before a match exists; for_game is the
## match's own route. Public and side-effect free so it can be unit-tested with
## no scene tree.
static func resolve(commanders_by_team: Dictionary) -> SideIdentity:
	var identity := SideIdentity.new()
	identity._resolve(commanders_by_team)
	return identity


## The theme a side wears — its faction's, or a borrowed classic in a mirror.
## Never null; an unresolved team answers neutral.
func theme(team: int) -> CommanderVisuals.FactionTheme:
	return _theme_by_team.get(team, CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY))


## What a side is called — its faction name (kept even when the colour is a
## borrowed classic), or "First Army"/"Second Army" for a commander-less side.
## Team 0 is the neutral property owner, the one non-side this is asked about
## (the terrain panel labels who owns a tile).
func display_name(team: int) -> String:
	if team == MapData.NEUTRAL:
		return "Neutral"
	return _name_by_team.get(team, "Team %d" % team)


## The units/terrain atlas row a side draws in. Team 0 (a neutral property
## owner) and any unresolved team fall to the neutral row, which is what an
## unowned property and a side-less query both want.
func atlas_row(team: int) -> int:
	if not _theme_by_team.has(team):
		return NEUTRAL_ROW
	return _ROW_FOR_KEY.get(_theme_by_team[team].key, NEUTRAL_ROW)


# --- resolution --------------------------------------------------------------


## Two passes, both in slot order, so the answer is deterministic and total:
## faction sides claim their colours first, then commander-less sides take what
## is left. Every collision falls to the first free classic, so two sides can
## never resolve to the same colour and the same picks always resolve the same.
func _resolve(commanders: Dictionary) -> void:
	var used: Dictionary = {}  # theme key -> true, for every side already placed
	for slot in GameState.TEAMS.size():
		var team: int = GameState.TEAMS[slot]
		var faction := CommanderVisuals.theme_for(commanders.get(team))
		if faction.key == CommanderVisuals.NEUTRAL_KEY:
			continue  # commander-less; placed in the second pass
		var worn := faction if not used.has(faction.key) else _fallback(_MIRROR_ORDER, used)
		used[worn.key] = true
		_theme_by_team[team] = worn
		# The faction's own name, even when the colour it wears is a borrowed
		# classic — a mirror keeps both sides named for the faction and leans on
		# the slot numeral and commander to tell them apart.
		_name_by_team[team] = faction.display
	for slot in GameState.TEAMS.size():
		var team: int = GameState.TEAMS[slot]
		if _theme_by_team.has(team):
			continue
		var worn := _fallback(_GENERIC_ORDER, used)
		used[worn.key] = true
		_theme_by_team[team] = worn
		_name_by_team[team] = _ordinal_army_name(slot)


## The first classic theme in `order` whose key is not already on the board.
## Distinctness is by theme key, which for the four faction themes is
## distinctness by hue — each theme is its own hue — so this is the "fall back by
## hue, never by shade" of plan D3, and the "first classic not in use" of D4,
## the two differing only in which order they try the classics.
func _fallback(order: Array[StringName], used: Dictionary) -> CommanderVisuals.FactionTheme:
	for key in order:
		if not used.has(key):
			return CommanderVisuals.theme_for_key(key)
	# Unreachable with two sides and two classics: at most one classic is ever
	# taken before a fallback runs. Answer neutral rather than crash if a future
	# third side ever gets here.
	return CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)


func _ordinal_army_name(slot: int) -> String:
	const ORDINALS: Array[String] = ["First", "Second", "Third", "Fourth"]
	var word := ORDINALS[slot] if slot < ORDINALS.size() else "%d-th" % (slot + 1)
	return "%s Army" % word
