class_name CutsceneSide
extends Control
## One half of the battle cut-in: a unit posed over a strip of its own terrain,
## with a name/HP plate above it and a terrain/defence plate below.
##
## Draws, and does nothing else. Every value it renders is written onto it by
## CombatCutscene, which owns the clock: the side never reads the simulation,
## never advances time, and never decides an outcome. `mirror` is the only
## difference between the attacker's half and the defender's.
##
## The ground is the board's own terrain art, tiled in three receding bands, and
## the figure is the board's own unit art — blown up, never redrawn (plan D2).
## The one thing derived rather than drawn is the horizon ridge's colour, which
## is averaged off the terrain tile so a new terrain needs no entry anywhere.

const PLATE_TOP_H := 26
const PLATE_BOT_H := 20
## Share of the arena the ground plane fills, measured up from the bottom.
const GROUND_RATIO := 0.45
## Figures are the 64 px atlas art at its own resolution — nearest-neighbour
## scaling of pixel art to a fractional size drops rows unevenly, so it isn't.
const FIGURE_PX := 64
## How far in from the outer edge the squad's *middle* sits. Squads are centred
## on this whatever their size, so a lone 1 HP straggler holds the same ground a
## full five did rather than standing off at the edge of the frame where the
## outermost of five would have been.
const SQUAD_CENTER := 132.0
## Where the figures' feet sit, as a share of the arena height.
const FEET_RATIO := 0.86
## Advance Wars' rule: one figure per two displayed HP, so a full squad is five
## and a battered 1 HP straggler fights alone (plan D3). Figures carry the feel;
## the pip bar above them carries the exact number.
const MAX_FIGURES := 5
## Where each figure stands, offset from the outermost one. Staggered rather than
## in a line so five 64 px sprites read as a cluster instead of a row, and drawn
## back to front so the outermost is the one in front.
const SLOTS: Array[Vector2] = [
	Vector2(0.0, 6.0),
	Vector2(44.0, -12.0),
	Vector2(86.0, 9.0),
	Vector2(128.0, -8.0),
	Vector2(168.0, 13.0),
]
## How far apart, in fall progress, consecutive figures start toppling.
const TOPPLE_STAGGER := 0.13
## How high aircraft ride above their own ground, and the bob they hold there.
## The phase step keeps a flight of four from pulsing in unison.
const HOVER_HEIGHT := 34.0
const HOVER_SWING := 4.0
const HOVER_RATE := 4.4
const HOVER_PHASE := 1.1

const INK := Color(0.078, 0.090, 0.102)
const SLATE_800 := Color(0.161, 0.184, 0.212)
const SKY_TOP := Color(0.290, 0.486, 0.667)
const SKY_HORIZON := Color(0.749, 0.902, 0.949)
const STAR_ON := Color(0.969, 0.788, 0.282)
const STAR_OFF := Color(1.0, 1.0, 1.0, 0.22)
const HP_FULL := Color(0.376, 0.769, 0.329)
const HP_MID := Color(0.910, 0.722, 0.227)
const HP_LOW := Color(0.863, 0.282, 0.235)
const HP_EMPTY := Color(1.0, 1.0, 1.0, 0.12)
const PLATE_TEXT := Color(1.0, 1.0, 1.0, 0.88)
## What a knocked-out figure burns down to on its way off the field.
const WRECK_TINT := Color(0.22, 0.20, 0.21)

const PIP_COUNT := 10
const PIP_SIZE := Vector2(6, 8)
const PIP_GAP := 1.0
const MAX_STARS := 4
const STAR_STEP := 11.0
## How far plate content is held off the frame's outer edge. Generous on purpose:
## the band pushes in slightly over the exchange, so a few pixels either side are
## outside the viewport at the moment the volley lands.
const PLATE_MARGIN := 26.0
## The matching hold-off from the seam, for the content that sits against it.
const SEAM_MARGIN := 18.0

## Cached average colour per terrain atlas cell — the horizon ridge's tint. Keyed
## by atlas (column, row) rather than terrain id so an owner-tinted city ridge
## follows the same team colour the board paints.
static var _tint_cache: Dictionary = {}

