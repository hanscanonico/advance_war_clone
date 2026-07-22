class_name CutsceneFx
extends Control
## The cut-in's overlay layer: whatever crosses the seam or sits on top of both
## halves — muzzle flash, the volley in flight, the damage each side took, and
## the VS badge that holds the frame together before the first shot.
##
## Like CutsceneSide it only draws. Every field below is written by
## CombatCutscene once per frame from its own clock, and every number it prints
## was handed to the cut-in by the sim — nothing here is computed from a rule.

## The one word that outranks a damage number. Lives here rather than on
## CombatCutscene so the dependency between the two runs one way: the director
## reads the overlay's vocabulary, never the reverse.
const KO_TAG := "K.O."

const INK := Color(0.078, 0.090, 0.102)
const FLASH_GOLD := Color(0.988, 0.847, 0.353)
const TRACER_ATK := Color(1.0, 0.949, 0.659)
const TRACER_DEF := Color(0.812, 0.878, 1.0)
const KO_RED := Color(0.902, 0.302, 0.243)

# --- pose, written every frame by CombatCutscene ------------------------------

## 0 while nothing is in flight; otherwise the volley's travel, 0 -> 1.
var tracer_p := 0.0
var tracer_from := Vector2.ZERO
var tracer_to := Vector2.ZERO
var tracer_tint := TRACER_ATK
## Set for the handful of frames a barrel is alight.
var muzzle_at := Vector2.ZERO
var muzzle_on := false
## Fades out as the first volley leaves — the badge belongs to the stare-down.
var vs_alpha := 0.0
## Damage callouts, keyed left (attacker) and right (defender). `amount` is the
## displayed HP the side lost, straight off the result's snapshot; `tag` is the
## one word that outranks it, which today is only ever "K.O.".
## `at` is the head of the figure it belongs to, so what a hit cost is printed
## over the thing that took it.
var atk_amount := 0
var atk_tag := ""
var atk_p := 0.0
var atk_at := Vector2.ZERO
var def_amount := 0
var def_tag := ""
var def_p := 0.0
var def_at := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if vs_alpha > 0.0:
		_draw_vs()
	if muzzle_on:
		_draw_muzzle(muzzle_at)
	if tracer_p > 0.0 and tracer_p < 1.0:
		_draw_tracer()
	_draw_callout(atk_at, atk_amount, atk_tag, atk_p)
	_draw_callout(def_at, def_amount, def_tag, def_p)


## Three dashes chasing each other along the firing line: the leading one at the
## volley's position, the rest trailing and dimming.
func _draw_tracer() -> void:
	for i in 3:
		var lag := clampf(tracer_p - i * 0.09, 0.0, 1.0)
		if lag <= 0.0:
			continue
		var at := tracer_from.lerp(tracer_to, lag)
		var length := 12.0 - i * 3.0
		var toward := signf(tracer_to.x - tracer_from.x)
		var tint := Color(tracer_tint, 1.0 - i * 0.28)
		draw_rect(Rect2(at.x - (length if toward < 0.0 else 0.0), at.y - 1.5, length, 3.0), tint)


## A four-pointed star at the barrel, drawn once per volley for a few frames.
func _draw_muzzle(at: Vector2) -> void:
	var points := PackedVector2Array()
	for i in 8:
		var reach := 14.0 if i % 2 == 0 else 4.5
		var angle := float(i) * PI / 4.0
		points.append(at + Vector2(cos(angle), sin(angle)) * reach)
	draw_colored_polygon(points, FLASH_GOLD)
	draw_circle(at, 5.0, Color(1.0, 1.0, 1.0, 0.95))


## The damage that landed, rising and fading over the side it landed on. Scaled
## through a quick overshoot so it punches rather than drifts.
func _draw_callout(at: Vector2, amount: int, tag: String, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var font := get_theme_font(&"font", &"Label")
	var rise := ramp(progress, [0.0, 0.3, 1.0], [10.0, -8.0, -26.0])
	var punch := ramp(progress, [0.0, 0.25, 1.0], [0.4, 1.2, 1.0])
	var alpha := ramp(progress, [0.0, 0.15, 0.7, 1.0], [0.0, 1.0, 1.0, 0.0])
	var origin := at + Vector2(0.0, rise)
	draw_set_transform(origin, 0.0, Vector2(punch, punch))
	if tag != "":
		var tag_width := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tag_tint := KO_RED if tag == KO_TAG else FLASH_GOLD
		_stroked(font, Vector2(-tag_width * 0.5, -18.0), tag, 15, Color(tag_tint, alpha))
	if amount > 0:
		var text := "-%d" % amount
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_stroked(font, Vector2(-width * 0.5, 8.0), text, 26, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO)


func _draw_vs() -> void:
	var font := get_theme_font(&"font", &"Label")
	var width := font.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_stroked(
		font,
		Vector2(size.x * 0.5 - width * 0.5, size.y * 0.5 + 8.0),
		"VS",
		22,
		Color(1.0, 1.0, 1.0, vs_alpha)
	)


## Outlined text. Everything the overlay prints sits over moving art, so nothing
## is ever drawn without a stroke around it.
func _stroked(font: Font, at: Vector2, text: String, font_size: int, tint: Color) -> void:
	draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(INK, tint.a)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


## Piecewise linear interpolation over matched stop/value lists — the one shape
## every eased value in the cut-in is written as, here and in the director.
static func ramp(at: float, stops: Array, values: Array) -> float:
	for i in range(1, stops.size()):
		if at <= stops[i]:
			var span: float = stops[i] - stops[i - 1]
			var t: float = 0.0 if span <= 0.0 else (at - stops[i - 1]) / span
			return lerpf(values[i - 1], values[i], t)
	return values[values.size() - 1]
