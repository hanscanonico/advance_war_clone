class_name CaptureStage
extends Control
## The diorama half of the capture cut-in: a strip of ground, the property being
## taken drawn from the board's own atlas cell, and a squad of infantry marching
## up to mash it down. The name/CAPTURE plate sits above, the property/defence
## plate below.
##
## Draws, and does nothing else — the sibling of CutsceneSide. Every value it
## renders is written onto it by CaptureCutscene, which owns the clock; the stage
## never reads the simulation, never advances time, and never decides an outcome.
## The property is the board's own art (plan D2): the terrain atlas cell for the
## property's column, in the owner's team row, swapped to the capturer's row at
## the flip. The squad is the board's own unit art, blown up, never redrawn.

const PLATE_TOP_H := 26
const PLATE_BOT_H := 20
## Share of the arena the grass plane fills, up from the bottom.
const GROUND_RATIO := 0.42
## How big the property is drawn. The board cell is 64 px; here it fills a good
## third of the frame so the flip is the thing the eye lands on.
const PROP_PX := 132.0
## Where the property's base sits, as a share of the arena, and how high off the
## bottom its feet rest.
const PROP_CENTER := 0.66
const FEET_RATIO := 0.82
## The squad's art size and how many figures march (plan: infantry/mech capture,
## a three-figure squad carries it — the pip-exact number lives on the meter).
const FIGURE_PX := 64
const SQUAD_SIZE := 3
## Where each figure stands relative to the squad's anchor, back to front.
const SQUAD_SLOTS: Array[Vector2] = [
	Vector2(0.0, 8.0),
	Vector2(30.0, -10.0),
	Vector2(58.0, 12.0),
]
## How far off the left edge the squad starts its march, and where it settles —
## a share of the width left of the property.
const MARCH_FROM := -280.0
const MARCH_TO := 0.24

const GRASS := Color(0.471, 0.784, 0.314)
const GRASS_DARK := Color(0.353, 0.651, 0.235)
const GOLD := Color(0.969, 0.788, 0.282)
const DUST := Color(0.941, 0.925, 0.886)
const MAX_STARS := 4
const STAR_STEP := 11.0

# --- pose, written every frame by CaptureCutscene -----------------------------

var unit: Unit
var terrain: TerrainType
## The property's atlas column and the two team rows the flip crosses between.
var prop_col := 0
var row_before := 0
var row_after := 0
## The capturer's faction accent, for the name-plate bar.
var accent := Color.WHITE
## 0 -> 1 as the plates slide in and their text appears.
var plate_p := 0.0
## Squad march, 0 -> 1: slides in from the left. Then `hop_advance` (0 -> 1)
## carries it the rest of the way to the building over the hops, and `squad_y`
## lifts it on each one. `hop_advance` is a fraction so the director never needs
## the control's pixel width.
var march_p := 0.0
var hop_advance := 0.0
var squad_y := 0.0
## The building's squash on a landing: wider and shorter, about its base.
var squash := 0.0
## 0 -> 1 white over-brighten as the flip flash peaks.
var brightness := 0.0
## Once true, the property is drawn in the capturer's row instead of the owner's.
var flipped := false
## One dust puff per hop, its own 0 -> 1; drawn at the building's base.
var dust := PackedFloat32Array()
## The cut-in's clock, for the squad's marching bob. Written by the director like
## everything else, so a posed still stays a pure function of the clock.
var clock := 0.0

var _squad_art: AtlasTexture


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Poses the stage for one capture. Called once, before the clock starts.
func bind(p_unit: Unit, p_terrain: TerrainType, p_col: int, p_before: int, p_after: int) -> void:
	unit = p_unit
	terrain = p_terrain
	prop_col = p_col
	row_before = p_before
	row_after = p_after
	_squad_art = UnitSprite.texture_for(p_unit.type, p_unit.team)


func _draw() -> void:
	if unit == null or terrain == null:
		return
	var arena := _arena()
	_draw_sky(arena)
	_draw_ground(arena)
	_draw_property(arena)
	_draw_squad(arena)
	_draw_dust(arena)
	_draw_plates()


func _arena() -> Rect2:
	return Rect2(0.0, PLATE_TOP_H, size.x, size.y - PLATE_TOP_H - PLATE_BOT_H)


# --- backdrop ----------------------------------------------------------------


