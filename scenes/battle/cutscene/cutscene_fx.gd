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
const KO_RED := Color(0.902, 0.302, 0.243)

## Ceiling on rounds drawn per volley. Five figures firing three apiece is
## fifteen dashes on a 640 px stage, which reads as a smear rather than a burst.
const MAX_ROUNDS := 8
## How far apart, in travel progress, consecutive rounds leave the barrel.
const ROUND_STAGGER := 0.085
## How far below the firing line a torpedo runs. The firing line is at the hull's
## gun, so this is roughly the waterline the wake belongs on.
const WAKE_DEPTH := 26.0

# --- pose, written every frame by CombatCutscene ------------------------------

## 0 while nothing is in flight; otherwise the volley's travel, 0 -> 1.
var volley_p := 0.0
var volley_from := Vector2.ZERO
var volley_to := Vector2.ZERO
## The firing side's BattleStyle: what the rounds look like, how many there are,
## and how high they arc. Never null while a volley is up.
var volley_style: BattleStyle
## How many figures are firing it. Held separately from `muzzles`, which is only
## populated for the few frames the barrels are alight — the volley outlives the
## flash, and a squad that has already stopped flashing is still five men firing.
var volley_figures := 1
## The lob height this particular volley uses. Held here rather than read off the
## style, because an indirect weapon arcs higher than the same style fired flat
## and a Resource is shared — writing the nudge onto it would change the arc for
## every unit that names it.
var volley_arc := 0.0
## Every barrel alight this frame — one per standing figure. Empty for all but
## the handful of frames after a volley leaves.
var muzzles := PackedVector2Array()
var muzzle_radius := 0.0
## The kill blast, 0 -> 1, and where it goes off.
var blast_p := 0.0
var blast_at := Vector2.ZERO
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
	for at in muzzles:
		_draw_muzzle(at)
	if volley_p > 0.0 and volley_p < 1.0 and volley_style != null:
		_draw_volley()
	if blast_p > 0.0 and blast_p < 1.0:
		_draw_blast()
	_draw_callout(atk_at, atk_amount, atk_tag, atk_p)
	_draw_callout(def_at, def_amount, def_tag, def_p)


## The volley in flight, drawn the way its style says. Rounds are staggered along
## the firing line so a squad's burst reads as several shots rather than one
## thick dash, and the whole thing is a function of `volley_p` like everything
## else here.
func _draw_volley() -> void:
	if not volley_style.fires():
		return
	var rounds := mini(volley_style.shots_per_figure * maxi(volley_figures, 1), MAX_ROUNDS)
	for i in rounds:
		var lag := clampf(volley_p - i * ROUND_STAGGER, 0.0, 1.0)
		if lag <= 0.0 or lag >= 1.0:
			continue
		_draw_round(lag, i)


## One round, at `lag` along its travel, drawn the way its projectile kind says.
## Six kinds cover eighteen units, which is the whole point of D5 — each has to
## be recognisable in a fifth of a second, so each gets a different silhouette
## rather than a different colour of the same dash.
func _draw_round(lag: float, index: int) -> void:
	var at := volley_from.lerp(volley_to, lag)
	var toward := signf(volley_to.x - volley_from.x)
	var tint := Color(volley_style.tint, 1.0 - index * 0.09)
	match volley_style.projectile:
		BattleStyle.TORPEDO:
			_draw_torpedo(at, toward, tint)
		BattleStyle.BOMB:
			# Released moving forward and then owned by gravity, so it lands on
			# the target rather than flying at it.
			at.y += lag * lag * 74.0 + (index % 2) * 9.0
			_draw_bomb(at, tint)
		BattleStyle.FLAK:
			at.y -= sin(lag * PI) * volley_arc
			at.y += (index % 3 - 1) * 7.0
			_draw_flak(at, lag, tint)
		BattleStyle.ROCKET:
			at.y -= sin(lag * PI) * volley_arc
			at.y += (index % 3 - 1) * 4.0
			_draw_rocket(at, toward, lag, tint)
		BattleStyle.SHELL:
			at.y -= sin(lag * PI) * volley_arc
			at.y += (index % 3 - 1) * 3.0
			_draw_shell(at, toward, tint)
		_:
			at.y += (index % 3 - 1) * 3.0
			_draw_tracer_dash(at, toward, tint)


