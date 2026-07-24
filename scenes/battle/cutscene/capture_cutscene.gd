class_name CaptureCutscene
extends CanvasLayer
## The capture cut-in: when an infantry squad takes a property, the board gives
## way to a single-panel frame — the squad marches up, mashes the building down
## over one to three hops as a points meter drains, and on completion the
## property flashes white and flips to the capturing faction's colours under a
## CAPTURED! banner — then the map returns.
##
## The sibling of CombatCutscene, and it replays; it never decides (plan D1).
## Every beat is driven by the CaptureCommand.CaptureResult it is handed — the
## two point totals and whether ownership flipped. The chips the mashes knock off
## are a presentation split of that committed delta (`points_before -
## points_after`), never a call back into `capture_strength`, so a press
## mid-mash lands on the same number the terrain panel reports.
##
## One clock, one exit. `_t` advances in `_process` and every visual is a pure
## function of it, so skipping is `_t = _total` rather than a race between
## cancelled tweens — the awaitable `play()` resolves exactly once, whatever the
## player presses (plan R2). Owned by Battle, which assigns `view` and hands it
## to the animator — the same assignment-not-constructor shape the rest use.

## Emitted once per cut-in, when the wipe has cleared and control belongs to the
## caller again. Every branch funnels through `_finish`, the only place it emits.
signal finished

## Beat budgets, in seconds. A completing capture runs ~2.4 s and a partial ~2.0
## — the tempo the plan's beat sheet asks for, and deliberately faster than the
## design handoff's 4.6 s reference, because captures are the most frequent
## ceremony in the game (plan R1). Fixed constants scaled by the streak pacing the
## animator sets, exactly as CombatCutscene's are — the two cut-ins keep one clock
## shape, and neither reads GameSpeed for its beat lengths.
const WIPE_IN := 0.22
const PLATES := 0.22
const MARCH := 0.34
const HOP_DUR := 0.24
const HOP_GAP := 0.03
const HOP_HEIGHT := 46.0
const FLIP := 0.30
const BANNER := 0.55
const HOLD := 0.20
const WIPE_OUT := 0.20
const MIN_WIPE_SCALE := 0.4
## At most three mashes, however many points came off — a strength-12 doctrine
## turn still reads as three hops, not twelve.
const MAX_HOPS := 3

const BAR_RATIO := 0.13
const DIM_ALPHA := 0.62
const PUSH_SCALE := 0.03
const SHAKE_PX := 5.0
const ACCENT_PX := 2.0


## The beat windows this capture has, laid out on the clock. A completing capture
## has a flip; a partial does not, and its banner opens where the flip would have.
class Beats:
	var plates := Vector2.ZERO
	var march := Vector2.ZERO
	var hops: Array[Vector2] = []
	var lands := PackedFloat32Array()
	var flip := Vector2.ZERO
	var banner := Vector2.ZERO
	var wipe_out := Vector2.ZERO
	var total := 0.0


## The board the capture is taken on. Assigned by Battle before first use. The
## cut-in reads the property's terrain and the two atlas rows off it — the owner's
## and the capturer's — which is what dresses the panel and drives the flip.
var view: BattleView
## Playback rate and how much of the closing hold/wipe is kept — the AI-pacing
## levers (plan CP3), set by the animator's shared streak state so a turn mixing
## attacks and captures tightens as one run.
var speed := 1.0
var tail_scale := 1.0

var _root: Control
var _dim: ColorRect
var _band: Control
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _top_edge: ColorRect
var _bottom_edge: ColorRect
var _stage: CaptureStage
var _hud: CaptureHud
var _view := Vector2(640.0, 360.0)
var _bar_h := 46.0

var _camera: Camera2D
var _resting_zoom := Vector2.ONE
var _punched_zoom := Vector2.ONE

var _playing := false
var _skipping := false
var _t := 0.0
var _beats := Beats.new()
var _result: CaptureCommand.CaptureResult
var _unit: Unit
var _cell := Vector2i.ZERO
var _accent := Color.WHITE
## The point chips each mash knocks off, largest first, summing to the meter's
## drop. Computed once in `_pose`.
var _chips := PackedInt32Array()
## Cue name -> true once its sound has played, so a beat crossed twice by a frame
## boundary is heard once and a skip is silent rather than a pile-up.
var _cues: Dictionary = {}


func _ready() -> void:
	_build()
	_root.hide()
	set_process(false)


# --- playing -----------------------------------------------------------------