var unit: Unit
var terrain: TerrainType
## Owner of the cell this side is fought over, for the team-tinted atlas row.
var owner_team := 0
## True for the defender's half: art, plates and squad all face the other way.
var mirror := false

# --- pose, written every frame by CombatCutscene ------------------------------

## Displayed HP the pips currently show. Ticks from the result's snapshot to the
## unit's real HP across the impact beat.
var hp_shown := 10
## How many figures this side ends the exchange with, and how many it started
## with. Both are whole counts written by the director rather than derived from
## the ticking `hp_shown`, so surplus figures topple once, together, from the
## start of their fall — deriving them mid-tick pops a figure into a topple that
## is already half over.
var squad_now := MAX_FIGURES
var squad_was := MAX_FIGURES
## 0 -> 1 as the surplus figures rise, spin and fall away.
var fall_p := 0.0
## Recoil offset along the firing axis: negative pulls back, positive thrusts.
var lunge := 0.0
## 0 -> 1 white over-brighten on taking a hit.
var flash := 0.0
## Fades whatever is left standing — what the death explosion takes with it.
var squad_alpha := 1.0
## 0 -> 1 as the plates slide in and their text appears.
var plate_p := 0.0
## The cut-in's clock, in seconds, for the one thing here that is a function of
## time rather than of a beat: an aircraft's hover bob. Written by the director
## like everything else, so a posed still is still a pure function of `_t`.
var clock := 0.0

var _art: AtlasTexture
var _ridge_tint := Color.SLATE_GRAY
## Cached off the unit's domain at bind time — asked once per cut-in rather than
## once per figure per frame.
var _flying := false
var _floating := false


func _ready() -> void:
	clip_contents = true  # the ground tiles and a toppling figure both overrun
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Poses this half for one exchange. Called once per cut-in, before the clock
## starts; everything after that is the pose fields above.
func bind(p_unit: Unit, p_terrain: TerrainType, p_owner_team: int, p_mirror: bool) -> void:
	unit = p_unit
	terrain = p_terrain
	owner_team = p_owner_team
	mirror = p_mirror
	_art = UnitSprite.texture_for(p_unit.type, p_unit.team)
	_ridge_tint = _ground_tint(p_terrain.atlas_col, _atlas_row())
	_flying = p_unit.type.domain == UnitType.AIR
	_floating = p_unit.type.domain == UnitType.SEA


## Advance Wars' squad rule: one figure per two displayed HP, capped at five.
## Zero only ever means dead.
static func figures_for(displayed_hp: int) -> int:
	return clampi(ceili(displayed_hp / 2.0), 0, MAX_FIGURES)


## Every standing figure's barrel, in this control's coordinates, innermost last
## — the muzzle flashes go on all of them and the volley leaves from the last,
## which is the figure nearest the enemy. Derived from the same layout numbers
## the squad is drawn with rather than hand-tuned twice.
func muzzle_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var arena := _arena()
	for slot in squad_now:
		var at := figure_point(arena, slot) + Vector2(_inward(22.0), -34.0)
		points.append(at + Vector2(0.0, _altitude(slot, 0.0)))
	return points


## Where one figure of the squad stands, in this control's coordinates.
##
## The formation is laid out from its own middle rather than from its outermost
## figure: the posted squad's span is measured off `squad_was` and halved, so
## every size stays centred on SQUAD_CENTER.
func figure_point(arena: Rect2, slot: int) -> Vector2:
	var offset: Vector2 = SLOTS[clampi(slot, 0, SLOTS.size() - 1)]
	var span: float = SLOTS[clampi(squad_was - 1, 0, SLOTS.size() - 1)].x
	return Vector2(
		_outward_px(SQUAD_CENTER - span * 0.5 + offset.x),
		arena.position.y + arena.size.y * FEET_RATIO + offset.y
	)


