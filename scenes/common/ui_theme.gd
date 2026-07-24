class_name UiTheme
extends RefCounted
## The menu's presentation authority: the Grid Commander Design System, transcribed
## into Godot styleboxes and fonts. Where the handoff's cream/ink/hard-shadow look
## is drawn — the main menu and the commander select page — the recipe comes from
## here, so a colour or a shadow is defined once and every surface reads the same
## value (menu-revamp plan D1).
##
## The palette splits three ways. Faction colours are never re-declared: they stay
## CommanderVisuals.FactionTheme's, reached through `menu_identity()` so a future
## palette change lands here for free (plan D4). Cream and ink alias the shipped
## CommanderVisuals authorities (PAPER / PAPER_INK / HARD_BORDER). Only the shell
## tokens the game had no authority for — the slates, the neutrals, the capture
## green — are new constants below, transcribed from the handoff's colors.css.
##
## No .tres Theme resource: this repo builds its UI in code (CommanderSelectPanel,
## CommanderCard), and a hand-edited Theme is the one format that cannot be
## reviewed in a diff. No file under data/ either — data/ is for numbers the *sim*
## reads, and the sim must never read a menu colour.
##
## Sizes are canvas pixels: the game renders a 640x360 canvas stretched 2x into
## the default window, so every value here is half the handoff's and doubles on
## screen (plan section 2's div-2 rule). These are starting values, tuned by eye.
##
## No Node, no scene path — but this is scenes/, not core/, so loading a font and
## caching it is allowed here where it would not be there.

const FONT_DIR := "res://assets/fonts"
const DISPLAY_FONT_PATH := FONT_DIR + "/PixelifySans-Variable.ttf"
const STAT_FONT_PATH := FONT_DIR + "/Silkscreen-Regular.ttf"
const STAT_BOLD_FONT_PATH := FONT_DIR + "/Silkscreen-Bold.ttf"
## OpenType 'wght' axis tag ('w'<<24 | 'g'<<16 | 'h'<<8 | 't'), so the variable
## display face can be asked for its bold instance without a second file.
const _WGHT_TAG := 2003265652

# --- shell palette: new tokens (no shipped authority), from tokens/colors.css ---
const SLATE_900 := Color(0.13725, 0.15294, 0.16863)  # #23272b page backdrop
const SLATE_800 := Color(0.16863, 0.18431, 0.20392)  # #2b2f34 raised dark surface
const SLATE_700 := Color(0.22745, 0.24706, 0.27059)  # #3a3f45
const NEUTRAL := Color(0.54118, 0.56471, 0.60000)  # #8a9099 un-owned property grey
const NEUTRAL_DARK := Color(0.34902, 0.36471, 0.38824)  # #595d63
const NEUTRAL_LIGHT := Color(0.67843, 0.69412, 0.71765)  # #adb1b7
const PAPER_RAISED := Color(0.95686, 0.93725, 0.89020)  # #f4efe3 hovered/selected cream
const PAPER_2 := Color(0.81176, 0.81176, 0.81176)  # #cfcfcf secondary grey panel
const CAPTURE := Color(0.42353, 0.76078, 0.29020)  # #6cc24a capture green (toggle ON)
const WHITE := Color(0.93333, 0.93333, 0.93333)  # #eeeeee pure light
## The signature hard drop shadow: ink, 90% opaque, zero blur. rgba(35,39,43,.9).
const SHADOW_INK := Color(0.13725, 0.15294, 0.16863, 0.9)

# --- aliases: colours that already have a shipped authority (plan D1) ----------
## Cream panel surface and the two inks on it stay CommanderVisuals', so the menu
## and the terrain panel can never disagree about what "paper" is.
const PAPER := CommanderVisuals.PAPER
const INK := CommanderVisuals.PAPER_INK  # body text / muted borders on cream
const HARD_BORDER := CommanderVisuals.HARD_BORDER  # the darkest outline

# --- canvas-pixel metrics (plan section 2) -------------------------------------
const CONTENT_W := 370  # handoff 740 content column
const ACTION_W := 122  # handoff 244 action stack
const GAP := 8  # handoff 16 column gap
const BORDER := 1  # chrome outline; 2 physical px on the default window
const PANEL_BORDER := 2  # the panel's heavier outline
const SHADOW := 1  # hard-shadow size; shows 2*SHADOW canvas px past bottom-right
const RADIUS := 1  # a whisker of rounding, at most

