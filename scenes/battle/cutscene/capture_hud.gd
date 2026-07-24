class_name CaptureHud
extends Control
## The overlay half of the capture cut-in: the capture-points meter, the floating
## point chips each mash knocks off, the white flip flash, its celebration specks,
## and the CAPTURED! / OCCUPYING banner.
##
## Like CutsceneFx it only draws. Every field below is written by CaptureCutscene
## once per frame from its own clock, and every number it prints was handed to
## the cut-in by the sim — nothing here is computed from a rule. The chips sum to
## the meter's drop by construction (the director splits the sim's committed
## delta), so a press mid-mash lands on the same number the terrain panel reports.

const INK := Color(0.078, 0.090, 0.102)
const GOLD := Color(0.969, 0.788, 0.282)
const HP_LOW := Color(0.863, 0.282, 0.235)
const SLATE_800 := Color(0.161, 0.184, 0.212, 0.9)
## The points meter's twenty ticks — a full property.
const METER_TOTAL := 20

# --- pose, written every frame by CaptureCutscene -----------------------------

## The meter's current reading, 0-20, and how far it has faded in (with the plates).
var points_shown := METER_TOTAL
var meter_p := 0.0
## Floating point chips: one value and one 0 -> 1 progress per hop. Drawn as a
## "-N" rising and fading over the property.
var chip_values := PackedInt32Array()
var chip_p := PackedFloat32Array()
## Where the chips rise from — the property's head, in this control's coordinates.
var chip_at := Vector2.ZERO
## 0 -> 1 full-panel white as the flip flash peaks.
var flash := 0.0
## 0 -> 1 as the celebration specks fan out after a completing flip.
var specks_p := 0.0
var specks_at := Vector2.ZERO
var specks_accent := Color.WHITE
## The banner: its text, how far it has popped in, and whether this was a
## completing capture (gold CAPTURED!) or a partial (white OCCUPYING + count left).
var banner_text := ""
var banner_sub := ""
var banner_p := 0.0
var banner_complete := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, flash * 0.55))
	_draw_specks()
	_draw_meter()
	_draw_chips()
	_draw_banner()


## Top-right: a big N/20 numeral over twenty ticks, draining as points fall. The
## numeral turns red at zero, the moment the property is taken.
func _draw_meter() -> void:
	if meter_p <= 0.0:
		return
	var font := get_theme_font(&"font", &"Label")
	var shown := maxi(points_shown, 0)
	var right := size.x - 16.0
	var top := 14.0
	_stroked(
		font,
		Vector2(right - 74.0, top + 6.0),
		"CAPTURE PTS",
		9,
		Color(1.0, 1.0, 1.0, 0.9 * meter_p)
	)
	var big := "%d" % shown
	var big_w := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var num_tint := HP_LOW if shown <= 0 else GOLD
	_stroked(font, Vector2(right - 26.0 - big_w, top + 34.0), big, 30, Color(num_tint, meter_p))
	_stroked(
		font, Vector2(right - 22.0, top + 34.0), "/20", 14, Color(1.0, 1.0, 1.0, 0.6 * meter_p)
	)
	var pip_w := 5.0
	var gap := 1.0
	for i in METER_TOTAL:
		var x := right - (pip_w + gap) * (METER_TOTAL - i)
		var lit := i < shown
		var tint := Color(GOLD, meter_p) if lit else Color(1.0, 1.0, 1.0, 0.15 * meter_p)
		draw_rect(Rect2(x, top + 42.0, pip_w, 9.0), tint)


func _draw_chips() -> void:
	var font := get_theme_font(&"font", &"Label")
	for i in chip_values.size():
		var p := chip_p[i]
		if p <= 0.0 or p >= 1.0:
			continue
		var rise := lerpf(0.0, -52.0, p)
		var alpha := CutsceneFx.ramp(p, [0.0, 0.15, 0.75, 1.0], [0.0, 1.0, 1.0, 0.0])
		var text := "-%d" % chip_values[i]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_stroked(font, chip_at + Vector2(-w * 0.5, rise), text, 26, Color(GOLD, alpha))


## Bits of confetti thrown up when the property flips, in the capturer's accent
## and gold. Only ever drawn on a completing capture.
func _draw_specks() -> void:
	if specks_p <= 0.0 or specks_p >= 1.0:
		return
	for i in 8:
		var ang := -PI * 0.5 + (i - 3.5) * 0.32
		var reach := lerpf(10.0, 130.0 + (i % 3) * 30.0, specks_p)
		var at := specks_at + Vector2(cos(ang), sin(ang)) * reach
		var tint := specks_accent if i % 2 == 0 else GOLD
		draw_set_transform(at, specks_p * 4.2 + i * 0.7, Vector2.ONE)
		draw_rect(Rect2(-5.0, -5.0, 10.0, 10.0), Color(tint, 1.0 - specks_p))
		draw_set_transform(Vector2.ZERO)


func _draw_banner() -> void:
	if banner_p <= 0.0:
		return
	var font := get_theme_font(&"font", &"Label")
	var scale := CutsceneFx.ramp(banner_p, [0.0, 0.6, 1.0], [0.3, 1.15, 1.0])
	var center := Vector2(size.x * 0.5, size.y * 0.36)
	draw_set_transform(center, 0.0, Vector2(scale, scale))
	var size_main := 40 if banner_complete else 30
	var tint := GOLD if banner_complete else Color(1.0, 1.0, 1.0)
	var main_w := font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_main).x
	_stroked(font, Vector2(-main_w * 0.5, 0.0), banner_text, size_main, tint)
	if banner_sub != "":
		var sub_w := font.get_string_size(banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_stroked(font, Vector2(-sub_w * 0.5, 24.0), banner_sub, 18, Color(1.0, 1.0, 1.0))
	draw_set_transform(Vector2.ZERO)


## Outlined text. Everything the overlay prints sits over moving art, so nothing
## is drawn without a stroke around it — the same rule CutsceneFx follows.
func _stroked(font: Font, at: Vector2, text: String, font_size: int, tint: Color) -> void:
	draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(INK, tint.a)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