func _draw_sky(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	var bands := 28
	for i in bands:
		var top := arena.position.y + (horizon - arena.position.y) * float(i) / bands
		var bottom := arena.position.y + (horizon - arena.position.y) * float(i + 1) / bands
		var shade := CutsceneSide.SKY_TOP.lerp(
			CutsceneSide.SKY_HORIZON, float(i) / float(bands - 1)
		)
		draw_rect(Rect2(0.0, top, size.x, bottom - top + 1.0), shade)
	_draw_cloud(Vector2(size.x * 0.22, arena.position.y + arena.size.y * 0.16), 1.0)
	_draw_cloud(Vector2(size.x * 0.72, arena.position.y + arena.size.y * 0.08), 0.66)


func _draw_cloud(at: Vector2, scale: float) -> void:
	var white := Color(1.0, 1.0, 1.0, 0.85)
	draw_rect(Rect2(at.x - 30.0 * scale, at.y, 60.0 * scale, 9.0 * scale), white)
	draw_circle(at + Vector2(-14.0, 1.0) * scale, 9.0 * scale, white)
	draw_circle(at + Vector2(2.0, -3.0) * scale, 13.0 * scale, white)
	draw_circle(at + Vector2(18.0, 0.0) * scale, 8.0 * scale, white)


## A grass plane receding to the horizon: rows that lighten and thin toward the
## back, so the field reads as ground rather than a wall.
func _draw_ground(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	var floor_y := arena.position.y + arena.size.y
	var depth := floor_y - horizon
	var y := horizon
	var row_h := depth * 0.06
	var toggle := 0
	while y < floor_y:
		var lit := lerpf(0.82, 1.0, clampf((y - horizon) / depth, 0.0, 1.0))
		var base := GRASS if toggle % 2 == 0 else GRASS_DARK
		draw_rect(
			Rect2(0.0, y, size.x, row_h + 1.0), Color(base.r * lit, base.g * lit, base.b * lit)
		)
		y += row_h
		row_h *= 1.5
		toggle += 1
	draw_rect(Rect2(0.0, horizon, size.x, 2.0), Color(GRASS_DARK.darkened(0.35), 0.9))
	draw_rect(Rect2(0.0, horizon - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.3))
	draw_rect(Rect2(0.0, floor_y - 16.0, size.x, 16.0), Color(0.0, 0.0, 0.0, 0.14))


func _horizon(arena: Rect2) -> float:
	return arena.position.y + arena.size.y * (1.0 - GROUND_RATIO)


# --- the property ------------------------------------------------------------


## The property, drawn from the board's own atlas cell, squashing on each mash and
## flashing white as it flips to the capturer's colours.
func _draw_property(arena: Rect2) -> void:
	var base := _prop_base(arena)
	var w := PROP_PX * (1.0 + squash * 0.4)
	var h := PROP_PX * (1.0 - squash)
	# Contact shadow, on the ground whatever the building is doing above it.
	draw_set_transform(base + Vector2(0.0, -3.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, PROP_PX * 0.5, Color(0.08, 0.10, 0.13, 0.34))
	draw_set_transform(Vector2.ZERO)
	var atlas := _terrain_atlas()
	var row := row_after if flipped else row_before
	var source := Rect2(
		prop_col * BattleView.TERRAIN_PX,
		row * BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX
	)
	var tint := Color(1.0, 1.0, 1.0).lerp(Color(3.0, 3.0, 3.0), brightness)
	draw_texture_rect_region(atlas, Rect2(base.x - w * 0.5, base.y - h, w, h), source, tint)


func _prop_base(arena: Rect2) -> Vector2:
	return Vector2(size.x * PROP_CENTER, arena.position.y + arena.size.y * FEET_RATIO)


# --- the squad ---------------------------------------------------------------


## Three infantry, marching in from the left with a bob, then hopping onto the
## property. Drawn back to front so the frontmost figure overlaps the ones behind.
func _draw_squad(arena: Rect2) -> void:
	var anchor := _squad_anchor(arena)
	var bob := 0.0
	if march_p > 0.0 and march_p < 1.0:
		bob = -absf(sin(clock * 16.0)) * 5.0
	for i in range(SQUAD_SIZE - 1, -1, -1):
		var slot: Vector2 = SQUAD_SLOTS[i]
		var stagger := (
			-absf(sin(clock * 16.0 + i)) * 4.0 if (march_p > 0.0 and march_p < 1.0) else 0.0
		)
		var feet := anchor + slot + Vector2(0.0, squad_y + bob + stagger)
		_draw_shadow(Vector2(feet.x, anchor.y + slot.y), 1.0)
		_draw_figure(feet)


## The squad's back-left anchor: it slides in from off-screen as `march_p` rises,
## then `hop_advance` carries it right to just short of the building base.
func _squad_anchor(arena: Rect2) -> Vector2:
	var settled := size.x * MARCH_TO
	var target := size.x * PROP_CENTER - PROP_PX * 0.62
	var x := lerpf(MARCH_FROM, settled, march_p) + (target - settled) * hop_advance
	var y := arena.position.y + arena.size.y * FEET_RATIO
	return Vector2(x, y)


func _draw_shadow(ground: Vector2, strength: float) -> void:
	draw_set_transform(ground + Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 20.0, Color(0.078, 0.102, 0.133, 0.3 * strength))
	draw_set_transform(Vector2.ZERO)


## One figure, standing on `feet` and facing the property (rightward). A hard
## offset shadow, then the art.
func _draw_figure(feet: Vector2) -> void:
	var box := Rect2(-FIGURE_PX * 0.5, -FIGURE_PX, FIGURE_PX, FIGURE_PX)
	draw_set_transform(feet)
	draw_texture_rect(
		_squad_art,
		Rect2(box.position + Vector2(2.0, 3.0), box.size),
		false,
		Color(0.137, 0.153, 0.169, 0.4)
	)
	draw_texture_rect(_squad_art, box, false, Color.WHITE)
	draw_set_transform(Vector2.ZERO)


## A fan of specks kicked up at the building's base on each landing.
func _draw_dust(arena: Rect2) -> void:
	var at := _prop_base(arena) + Vector2(-PROP_PX * 0.32, -6.0)
	for p in dust:
		if p <= 0.0 or p >= 1.0:
			continue
		for i in 6:
			var ang := PI + float(i) / 5.0 * PI
			var reach := lerpf(4.0, 44.0 + (i % 3) * 12.0, p)
			var s := CutsceneFx.ramp(p, [0.0, 0.4, 1.0], [6.0, 11.0, 3.0])
			var pos := at + Vector2(cos(ang) * reach, sin(ang) * reach * 0.5)
			draw_circle(pos, s * 0.5, Color(DUST, 1.0 - p))


# --- plates ------------------------------------------------------------------


func _draw_plates() -> void:
	if plate_p <= 0.0:
		return
	var slide := -40.0 * (1.0 - plate_p)
	draw_set_transform(Vector2(slide, 0.0))
	var top := Rect2(0.0, 0.0, size.x, PLATE_TOP_H)
	draw_rect(top, Color(CutsceneSide.SLATE_800, plate_p))
	draw_rect(Rect2(0.0, PLATE_TOP_H - 2.0, size.x, 2.0), Color(CutsceneSide.INK, plate_p))
	_draw_name_row(top)
	var bottom := Rect2(0.0, size.y - PLATE_BOT_H, size.x, PLATE_BOT_H)
	draw_rect(bottom, Color(CutsceneSide.SLATE_800, plate_p))
	draw_rect(Rect2(0.0, bottom.position.y, size.x, 2.0), Color(CutsceneSide.INK, plate_p))
	_draw_terrain_row(bottom)
	draw_set_transform(Vector2.ZERO)


func _draw_name_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	draw_rect(Rect2(16.0, plate.position.y + 6.0, 4.0, 13.0), Color(accent, plate_p))
	var title := unit.type.display_name.to_upper()
	draw_string(
		font,
		Vector2(26.0, plate.position.y + 18.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1.0, 1.0, 1.0, plate_p)
	)
	var name_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(
		font,
		Vector2(26.0 + name_width + 12.0, plate.position.y + 17.0),
		"CAPTURE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color(GOLD, plate_p)
	)


func _draw_terrain_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	var label := terrain.display_name.to_upper()
	draw_string(
		font,
		Vector2(20.0, plate.position.y + 14.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color(CutsceneSide.PLATE_TEXT, CutsceneSide.PLATE_TEXT.a * plate_p)
	)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var stars := mini(terrain.defense_stars, MAX_STARS)
	for i in MAX_STARS:
		var center := Vector2(20.0 + width + 14.0 + STAR_STEP * i, plate.position.y + 10.0)
		var tint := CutsceneSide.STAR_ON if i < stars else CutsceneSide.STAR_OFF
		draw_colored_polygon(_star_points(center, 4.5), Color(tint, tint.a * plate_p))


static func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var reach := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	return points


static func _terrain_atlas() -> Texture2D:
	return load(BattleView.ATLAS_PATH)