const SIZE_WORDMARK := 24
const SIZE_TITLE := 8
const SIZE_BUTTON := 10
const SIZE_BODY := 8
const SIZE_SEGMENT := 7
const SIZE_MICRO := 6  # Silkscreen micro-labels; 12 physical px, R1's floor

enum ButtonVariant { PRIMARY, SECONDARY, GHOST }

static var _display: FontFile
static var _stat: FontFile
static var _stat_bold: FontFile
static var _display_bold: FontVariation

# --- fonts -------------------------------------------------------------------


## Pixelify Sans — display & UI chrome. `bold` asks the variable face for its
## 700-weight instance (the wordmark and panel titles), no second file needed.
static func display(bold := false) -> Font:
	if bold:
		if _display_bold == null:
			_display_bold = FontVariation.new()
			_display_bold.base_font = _display_face()
			_display_bold.variation_opentype = {_WGHT_TAG: 700}
		return _display_bold
	return _display_face()


## Silkscreen — micro-labels, numerals, badges. `bold` loads the static bold cut.
static func stat(bold := false) -> Font:
	if bold:
		if _stat_bold == null:
			_stat_bold = _tuned(STAT_BOLD_FONT_PATH)
		return _stat_bold
	if _stat == null:
		_stat = _tuned(STAT_FONT_PATH)
	return _stat


static func _display_face() -> FontFile:
	if _display == null:
		_display = _tuned(DISPLAY_FONT_PATH)
	return _display


## Loads a face and switches off every source of blur: no antialiasing, no
## subpixel drift, no hinting — so the glyphs rasterise on the same pixel grid the
## tile and unit art already lives on (plan D2, and R1's mitigation).
static func _tuned(path: String) -> FontFile:
	var face: FontFile = load(path)
	face.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	face.hinting = TextServer.HINTING_NONE
	return face


# --- the faction hues, never re-declared (plan D4) ---------------------------


## The default side identities a commander-less match plays as: team 1 in the
## classic meridian red, team 2 in aurora blue. The menu's faction hues — the 1P
## and 2P button fills, the identity chip dots, the selected-map border — all read
## from this, so they stay CommanderVisuals' colours and never a fourth copy.
static func menu_identity() -> SideIdentity:
	return SideIdentity.resolve({1: null, 2: null})


# --- stylebox factories ------------------------------------------------------


## A flat fill with no border or shadow — the atom the header bands and chips are
## built from.
static func flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.anti_aliasing = false
	return box


## The signature look, applied to any StyleBoxFlat: a hard offset shadow with zero
## blur. `shadow_size = n`, `shadow_offset = (n, n)` grows the shadow rect by n and
## shifts it, so it sits flush under the top-left edges and shows exactly 2n canvas
## pixels of ink past the bottom-right — CSS `2n 2n 0` (plan D3). Proven here first.
static func hard_shadow(box: StyleBoxFlat, size := SHADOW) -> StyleBoxFlat:
	box.shadow_color = SHADOW_INK
	box.shadow_size = size
	box.shadow_offset = Vector2(size, size)
	box.anti_aliasing = false
	return box


## The cream Match Setup panel: paper surface, ink outline, hard shadow. The
## game's universal container (handoff Panel.jsx, `tone: cream`).
static func panel_box() -> StyleBoxFlat:
	var box := flat(PAPER)
	box.border_color = HARD_BORDER
	box.set_border_width_all(PANEL_BORDER)
	box.set_corner_radius_all(RADIUS)
	return hard_shadow(box)


## The dark variant — slate surface for HUD-style overlays (the select page's
## backdrop panels). Same outline and shadow as the cream panel.
static func dark_panel_box(fill := SLATE_800) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = HARD_BORDER
	box.set_border_width_all(PANEL_BORDER)
	box.set_corner_radius_all(RADIUS)
	return hard_shadow(box)


## A panel's title band — the header bar that spans the top of a Panel. Ink by
## default, or a faction fill when the panel belongs to a side.
static func header_box(fill := HARD_BORDER) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = HARD_BORDER
	box.border_width_bottom = BORDER
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


