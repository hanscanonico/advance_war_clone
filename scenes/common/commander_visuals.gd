class_name CommanderVisuals
extends RefCounted
## Presentation adapter for commanders: turns the sim-side CommanderType (id,
## faction, text, numbers) into the things a scene needs to draw one — a portrait
## texture, a faction colour theme, an emblem — without any of that ever entering
## core/.
##
## This is the single authority on commander styling. The card, the battle HUD
## chip, and the power banner all ask here rather than each keeping their own
## copy of the four faction colours, exactly as the resolvers each own one rule.
## The offline portrait generator asks here too, so the art it bakes and the art
## the UI expects can never disagree about which colour a faction is.
##
## No Node, no scene path — but this is scenes/, not core/, so loading a
## Texture2D and caching it is allowed here where it would not be there.


## A faction's colour identity. Colour is always reinforced by the emblem and the
## faction name (see the plan's "faction first, never colour alone" principle),
## so nothing here is asked to carry meaning on hue alone.
class FactionTheme:
	extends RefCounted

	var key: StringName
	var display: String
	## The field colour behind the portrait and the name band.
	var color: Color
	## A darker shade for borders and the pressed/inactive state.
	var color_dark: Color
	## A lighter shade for the diagonal field's second stripe.
	var color_light: Color
	## Text drawn on top of `color`.
	var ink: Color

	func _init(
		p_key: StringName,
		p_display: String,
		p_color: Color,
		p_dark: Color,
		p_light: Color,
		p_ink: Color
	) -> void:
		key = p_key
		display = p_display
		color = p_color
		color_dark = p_dark
		color_light = p_light
		ink = p_ink


## Warm rules-panel paper and the ink on it, shared by every card regardless of
## faction — the doctrine and power copy always sits on the same neutral field.
const PAPER := Color(0.933, 0.906, 0.839)
const PAPER_INK := Color(0.145, 0.169, 0.188)
const HARD_BORDER := Color(0.067, 0.086, 0.098)

const PORTRAIT_DIR := "res://assets/portraits/commanders"
const FACTION_DIR := "res://assets/portraits/factions"
const NEUTRAL_PORTRAIT_PATH := "res://assets/portraits/commanders/none.png"
## Master portrait size the generator writes and the fallbacks match.
const PORTRAIT_PX := 256
const EMBLEM_PX := 64

## The neutral commander has no faction; it renders in this iron-grey so "No
## Commander" still reads as a deliberate, styled choice rather than a blank.
const NEUTRAL_KEY := &"neutral"

## Faction display string -> short theme key. Kept here so a .tres that names a
## faction and this adapter can never drift; an unknown faction falls back to the
## neutral theme rather than crashing.
const _FACTION_KEYS := {
	"Meridian Coalition": &"meridian",
	"Iron Dominion": &"iron",
	"Aurora Compact": &"aurora",
	"Verdant League": &"verdant",
}

static var _themes: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func _build_themes() -> void:
	if not _themes.is_empty():
		return
	_themes = {
		&"meridian":
		FactionTheme.new(
			&"meridian",
			"Meridian Coalition",
			Color(0.859, 0.290, 0.231),
			Color(0.663, 0.212, 0.192),
			Color(0.937, 0.447, 0.373),
			Color(0.973, 0.957, 0.925)
		),
		&"iron":
		FactionTheme.new(
			&"iron",
			"Iron Dominion",
			Color(0.290, 0.322, 0.345),
			Color(0.184, 0.212, 0.231),
			Color(0.420, 0.455, 0.482),
			Color(0.949, 0.957, 0.961)
		),
		&"aurora":
		FactionTheme.new(
			&"aurora",
			"Aurora Compact",
			Color(0.220, 0.396, 0.847),
			Color(0.169, 0.306, 0.659),
			Color(0.427, 0.549, 0.910),
			Color(0.957, 0.965, 0.988)
		),
		&"verdant":
		FactionTheme.new(
			&"verdant",
			"Verdant League",
			Color(0.173, 0.525, 0.212),
			Color(0.114, 0.380, 0.153),
			Color(0.310, 0.659, 0.353),
			Color(0.949, 0.965, 0.945)
		),
		NEUTRAL_KEY:
		FactionTheme.new(
			NEUTRAL_KEY,
			"No Commander",
			Color(0.376, 0.416, 0.443),
			Color(0.235, 0.267, 0.290),
			Color(0.510, 0.549, 0.573),
			Color(0.925, 0.933, 0.937)
		),
	}


## The short theme key for a faction string. Empty/unknown -> neutral.
static func key_for_faction(faction: String) -> StringName:
	return _FACTION_KEYS.get(faction, NEUTRAL_KEY)


static func theme_for_key(key: StringName) -> FactionTheme:
	_build_themes()
	return _themes.get(key, _themes[NEUTRAL_KEY])


## The theme a commander renders in. Neutral commanders — and any general whose
## .tres names a faction this adapter has not been taught — resolve to the
## neutral grey rather than crashing.
static func theme_for(commander: CommanderType) -> FactionTheme:
	if commander == null or commander.faction.is_empty():
		return theme_for_key(NEUTRAL_KEY)
	return theme_for_key(key_for_faction(commander.faction))


## Every faction theme except neutral, in the plan's tab order. The selection
## page groups the roster under these.
static func faction_themes() -> Array:
	_build_themes()
	var ordered: Array = []
	for key: StringName in [&"meridian", &"iron", &"aurora", &"verdant"]:
		ordered.append(_themes[key])
	return ordered


# --- textures ----------------------------------------------------------------


## The portrait for a commander. Resolves by id; a commander whose art has not
## been produced yet falls back to the neutral silhouette, and if even that is
## missing (a truly fresh tree before `make portraits`) returns a generated
## flat-colour placeholder so no caller ever gets null and no scene crashes.
static func portrait_for(commander: CommanderType) -> Texture2D:
	var id := commander.id if commander != null else CommanderType.NEUTRAL_ID
	return _cached(
		"%s/%s.png" % [PORTRAIT_DIR, id], func() -> Texture2D: return _fallback_portrait()
	)


## A faction's emblem. Neutral has none, so callers gate on the theme key; asked
## anyway it falls back like a portrait does.
static func emblem_for_key(key: StringName) -> Texture2D:
	return _cached("%s/%s.png" % [FACTION_DIR, key], func() -> Texture2D: return _fallback_emblem())


static func emblem_for(commander: CommanderType) -> Texture2D:
	return emblem_for_key(theme_for(commander).key)


## Loads `path` through a small cache, calling `on_missing` for the fallback when
## the file is not there. Textures are shared immutable resources, so caching
## them across scene loads is safe and keeps the select page from reloading
## thirteen portraits every time a tab changes.
static func _cached(path: String, on_missing: Callable) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path)
	if texture == null and ResourceLoader.exists(NEUTRAL_PORTRAIT_PATH):
		texture = load(NEUTRAL_PORTRAIT_PATH)
	if texture == null:
		texture = on_missing.call()
	_texture_cache[path] = texture
	return texture


static func _fallback_portrait() -> Texture2D:
	var image := Image.create(PORTRAIT_PX, PORTRAIT_PX, false, Image.FORMAT_RGBA8)
	image.fill(theme_for_key(NEUTRAL_KEY).color)
	return ImageTexture.create_from_image(image)


static func _fallback_emblem() -> Texture2D:
	var image := Image.create(EMBLEM_PX, EMBLEM_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