## Where this side's callout sits, where an incoming round is aimed, and where
## the kill blast goes off: the middle of the squad, at body height rather than
## down at its feet. Fixed for the whole cut-in, so nothing anchored here drifts
## sideways as figures fall out from under it.
## Deliberately without the hover bob: a shot aimed at a bobbing point, or a
## damage number pinned to one, would judder for the whole beat.
func center_point() -> Vector2:
	var arena := _arena()
	var cruise := HOVER_HEIGHT if _flying else 0.0
	return Vector2(
		_outward_px(SQUAD_CENTER), arena.position.y + arena.size.y * FEET_RATIO - 28.0 - cruise
	)


func _arena() -> Rect2:
	return Rect2(0.0, PLATE_TOP_H, size.x, size.y - PLATE_TOP_H - PLATE_BOT_H)


func _draw() -> void:
	if unit == null:
		return
	var arena := _arena()
	_draw_sky(arena)
	_draw_ground(arena)
	_draw_squad(arena)
	_draw_vignette(arena)
	_draw_plates()


# --- backdrop ----------------------------------------------------------------


## Graded sky, two blocky clouds, and a ridge of the same ground sitting on the
## horizon. All of it above the ground line.
func _draw_sky(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	var bands := 32
	for i in bands:
		var top := arena.position.y + (horizon - arena.position.y) * float(i) / bands
		var bottom := arena.position.y + (horizon - arena.position.y) * float(i + 1) / bands
		var shade := SKY_TOP.lerp(SKY_HORIZON, float(i) / float(bands - 1))
		draw_rect(Rect2(0.0, top, size.x, bottom - top + 1.0), shade)
	_draw_cloud(Vector2(_outward(0.30), arena.position.y + arena.size.y * 0.17), 1.0)
	_draw_cloud(Vector2(_outward(0.74), arena.position.y + arena.size.y * 0.07), 0.62)
	# Distant country, not scenery: the ridge is the ground's own colour washed
	# most of the way toward the sky, so it sits behind the horizon instead of
	# competing with the field the fight is on.
	var far := _ridge_tint.darkened(0.25).lerp(SKY_HORIZON, 0.55)
	_draw_hill(horizon, _outward(0.34), 260.0, 26.0, Color(far, 0.85))
	_draw_hill(horizon, _outward(0.90), 190.0, 19.0, Color(far, 0.85))
	var near := _ridge_tint.darkened(0.3).lerp(SKY_HORIZON, 0.3)
	_draw_hill(horizon, _outward(0.04), 150.0, 13.0, Color(near, 0.9))
	_draw_hill(horizon, _outward(0.66), 200.0, 16.0, Color(near, 0.9))


## The ground plane: the cell's own atlas tile, in rows that keep their width and
## grow taller as they come forward. That vertical squash is the whole trick —
## the same square tile foreshortened near the horizon and full height at the
## camera reads as a plane receding away, and the art is exactly what the board
## draws on that square (plan D2).
func _draw_ground(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	var floor_y := arena.position.y + arena.size.y
	var depth := floor_y - horizon
	var atlas := _terrain_atlas()
	var source := Rect2(
		terrain.atlas_col * BattleView.TERRAIN_PX,
		_atlas_row() * BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX
	)
	var y := horizon
	var row_h := depth * 0.05
	while y < floor_y:
		# Rows also lighten as they approach: distance drains contrast, which is
		# what keeps the far ground from reading as a wall behind the near one.
		var lit := lerpf(0.76, 1.0, clampf((y - horizon) / depth, 0.0, 1.0))
		_tile_row(atlas, source, y, row_h, Color(lit, lit, lit))
		y += row_h
		row_h *= 1.6
	# A lit lip over a dark band is what makes the horizon read as an edge
	# rather than as the seam between two textures.
	draw_rect(Rect2(0.0, horizon, size.x, 2.0), Color(_ridge_tint.darkened(0.55), 0.9))
	draw_rect(Rect2(0.0, horizon - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.35))
	draw_rect(Rect2(0.0, floor_y - 18.0, size.x, 18.0), Color(0.0, 0.0, 0.0, 0.16))


## One row of terrain tiles across the full width: full tile width, squashed to
## `row_h` tall.
func _tile_row(atlas: Texture2D, source: Rect2, top: float, row_h: float, shade: Color) -> void:
	var tile := float(BattleView.TERRAIN_PX)
	var x := -tile * 0.5
	while x < size.x:
		draw_texture_rect_region(atlas, Rect2(x, top, tile, row_h + 1.0), source, shade)
		x += tile


func _horizon(arena: Rect2) -> float:
	return arena.position.y + arena.size.y * (1.0 - GROUND_RATIO)


func _draw_cloud(at: Vector2, scale: float) -> void:
	var white := Color(1.0, 1.0, 1.0, 0.85)
	draw_rect(Rect2(at.x - 30.0 * scale, at.y, 60.0 * scale, 9.0 * scale), white)
	draw_circle(at + Vector2(-14.0, 1.0) * scale, 9.0 * scale, white)
	draw_circle(at + Vector2(2.0, -3.0) * scale, 13.0 * scale, white)
	draw_circle(at + Vector2(18.0, 0.0) * scale, 8.0 * scale, white)


func _draw_hill(base_y: float, center_x: float, width: float, height: float, tint: Color) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		points.append(Vector2(center_x - width * 0.5 + width * t, base_y - sin(t * PI) * height))
	points.append(Vector2(center_x + width * 0.5, base_y))
	points.append(Vector2(center_x - width * 0.5, base_y))
	draw_colored_polygon(points, tint)


## Cinematic framing: the arena darkens toward its edges so the eye lands on the
## squad rather than on the seam between the halves.
func _draw_vignette(arena: Rect2) -> void:
	var steps := 10
	for i in steps:
		var alpha := 0.030 * (steps - i) / float(steps)
		var band := 4.0
		var offset := i * band
		draw_rect(
			Rect2(offset, arena.position.y, band, arena.size.y), Color(0.05, 0.06, 0.10, alpha)
		)
		draw_rect(
			Rect2(size.x - offset - band, arena.position.y, band, arena.size.y),
			Color(0.05, 0.06, 0.10, alpha)
		)
		draw_rect(
			Rect2(0.0, arena.position.y + arena.size.y - offset - band, size.x, band),
			Color(0.05, 0.06, 0.10, alpha)
		)


# --- the squad ---------------------------------------------------------------


## The squad: one figure per two HP the side went in with, the surplus toppling
## away as the volley lands. Drawn back to front so the outermost figure — the
## one nearest the camera's edge of the frame — is the one in front.
func _draw_squad(arena: Rect2) -> void:
	if squad_alpha <= 0.0:
		return
	var posted := maxi(squad_now, squad_was)
	# Each falls a beat after the one before it, so a squad losing three figures
	# reads as three going down rather than a row vanishing. `reach` is what pays
	# for that: the last one to start still has a full fall left when the window
	# closes, so the run has to be long enough for all of them to finish it.
	var reach := 1.0 + TOPPLE_STAGGER * maxf(posted - squad_now - 1, 0.0)
	for slot in range(posted - 1, -1, -1):
		var ground := figure_point(arena, slot)
		var toppling := slot >= squad_now
		var fall := 0.0
		if toppling:
			fall = clampf(fall_p * reach - (slot - squad_now) * TOPPLE_STAGGER, 0.0, 1.0)
		if fall >= 1.0:
			continue
		# The shadow stays on the ground whatever the figure is doing above it —
		# which is exactly what makes an aircraft read as flying rather than as a
		# tank drawn too high.
		_draw_shadow(ground, 1.0 - fall)
		_draw_figure(ground + Vector2(_inward(lunge), _altitude(slot, fall)), fall, not toppling)


## How far above its own patch of ground a figure sits. Aircraft ride high and
## bob, each on its own phase so a flight of four does not pulse in unison;
## everything else stands on the deck. A falling figure loses its lift as it
## goes: a shot-down plane comes down.
func _altitude(slot: int, fall: float) -> float:
	if not _flying:
		return 0.0
	var bob := sin(clock * HOVER_RATE + slot * HOVER_PHASE) * HOVER_SWING
	return (-HOVER_HEIGHT + bob) * (1.0 - fall)


## Ground units get a flattened contact shadow — the light is high and the
## ground is a plane, so it lies down on it. A hull gets a pale wake instead: a
## dark disc under a ship reads as a hole in the water.
func _draw_shadow(ground: Vector2, strength: float) -> void:
	var tint := Color(0.078, 0.102, 0.133, 0.3 * strength * squad_alpha)
	var reach := 22.0
	if _floating:
		tint = Color(1.0, 1.0, 1.0, 0.28 * strength * squad_alpha)
		reach = 26.0
	elif _flying:
		# Cast from height: wider, fainter, and further from the thing casting it.
		tint.a *= 0.55
		reach = 26.0
	draw_set_transform(ground + Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, reach, tint)
	draw_set_transform(Vector2.ZERO)


## One figure, standing on `feet` and facing the seam. Drawn twice: a hard offset
## shadow first, then the art, over-brightened while flashing — the same
## white-hit language UnitSprite already uses on the board.
##
## `fall` above zero knocks it out: kicked up and back, tipping over, burning
## down to a dark silhouette as it goes. The tip is deliberately shallow — these
## are the board's own three-quarter-view sprites, and spinning one right over
## reads as a rendering glitch rather than a casualty (plan R3).
##
## A figure already on its way down does not flash: it has taken its hit.
func _draw_figure(feet: Vector2, fall: float, hittable: bool) -> void:
	var flip := Vector2(-1.0 if mirror else 1.0, 1.0)
	var box := Rect2(-FIGURE_PX * 0.5, -FIGURE_PX, FIGURE_PX, FIGURE_PX)
	var lift := 0.0
	var spin := 0.0
	var alpha := squad_alpha
	var tint := Color(1.0, 1.0, 1.0)
	if fall > 0.0:
		lift = CutsceneFx.ramp(fall, [0.0, 0.3, 1.0], [0.0, -13.0, 46.0])
		spin = CutsceneFx.ramp(fall, [0.0, 1.0], [0.0, _inward(-0.55)])
		alpha *= CutsceneFx.ramp(fall, [0.0, 0.55, 1.0], [1.0, 1.0, 0.0])
		tint = tint.lerp(WRECK_TINT, CutsceneFx.ramp(fall, [0.0, 0.35, 1.0], [0.0, 0.85, 1.0]))
	elif hittable:
		tint = tint.lerp(Color(3.4, 3.4, 3.4), flash)
	var at := feet + Vector2(_inward(-fall * 10.0), lift)
	draw_set_transform_matrix(Transform2D(spin, flip, 0.0, at))
	var shadow := Color(0.137, 0.153, 0.169, 0.4 * alpha)
	draw_texture_rect(_art, Rect2(box.position + Vector2(2.0, 3.0), box.size), false, shadow)
	tint.a = alpha
	draw_texture_rect(_art, box, false, tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --- plates ------------------------------------------------------------------


## Name and HP above, terrain and defence stars below. Both slide in from the
## outer edge as `plate_p` rises, so the frame assembles itself rather than
## snapping into place.
func _draw_plates() -> void:
	if plate_p <= 0.0:
		return
	var slide := _inward(-40.0 * (1.0 - plate_p))
	draw_set_transform(Vector2(slide, 0.0))
	var top := Rect2(0.0, 0.0, size.x, PLATE_TOP_H)
	draw_rect(top, Color(SLATE_800, plate_p))
	draw_rect(Rect2(0.0, PLATE_TOP_H - 2.0, size.x, 2.0), Color(INK, plate_p))
	_draw_name_row(top)
	_draw_pips(top)
	var bottom := Rect2(0.0, size.y - PLATE_BOT_H, size.x, PLATE_BOT_H)
	draw_rect(bottom, Color(SLATE_800, plate_p))
	draw_rect(Rect2(0.0, bottom.position.y, size.x, 2.0), Color(INK, plate_p))
	_draw_terrain_row(bottom)
	draw_set_transform(Vector2.ZERO)


func _draw_name_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	var accent: Color = TerrainPanel.TEAM_COLORS.get(unit.team, Color.WHITE)
	var title := unit.type.display_name.to_upper()
	var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var bar_x := _outward_px(PLATE_MARGIN - 10.0) - (4.0 if mirror else 0.0)
	draw_rect(Rect2(bar_x, plate.position.y + 6.0, 4.0, 13.0), Color(accent, plate_p))
	var text_x := _outward_px(PLATE_MARGIN) - (text_width if mirror else 0.0)
	draw_string(
		font,
		Vector2(text_x, plate.position.y + 18.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1.0, 1.0, 1.0, plate_p)
	)


## Ten pips, banded by health and depleting toward the seam, so both bars run
## out in the same direction and the two sides read as one gauge.
func _draw_pips(plate: Rect2) -> void:
	var band := HP_FULL
	if hp_shown <= 3:
		band = HP_LOW
	elif hp_shown <= 6:
		band = HP_MID
	# Anchored to the seam and running outward, so both bars deplete toward the
	# middle of the frame and the two read as one gauge.
	var seam := _outward_px(size.x - SEAM_MARGIN)
	for i in PIP_COUNT:
		var step := (PIP_SIZE.x + PIP_GAP) * (PIP_COUNT - 1 - i)
		var x := seam - _inward(step) - (0.0 if mirror else PIP_SIZE.x)
		var pip := band if i < hp_shown else HP_EMPTY
		draw_rect(
			Rect2(x, plate.position.y + 9.0, PIP_SIZE.x, PIP_SIZE.y), Color(pip, pip.a * plate_p)
		)


func _draw_terrain_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	var label := terrain.display_name.to_upper()
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var text_x := _outward_px(PLATE_MARGIN) - (width if mirror else 0.0)
	draw_string(
		font,
		Vector2(text_x, plate.position.y + 14.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color(PLATE_TEXT, PLATE_TEXT.a * plate_p)
	)
	# Beside the name and reading inward, the way the tile panel already writes
	# "DEF ★☆☆☆" — anchored to the seam instead, the two sides' rows grow toward
	# each other and collide in the middle of the frame.
	var first := _outward_px(PLATE_MARGIN + width + 12.0)
	var stars := mini(terrain.defense_stars, MAX_STARS)
	for i in MAX_STARS:
		var center := Vector2(first + _inward(STAR_STEP * i), plate.position.y + 10.0)
		var tint := STAR_ON if i < stars else STAR_OFF
		draw_colored_polygon(_star_points(center, 4.5), Color(tint, tint.a * plate_p))


func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var reach := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	return points


# --- mirroring helpers -------------------------------------------------------


## An x measured from this side's *outer* edge, so one set of layout numbers
## describes both halves.
func _outward_px(from_edge: float) -> float:
	return size.x - from_edge if mirror else from_edge


## The same thing as a share of the width.
func _outward(fraction: float) -> float:
	return _outward_px(size.x * fraction)


## Flips a delta so positive always points at the seam — the direction a unit
## lunges, fires and recoils along.
func _inward(delta: float) -> float:
	return -delta if mirror else delta


func _atlas_row() -> int:
	return owner_team if terrain.team_tinted and owner_team > 0 else 0


static func _terrain_atlas() -> Texture2D:
	return load(BattleView.ATLAS_PATH)


## The terrain tile's average colour, for the horizon ridge behind it. Sampled
## off the art rather than tabled here, so a new terrain — or a repainted one —
## needs no entry in the presentation layer at all.
static func _ground_tint(column: int, row: int) -> Color:
	var key := Vector2i(column, row)
	if _tint_cache.has(key):
		return _tint_cache[key]
	var tint := Color.SLATE_GRAY
	var image: Image = _terrain_atlas().get_image()
	if image != null:
		var total := Color(0.0, 0.0, 0.0)
		var samples := 0
		for y in range(0, BattleView.TERRAIN_PX, 4):
			for x in range(0, BattleView.TERRAIN_PX, 4):
				var pixel := image.get_pixel(
					column * BattleView.TERRAIN_PX + x, row * BattleView.TERRAIN_PX + y
				)
				total += Color(pixel.r, pixel.g, pixel.b)
				samples += 1
		if samples > 0:
			tint = Color(total.r / samples, total.g / samples, total.b / samples)
	_tint_cache[key] = tint
	return tint