## One segment of a segmented control: the active segment carries the faction
## fill with white text, the rest are paper. Segments butt against each other and
## are split by the parent box's inner ink rules (drawn by the caller as thin
## dividers), so a segment itself is borderless.
static func segment_box(active: bool, accent: Color) -> StyleBoxFlat:
	var box := flat(accent if active else PAPER)
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	box.content_margin_left = 2
	box.content_margin_right = 2
	return box


## The chunky focus ring — a bright border that reads at a glance for keyboard and
## controller users. Faction blue by default (handoff --focus-ring), swappable so
## a gold-selected surface can keep its own accent.
static func focus_box(accent := menu_identity().theme(2).color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = accent
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS)
	box.anti_aliasing = false
	# Lift the ring a pixel off the control so it reads as a ring, not a repaint.
	box.expand_margin_left = 1
	box.expand_margin_right = 1
	box.expand_margin_top = 1
	box.expand_margin_bottom = 1
	return box


# --- the faction/cream/ghost button, all states (handoff Button.jsx) ----------


## Dresses a Button in the design system's recipe: chunky outline, hard offset
## shadow, snaps down on press (the shadow collapses and the label shifts into its
## place), hover brightens, disabled desaturates to 45%. One implementation, read
## by both the menu action stack and the select page (plan MN3), so the press
## feels identical wherever a button lives.
##
## `theme` tints a PRIMARY button to a faction; SECONDARY is cream, GHOST is
## chrome-less. Font colour is set per state so the label tracks the fill.
static func apply_button(
	button: Button,
	variant: ButtonVariant,
	theme: CommanderVisuals.FactionTheme = null,
	size := SIZE_BUTTON
) -> void:
	button.add_theme_font_override("font", display())
	button.add_theme_font_size_override("font_size", size)

	var fill := PAPER
	var border := HARD_BORDER
	var fg := INK
	match variant:
		ButtonVariant.PRIMARY:
			var t := theme if theme != null else menu_identity().theme(1)
			fill = t.color
			border = t.color_dark
			fg = t.ink
		ButtonVariant.SECONDARY:
			fill = PAPER
			border = HARD_BORDER
			fg = INK
		ButtonVariant.GHOST:
			fill = Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			fg = WHITE

	var ghost := variant == ButtonVariant.GHOST
	button.add_theme_stylebox_override("normal", _button_box(fill, border, not ghost))
	button.add_theme_stylebox_override(
		"hover", _button_box(_brighten(fill, ghost), border, not ghost)
	)
	button.add_theme_stylebox_override("pressed", _pressed_box(fill, border))
	button.add_theme_stylebox_override("disabled", _disabled_box(fill, border, not ghost))
	button.add_theme_stylebox_override("focus", focus_box())

	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.6))


static func _button_box(fill: Color, border: Color, shadow: bool) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = border
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	if shadow:
		hard_shadow(box)
	return box


## Pressed: the shadow is gone and the content shifts down-right by the shadow's
## size, so the button reads as having dropped onto the board (Button.jsx's
## `translate(2px,2px)` with the shadow removed). A state swap, no tween (plan D3).
static func _pressed_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = border
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = 6 + SHADOW
	box.content_margin_top = 3 + SHADOW
	box.content_margin_right = 6 - SHADOW
	box.content_margin_bottom = 3 - SHADOW
	return box


static func _disabled_box(fill: Color, border: Color, shadow: bool) -> StyleBoxFlat:
	var faded := Color(fill.r, fill.g, fill.b, fill.a * 0.45)
	var box := _button_box(_desaturate(faded), border, shadow)
	return box


# --- small colour maths ------------------------------------------------------


## Hover brightening. A PRIMARY/SECONDARY fill lifts toward white (Button.jsx's
## `brightness(1.07)`); a GHOST, which has no fill, takes a faint white wash.
static func _brighten(color: Color, ghost: bool) -> Color:
	if ghost:
		return Color(1, 1, 1, 0.10)
	return color.lightened(0.07)


static func _desaturate(color: Color) -> Color:
	var grey := color.get_luminance()
	return Color(color, color.a).lerp(Color(grey, grey, grey, color.a), 0.6)