## Plays one already-applied capture and returns when the map is back. Awaitable:
## both call sites hold the interaction flow on it. The animator hands over the
## punched-in camera and the zoom to return it to; left null (as the scenario
## driver leaves it) the camera is untouched.
func play(
	result: CaptureCommand.CaptureResult,
	unit: Unit,
	cell: Vector2i,
	camera: Camera2D = null,
	resting_zoom := Vector2.ONE
) -> void:
	_pose(result, unit, cell)
	_camera = camera
	_resting_zoom = resting_zoom
	_punched_zoom = camera.zoom if camera != null else resting_zoom
	_t = 0.0
	_playing = true
	_skipping = false
	_cues.clear()
	_layout()
	_apply()
	_root.show()
	set_process(true)
	set_process_unhandled_input(true)
	await finished


## Freezes the cut-in at one moment of its own clock and leaves it there, for a
## screenshot (plan D3). No clock runs, no sound plays, and `finished` is never
## emitted — a still, not a playthrough, which is what makes it byte-stable.
## Dev-only; play never poses.
func pose_at(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i, at: float) -> void:
	_pose(result, unit, cell)
	_camera = null
	_t = clampf(at, 0.0, _beats.total)
	_layout()
	_apply()
	_root.show()


## Fast-forwards every remaining beat to its end state. Never aborts: the clock is
## set to the end, the final tableau is applied, and the same exit runs — which is
## what makes a skip at any beat land on the right board.
func skip() -> void:
	if not _playing:
		return
	_skipping = true
	_t = _beats.total