## The default: a bright dash with a hard outline, so it reads over sky, ground
## and a unit alike.
func _draw_tracer_dash(at: Vector2, toward: float, tint: Color) -> void:
	var length := 14.0
	var body := Rect2(at.x - (length if toward < 0.0 else 0.0), at.y - 2.0, length, 4.0)
	draw_rect(body.grow(1.0), Color(INK, tint.a * 0.8))
	draw_rect(body, tint)


## A heavy round: a hot head with a short streak of its own smoke behind it, so
## a single shell is as legible as a wall of tracer.
func _draw_shell(at: Vector2, toward: float, tint: Color) -> void:
	for trail in 3:
		var back := at - Vector2(toward * (7.0 + trail * 6.0), -trail * 1.5)
		draw_circle(back, 4.0 - trail, Color(tint, tint.a * (0.4 - trail * 0.1)))
	draw_circle(at, 6.0, Color(INK, tint.a * 0.9))
	draw_circle(at, 4.5, tint)
	draw_circle(at, 2.0, Color(1.0, 1.0, 1.0, tint.a))


## Anti-air fire: rounds that go off in the air rather than arriving, so the
## volley reads as a wall of bursts the target has to fly through.
func _draw_flak(at: Vector2, lag: float, tint: Color) -> void:
	var puff := ramp(lag, [0.0, 0.55, 1.0], [1.5, 9.0, 13.0])
	var fade := ramp(lag, [0.0, 0.5, 1.0], [1.0, 0.8, 0.0])
	draw_circle(at, puff + 1.5, Color(INK, tint.a * fade * 0.7))
	draw_circle(at, puff, Color(tint, tint.a * fade))
	draw_circle(at, puff * 0.45, Color(1.0, 1.0, 1.0, tint.a * fade))


## A dart dragging a column of smoke that thickens and greys behind it.
func _draw_rocket(at: Vector2, toward: float, lag: float, tint: Color) -> void:
	for trail in 5:
		var back := at - Vector2(toward * (9.0 + trail * 8.0), 0.0)
		var puff := 2.0 + trail * 1.6
		var smoke := clampf(0.42 - trail * 0.07, 0.0, 1.0) * minf(lag * 4.0, 1.0)
		draw_circle(back, puff, Color(0.78, 0.76, 0.78, smoke * tint.a))
	var nose := at + Vector2(toward * 6.0, 0.0)
	draw_colored_polygon(
		PackedVector2Array(
			[nose, at + Vector2(-toward * 6.0, -3.5), at + Vector2(-toward * 6.0, 3.5)]
		),
		tint
	)
	draw_circle(at - Vector2(toward * 7.0, 0.0), 3.0, Color(FLASH_GOLD, tint.a))


## A bomb: small, dark, and falling — the only round in the game whose shape
## reads vertically, because it is the only one that arrives from above.
func _draw_bomb(at: Vector2, tint: Color) -> void:
	draw_circle(at, 4.5, Color(INK, tint.a))
	draw_circle(at + Vector2(0.0, -1.0), 3.0, tint)
	draw_rect(Rect2(at.x - 1.5, at.y + 3.0, 3.0, 5.0), Color(INK, tint.a * 0.8))


## A torpedo, run flat under the waterline: the head is barely visible and the
## wake behind it is what the eye actually follows.
func _draw_torpedo(at: Vector2, toward: float, tint: Color) -> void:
	var depth := at + Vector2(0.0, WAKE_DEPTH)
	for trail in 5:
		var back := depth - Vector2(toward * (8.0 + trail * 11.0), 0.0)
		var foam := clampf(0.6 - trail * 0.11, 0.0, 1.0)
		draw_rect(
			Rect2(back.x - 5.0, back.y - 1.5 + trail * 0.5, 10.0, 3.0 - trail * 0.4),
			Color(1.0, 1.0, 1.0, foam * tint.a)
		)
	draw_circle(depth, 4.0, Color(INK, tint.a * 0.75))
	draw_circle(depth, 2.5, tint)