func _process(delta: float) -> void:
	if not _playing:
		return
	_t = minf(_t + delta * speed, _beats.total)
	_apply()
	if _t >= _beats.total:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	var pressed := (
		event.is_action_pressed(&"confirm")
		or event.is_action_pressed(&"cancel")
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if pressed:
		skip()
		get_viewport().set_input_as_handled()


## The single exit. Every branch reaches it, and it emits once.
func _finish() -> void:
	if not _playing:
		return
	_playing = false
	set_process(false)
	set_process_unhandled_input(false)
	_root.hide()
	finished.emit()


# --- staging -----------------------------------------------------------------


## Poses the stage and hud and works out the beat windows this capture has.
func _pose(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_result = result
	_unit = unit
	_cell = cell
	var terrain := view.map.terrain_at(cell)
	_accent = _accent_of(unit.team)
	var row_before := view.identity.atlas_row(result.owner_before)
	var row_after := view.identity.atlas_row(unit.team)
	_stage.bind(unit, terrain, terrain.atlas_col, row_before, row_after)
	var removed := maxi(result.points_before - result.points_after, 0)
	var hops := clampi(removed, 1, MAX_HOPS)
	_chips = _split(removed, hops)
	_beats = _plan(result.captured, hops, clampf(tail_scale, 0.0, 1.0))


## A side's faction accent: the capturing commander's colour, or — capturing
## without one — the classic its slot falls back to. CommanderVisuals is the
## single authority on what a faction looks like; a commander-less side's colour
## is SideIdentity's, the same red/blue the board resolves it to.
func _accent_of(team: int) -> Color:
	var commander := view.game.commander_of(team)
	if commander != null and commander.id != CommanderType.NEUTRAL_ID:
		return CommanderVisuals.theme_for(commander).color_light
	return view.identity.theme(team).color_light


## Splits the points removed across the mashes, largest first, so the chips sum
## to the meter's committed drop: 10 over 3 hops is 4/3/3, a doctrine's 12 is
## 4/4/4, a finishing 1 is a single hop of 1.
static func _split(removed: int, hops: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := removed / hops
	var extra := removed % hops
	for i in hops:
		out.append(base + (1 if i < extra else 0))
	return out


## The beat sheet, laid out on the clock. `tail` trims the closing hold and wipe,
## the only part the pacing is allowed to take — the mashes and the flip keep
## their length, because those carry what the cut-in is for.
static func _plan(captured: bool, hops: int, tail: float) -> Beats:
	var beats := Beats.new()
	beats.plates = Vector2(WIPE_IN * 0.5, WIPE_IN * 0.5 + PLATES)
	beats.march = Vector2(WIPE_IN, WIPE_IN + MARCH)
	var t := beats.march.y
	for i in hops:
		var start := t + i * (HOP_DUR + HOP_GAP)
		beats.hops.append(Vector2(start, start + HOP_DUR))
		beats.lands.append(start + HOP_DUR)
	var settled: float = beats.lands[beats.lands.size() - 1]
	var banner_start := settled + 0.05
	if captured:
		beats.flip = Vector2(settled + 0.05, settled + 0.05 + FLIP)
		banner_start = beats.flip.x + FLIP * 0.4
	beats.banner = Vector2(banner_start, banner_start + BANNER)
	var hold := beats.banner.y + HOLD * tail
	beats.wipe_out = Vector2(hold, hold + WIPE_OUT * maxf(tail, MIN_WIPE_SCALE))
	beats.total = beats.wipe_out.y
	return beats


# --- the frame ---------------------------------------------------------------


## Everything the cut-in shows, as a pure function of `_t`. Called once per frame
## while playing and once by `skip`, so it may never do anything that only makes
## sense the first time — sounds go through `_cue`.
func _apply() -> void:
	var present := clampf(_window(Vector2(0.0, WIPE_IN)) - _window(_beats.wipe_out), 0.0, 1.0)
	var plates := _window(_beats.plates) * present
	_dim.color.a = DIM_ALPHA * present
	_restore_zoom()
	_frame_bars(present)
	_frame_band(present)

	# The meter reading and the chips: a split of the committed delta, applied as
	# each mash lands.
	var shown := _result.points_before
	var flip_p := _window(_beats.flip) if _result.captured else 0.0
	var flash := sin(flip_p * PI) if (flip_p > 0.0 and flip_p < 1.0) else 0.0
	var squash := 0.0
	var hop_advance := 0.0
	var chip_p := PackedFloat32Array()
	for i in _beats.hops.size():
		var hp := _window(_beats.hops[i])
		if hp > 0.0:
			hop_advance = (i + minf(hp * 2.0, 1.0)) / float(_beats.hops.size())
		var land: float = _beats.lands[i]
		if _t >= land:
			shown -= _chips[i]
		squash = maxf(squash, sin(clampf((_t - land) / 0.22, 0.0, 1.0) * PI) * 0.12)
		chip_p.append(_window(Vector2(land, land + 0.6)))

	_stage.plate_p = plates
	_stage.march_p = _window(_beats.march)
	_stage.hop_advance = hop_advance
	_stage.squad_y = -sin(_active_hop() * PI) * HOP_HEIGHT
	_stage.squash = squash
	_stage.brightness = flash * 2.0
	_stage.flipped = _result.captured and flip_p >= 0.5
	_stage.dust = _dust_windows()
	_stage.clock = _t
	_stage.modulate.a = present
	_stage.queue_redraw()

	_hud.points_shown = shown
	_hud.meter_p = plates
	_hud.chip_values = _chips
	_hud.chip_p = chip_p
	_hud.chip_at = _prop_head()
	_hud.flash = flash * 0.55
	_hud.specks_p = (
		_window(Vector2(_beats.flip.y - 0.05, _beats.flip.y + 0.8)) if _result.captured else 0.0
	)
	_hud.specks_at = _prop_head() + Vector2(0.0, 20.0)
	_hud.specks_accent = _accent
	_frame_banner()
	_hud.modulate.a = present
	_hud.queue_redraw()

	_sound()


## Where along its arc the one hop in flight sits, 0 while none is.
func _active_hop() -> float:
	for span in _beats.hops:
		var hp := _window(span)
		if hp > 0.0 and hp < 1.0:
			return hp
	return 0.0


## One dust window per hop, opening as it lands.
func _dust_windows() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for land in _beats.lands:
		out.append(_window(Vector2(land, land + 0.5)))
	return out


## The property's head in the band's coordinates — where the chips rise from and
## the specks fan out. Fixed for the whole cut-in so nothing anchored here drifts.
func _prop_head() -> Vector2:
	return Vector2(_band.size.x * CaptureStage.PROP_CENTER, _band.size.y * 0.34)


func _frame_banner() -> void:
	_hud.banner_p = _window(Vector2(_beats.banner.x, _beats.banner.x + 0.3))
	_hud.banner_complete = _result.captured
	if _result.captured:
		_hud.banner_text = "CAPTURED!"
		_hud.banner_sub = ""
	else:
		_hud.banner_text = "OCCUPYING"
		_hud.banner_sub = "%d/20 LEFT" % maxi(_result.points_after, 0)
	if _t < _beats.banner.x or _t >= _beats.banner.y:
		_hud.banner_p = 0.0


## Eases the board camera from its entry punch back to rest over the closing wipe,
## in lockstep with `present` falling to zero — so the map is at its resting zoom
## on the frame the wipe uncovers it, and a skip (which pins the reveal at 1)
## lands the zoom exactly at rest. No-op when no camera was handed over.
func _restore_zoom() -> void:
	if _camera == null:
		return
	var reveal := _window(_beats.wipe_out)
	_camera.zoom = _resting_zoom if reveal >= 1.0 else _punched_zoom.lerp(_resting_zoom, reveal)


func _frame_bars(present: float) -> void:
	var bar := _bar_h * present
	_top_bar.size = Vector2(_view.x, bar)
	_bottom_bar.position = Vector2(0.0, _view.y - bar)
	_bottom_bar.size = Vector2(_view.x, bar)
	var glow := lerpf(1.0, 0.55, present)
	var edge := Color(_accent, present * glow)
	_top_edge.color = edge
	_top_edge.position = Vector2(0.0, bar)
	_top_edge.size = Vector2(_view.x, ACCENT_PX)
	_bottom_edge.color = edge
	_bottom_edge.position = Vector2(0.0, _view.y - bar - ACCENT_PX)
	_bottom_edge.size = Vector2(_view.x, ACCENT_PX)


## The single panel fades in and pushes in slightly, with a decaying shake on
## every landing and the flip flash.
func _frame_band(present: float) -> void:
	var push := 1.0 + PUSH_SCALE * _window(Vector2(WIPE_IN, WIPE_IN + 0.3)) * present
	_band.scale = Vector2(push, push)
	var jolt := 0.0
	for land in _beats.lands:
		jolt += _decay(_window(Vector2(land, land + 0.3)))
	if _result.captured:
		var flip_p := _window(_beats.flip)
		jolt += (sin(flip_p * PI) if (flip_p > 0.0 and flip_p < 1.0) else 0.0) * 0.6
	_band.position = Vector2(
		sin(_t * 90.0) * jolt * SHAKE_PX, _bar_h + cos(_t * 76.0) * jolt * SHAKE_PX
	)


func _sound() -> void:
	if not _playing:
		return
	for i in _beats.lands.size():
		_cue(StringName("mash_%d" % i), _beats.lands[i], &"capture")
	if _result.captured:
		_cue(&"flip", _beats.banner.x, &"fanfare")


func _cue(key: StringName, at: float, sfx: StringName) -> void:
	if at <= 0.0 or _cues.has(key) or _t < at:
		return
	_cues[key] = true
	if not _skipping:
		Sfx.play(sfx)


# --- curves ------------------------------------------------------------------


## Where `_t` sits inside a beat window, 0 -> 1. A zero-length window — a beat
## this capture does not have — is always 0, switching its branch of the frame off.
func _window(span: Vector2) -> float:
	if span.y <= span.x:
		return 0.0
	return clampf((_t - span.x) / (span.y - span.x), 0.0, 1.0)


## A jolt strongest as its window opens and gone a third of the way in.
static func _decay(progress: float) -> float:
	if progress <= 0.0 or progress >= 1.0:
		return 0.0
	return maxf(0.0, 1.0 - progress / 0.35)


# --- nodes -------------------------------------------------------------------


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0.078, 0.086, 0.118, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_band)
	_stage = CaptureStage.new()
	_hud = CaptureHud.new()
	_band.add_child(_stage)
	_band.add_child(_hud)
	_top_bar = _new_bar()
	_bottom_bar = _new_bar()
	_top_edge = _new_bar()
	_bottom_edge = _new_bar()
	_root.resized.connect(_layout)


func _new_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.055, 0.063, 0.078)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	return bar


## Sizes the band and its two draw layers off the viewport, so the cut-in still
## frames correctly if the base resolution ever changes.
func _layout() -> void:
	_view = _root.get_viewport_rect().size
	_bar_h = roundf(_view.y * BAR_RATIO)
	var band := Vector2(_view.x, _view.y - _bar_h * 2.0)
	_dim.position = Vector2.ZERO
	_dim.size = _view
	_band.position = Vector2(0.0, _bar_h)
	_band.size = band
	_band.pivot_offset = band * 0.5
	_stage.position = Vector2.ZERO
	_stage.size = band
	_hud.position = Vector2.ZERO
	_hud.size = band
	_top_bar.position = Vector2.ZERO
	_bottom_bar.position = Vector2(0.0, _view.y - _bar_h)