## A four-pointed star at the barrel, drawn for the few frames after a volley
## leaves. One per standing figure, so a full squad lights up along its whole
## front and a lone survivor gives off a single flash.
func _draw_muzzle(at: Vector2) -> void:
	if muzzle_radius <= 0.0:
		return
	var points := PackedVector2Array()
	for i in 8:
		var reach := muzzle_radius if i % 2 == 0 else muzzle_radius * 0.32
		var angle := float(i) * PI / 4.0
		points.append(at + Vector2(cos(angle), sin(angle)) * reach)
	draw_colored_polygon(points, FLASH_GOLD)
	draw_circle(at, muzzle_radius * 0.35, Color(1.0, 1.0, 1.0, 0.95))


## The kill blast: a shock ring running out ahead of a ragged fireball, debris
## thrown clear on a ballistic arc, and smoke left rising behind it. Original and
## procedural — no explosion sheet, which is the fence D2 puts around this whole
## feature.
##
## The fireball is a jagged star rather than a disc on purpose: nested circles
## read as a bullseye at this size, and a torn silhouette reads as a blast.
func _draw_blast() -> void:
	var ring := ramp(blast_p, [0.0, 1.0], [14.0, 104.0])
	var ring_alpha := ramp(blast_p, [0.0, 0.3, 1.0], [0.9, 0.28, 0.0])
	draw_arc(blast_at, ring, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, ring_alpha), 2.0)
	_draw_debris()
	_draw_smoke()
	var core := ramp(blast_p, [0.0, 0.22, 1.0], [4.0, 54.0, 18.0])
	var core_alpha := ramp(blast_p, [0.0, 0.15, 0.7, 1.0], [0.0, 1.0, 0.6, 0.0])
	_draw_flare(core, Color(KO_RED, core_alpha * 0.9), 0.0)
	_draw_flare(core * 0.68, Color(FLASH_GOLD, core_alpha), 0.42)
	_draw_flare(core * 0.34, Color(1.0, 1.0, 1.0, core_alpha), 0.84)


## One ragged ring of the fireball: alternating long and short spokes, rotated so
## the three layers do not line their teeth up.
func _draw_flare(reach: float, tint: Color, turn: float) -> void:
	if reach <= 0.0 or tint.a <= 0.0:
		return
	var points := PackedVector2Array()
	var spokes := 18
	for i in spokes:
		var angle := turn + float(i) * TAU / spokes
		var length := reach if i % 2 == 0 else reach * 0.66
		points.append(blast_at + Vector2(cos(angle), sin(angle) * 0.86) * length)
	draw_colored_polygon(points, tint)


## Wreckage thrown clear: out fast, then dragged down, so it arcs instead of
## sliding along a straight line out of the fireball.
func _draw_debris() -> void:
	var alpha := ramp(blast_p, [0.0, 0.1, 0.75, 1.0], [0.0, 1.0, 0.9, 0.0])
	for i in 12:
		var angle := float(i) * TAU / 12.0 + (i % 3) * 0.17
		var reach := ramp(blast_p, [0.0, 0.6, 1.0], [4.0, 58.0 + (i % 4) * 16.0, 96.0])
		var drop := blast_p * blast_p * 54.0
		var at := blast_at + Vector2(cos(angle), sin(angle) * 0.7) * reach + Vector2(0.0, drop)
		var chip := 7.0 - (i % 3) * 1.5
		draw_rect(
			Rect2(at - Vector2(chip, chip) * 0.5, Vector2(chip, chip)),
			Color(FLASH_GOLD if i % 2 == 0 else KO_RED, alpha)
		)


## What is left over the wreck once the fire is out.
func _draw_smoke() -> void:
	var alpha := ramp(blast_p, [0.0, 0.35, 0.7, 1.0], [0.0, 0.0, 0.45, 0.0])
	if alpha <= 0.0:
		return
	for i in 4:
		var lift := ramp(blast_p, [0.35, 1.0], [0.0, 34.0 + i * 9.0])
		var at := blast_at + Vector2((i - 1.5) * 15.0, -lift)
		draw_circle(at, 13.0 + i * 2.5, Color(0.35, 0.34, 0.36, alpha))


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
