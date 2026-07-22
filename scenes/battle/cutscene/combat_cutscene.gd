class_name CombatCutscene
extends CanvasLayer
## The battle cut-in: when an attack resolves, the board gives way to a
## full-screen versus frame — attacker on the left, defender on the right, each
## posed over its own terrain — the volley crosses, HP ticks down, the counter
## comes back, and the map returns.
##
## It replays; it never decides (plan D1). Every beat below is driven by a field
## of the CombatResolver.CombatResult it is handed, including the two HP
## snapshots that exist for exactly this — by the time the cut-in runs, the
## command has applied and both units hold post-combat HP. Nothing here touches
## the damage chart, the RNG, or a rule.
##
## One clock, one exit. `_t` advances in `_process` and every visual is a pure
## function of it, so skipping is `_t = _total` rather than a race between
## cancelled tweens — the awaitable `play()` resolves exactly once, whatever the
## player presses (plan R2). The randomness in the shake is a function of `_t`
## too, so a posed frame is the same frame every run (R4).
##
## Owned by Battle, which assigns `view` and hands it to the animator — the same
## assignment-not-constructor shape BattleView and BattleAnimator use, so the
## cut-in never learns what a Battle is either.

## Emitted once per cut-in, when the wipe has cleared and control belongs to the
## caller again. Every branch funnels through `_finish`, which is the only place
## that emits it.
signal finished

## Beat budgets, in seconds. A clean kill runs ~1.8 s and a full exchange with a
## counter ~2.3 s, which is the tempo the plan's beat sheet asks for: long enough
## to read, short enough to sit through two hundred times.
const WIPE_IN := 0.20
const PLATES := 0.22
const ANTICIPATION := 0.16
const TRAVEL := 0.29
const IMPACT := 0.40
const DEATH := 0.35
const HOLD := 0.25
const WIPE_OUT := 0.20

## Letterbox bar height, as a share of the viewport.
const BAR_RATIO := 0.13
const DIM_ALPHA := 0.62
## How far each half slides in from its own edge.
const SLIDE_PX := 60.0
## Push-in over the exchange, and the shake an impact adds.
const PUSH_SCALE := 0.03
const SHAKE_PX := 5.0


## The windows every beat is read out of, in seconds from the wipe. A window of
## zero length is a beat this exchange does not have — an unanswered volley has
## no counter, a survivor has no death.
class Beats:
	var atk_ready := Vector2.ZERO
	var atk_fire := 0.0
	var atk_travel := Vector2.ZERO
	var def_impact := Vector2.ZERO
	var def_death := Vector2.ZERO
	var ctr_ready := Vector2.ZERO
	var def_fire := 0.0
	var def_travel := Vector2.ZERO
	var atk_impact := Vector2.ZERO
	var atk_death := Vector2.ZERO
	var wipe_out := Vector2.ZERO
	var total := 0.0


## The board the exchange is fought on. Assigned by Battle before first use. The
## cut-in reads exactly two things off it — the terrain each side stands on and
## who owns that cell — which is what dresses each half's ground strip.
var view: BattleView
## Playback rate. BA4's AI pacing nudges this above 1.0 for a side that is
## attacking repeatedly; a player's own attacks always run at 1.0.
var speed := 1.0

var _root: Control
var _dim: ColorRect
var _band: Control
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _atk: CutsceneSide
var _def: CutsceneSide
var _fx: CutsceneFx
## Viewport size and letterbox height, refreshed by `_layout` so the per-frame
## work never re-measures anything.
var _view := Vector2(640.0, 360.0)
var _bar_h := 46.0

var _playing := false
var _skipping := false
var _t := 0.0
var _beats := Beats.new()
var _result: CombatResolver.CombatResult
var _atk_hp_after := 0
var _def_hp_after := 0
## The two weapon signatures this exchange fires with. Read from data, never
## decided here — see BattleStyle.
var _styles := BattleStyleDB.new()
var _atk_style: BattleStyle
var _def_style: BattleStyle
## Cue name -> true once its sound has played, so a beat crossed twice by a
## frame boundary is still heard once and a skip is silent rather than a pile-up.
var _cues: Dictionary = {}


func _ready() -> void:
	_build()
	_styles = BattleStyleDB.load_default()
	_root.hide()
	set_process(false)


# --- playing -----------------------------------------------------------------


## Plays one already-resolved exchange and returns when the map is back.
## Awaitable: both call sites hold the interaction flow on it.
func play(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	_pose(result, attacker, defender)
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
## capture (plan D6). No clock runs, no sound plays, and `finished` is never
## emitted — this is a still, not a playthrough, which is exactly what makes it
## byte-stable: every value on screen is a function of the `at` handed in.
##
## Dev-only. The scenario driver is the one caller; play never poses.
func pose_at(
	result: CombatResolver.CombatResult, attacker: Unit, defender: Unit, at: float
) -> void:
	_pose(result, attacker, defender)
	_t = clampf(at, 0.0, _beats.total)
	_layout()
	_apply()
	_root.show()


## Fast-forwards every remaining beat to its end state. Never aborts: the clock
## is simply set to the end, the final tableau is applied, and the same exit runs
## — which is what makes a skip at any beat land on the right board.
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


## Poses both halves and works out the beat windows this exchange has.
func _pose(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	_result = result
	_atk_hp_after = attacker.displayed_hp()
	_def_hp_after = defender.displayed_hp()
	_atk_style = _styles.for_unit(attacker.type)
	_def_style = _styles.for_unit(defender.type)
	_atk.bind(attacker, _terrain_at(attacker.cell), view.game.owner_at(attacker.cell), false)
	_def.bind(defender, _terrain_at(defender.cell), view.game.owner_at(defender.cell), true)
	_atk.hp_shown = result.attacker_hp_before
	_def.hp_shown = result.defender_hp_before
	_squads(_atk, result.attacker_hp_before, _atk_hp_after, result.attacker_died)
	_squads(_def, result.defender_hp_before, _def_hp_after, result.defender_died)
	_beats = _plan(result, TRAVEL * _atk_style.travel_scale, TRAVEL * _def_style.travel_scale)


## How many figures a side posts and how many it keeps. A side that dies keeps
## all of them: the blast is what takes it, and toppling them first would leave
## the explosion going off over an empty patch of ground.
static func _squads(side: CutsceneSide, before: int, after: int, died: bool) -> void:
	side.squad_was = CutsceneSide.figures_for(before)
	side.squad_now = side.squad_was if died else CutsceneSide.figures_for(after)


## The cell's terrain. An attacker fires from the cell it has already been moved
## to — the command applied before the animator was called — so this is the
## ground the shot was actually taken from, not the one it started the turn on.
func _terrain_at(cell: Vector2i) -> TerrainType:
	return view.map.terrain_at(cell)


## The beat sheet, laid out on the clock. Reads only the result's flags, so an
## exchange with no counter is genuinely shorter rather than padded with a pause.
## The two travel budgets come from the firing styles — an arcing shell is given
## longer to get there than a burst of tracer.
static func _plan(
	result: CombatResolver.CombatResult, atk_travel: float, def_travel: float
) -> Beats:
	var beats := Beats.new()
	beats.atk_ready = Vector2(WIPE_IN, WIPE_IN + ANTICIPATION)
	beats.atk_fire = beats.atk_ready.y
	beats.atk_travel = Vector2(beats.atk_fire, beats.atk_fire + atk_travel)
	beats.def_impact = Vector2(beats.atk_travel.y - 0.02, beats.atk_travel.y - 0.02 + IMPACT)
	var settled := beats.def_impact.y
	if result.defender_died:
		beats.def_death = Vector2(settled - 0.05, settled - 0.05 + DEATH)
		settled = beats.def_death.y
	elif result.countered:
		beats.ctr_ready = Vector2(settled, settled + ANTICIPATION)
		beats.def_fire = beats.ctr_ready.y
		beats.def_travel = Vector2(beats.def_fire, beats.def_fire + def_travel)
		beats.atk_impact = Vector2(beats.def_travel.y - 0.02, beats.def_travel.y - 0.02 + IMPACT)
		settled = beats.atk_impact.y
		if result.attacker_died:
			beats.atk_death = Vector2(settled - 0.05, settled - 0.05 + DEATH)
			settled = beats.atk_death.y
	beats.wipe_out = Vector2(settled + HOLD, settled + HOLD + WIPE_OUT)
	beats.total = beats.wipe_out.y
	return beats


# --- the frame ---------------------------------------------------------------


## Everything the cut-in shows, as a pure function of `_t`. Called once per
## frame while playing and once more by `skip`, which is why it may never do
## anything that only makes sense the first time — sounds go through `_cue`.
func _apply() -> void:
	var present := clampf(_window(Vector2(0.0, WIPE_IN)) - _window(_beats.wipe_out), 0.0, 1.0)
	var plates := _window(Vector2(WIPE_IN * 0.5, WIPE_IN * 0.5 + PLATES)) * present
	_dim.color.a = DIM_ALPHA * present
	_frame_bars(present)
	_frame_band(present)

	var atk_ready := _window(_beats.atk_ready)
	var ctr_ready := _window(_beats.ctr_ready)
	var def_hit := _window(_beats.def_impact)
	var atk_hit := _window(_beats.atk_impact)
	var def_gone := _window(_beats.def_death)
	var atk_gone := _window(_beats.atk_death)

	_atk.plate_p = plates
	_atk.lunge = _lunge(atk_ready)
	_atk.flash = maxf(0.0, 1.0 - atk_hit / 0.3) if atk_hit > 0.0 else 0.0
	_atk.hp_shown = _tick(_result.attacker_hp_before, _atk_hp_after, atk_hit)
	_atk.fall_p = _window(_topple(_beats.atk_impact))
	_atk.squad_alpha = 1.0 - atk_gone
	_atk.queue_redraw()

	_def.plate_p = plates
	_def.lunge = _lunge(ctr_ready)
	_def.flash = maxf(0.0, 1.0 - def_hit / 0.3) if def_hit > 0.0 else 0.0
	_def.hp_shown = _tick(_result.defender_hp_before, _def_hp_after, def_hit)
	_def.fall_p = _window(_topple(_beats.def_impact))
	_def.squad_alpha = 1.0 - def_gone
	_def.queue_redraw()

	_frame_fx(present)
	_sound()


func _frame_bars(present: float) -> void:
	var bar := _bar_h * present
	_top_bar.size = Vector2(_view.x, bar)
	_bottom_bar.position = Vector2(0.0, _view.y - bar)
	_bottom_bar.size = Vector2(_view.x, bar)


## The two halves slide in from their own edges, and the whole band pushes in
## slightly over the exchange with a decaying shake on every impact.
func _frame_band(present: float) -> void:
	var half := _band.size.x * 0.5
	_atk.position = Vector2(-SLIDE_PX * (1.0 - present), 0.0)
	_def.position = Vector2(half + SLIDE_PX * (1.0 - present), 0.0)
	_atk.modulate.a = present
	_def.modulate.a = present
	var push := 1.0 + PUSH_SCALE * _window(Vector2(WIPE_IN, WIPE_IN + 0.3)) * present
	_band.scale = Vector2(push, push)
	var jolt := (
		_decay(_window(_beats.def_impact))
		+ _decay(_window(_beats.atk_impact))
		+ _decay(_window(_beats.def_death))
		+ _decay(_window(_beats.atk_death))
	)
	_band.position = Vector2(
		sin(_t * 91.0) * jolt * SHAKE_PX, _bar_h + cos(_t * 77.0) * jolt * SHAKE_PX
	)


## Which side is firing, what it is firing, and where the blast goes off. Only
## one volley is ever in the air: the counter cannot start until the first has
## landed, which is the beat sheet's shape, not a rule enforced here.
func _frame_fx(present: float) -> void:
	var outgoing := _window(_beats.atk_travel)
	var returning := _window(_beats.def_travel)
	_fx.volley_p = 0.0
	_fx.volley_style = null
	if outgoing > 0.0 and outgoing < 1.0:
		_aim(_atk, _def, outgoing, _atk_style)
	elif returning > 0.0 and returning < 1.0:
		_aim(_def, _atk, returning, _def_style)
	_fx.muzzles = PackedVector2Array()
	_fx.muzzle_radius = 0.0
	if _flashing(_beats.atk_fire) and _atk_style.fires():
		_flash_barrels(_atk, _atk_style)
	elif _flashing(_beats.def_fire) and _def_style.fires():
		_flash_barrels(_def, _def_style)
	var def_gone := _window(_beats.def_death)
	_fx.blast_p = def_gone if def_gone > 0.0 else _window(_beats.atk_death)
	_fx.blast_at = (
		_def.position + _def.center_point()
		if def_gone > 0.0
		else (_atk.position + _atk.center_point())
	)
	_fx.vs_alpha = present * (1.0 - clampf(_t / maxf(_beats.atk_fire, 0.01), 0.0, 1.0))
	_fx.def_amount = _result.defender_hp_before - _def_hp_after
	_fx.def_tag = CutsceneFx.KO_TAG if _result.defender_died else ""
	_fx.def_p = _window(_callout(_beats.def_impact, _beats.def_death))
	_fx.def_at = _head_of(_def)
	_fx.atk_amount = _result.attacker_hp_before - _atk_hp_after
	_fx.atk_tag = CutsceneFx.KO_TAG if _result.attacker_died else ""
	_fx.atk_p = _window(_callout(_beats.atk_impact, _beats.atk_death))
	_fx.atk_at = _head_of(_atk)
	_fx.modulate.a = present
	_fx.queue_redraw()


## Points the volley from the front rank of one squad at the middle of the
## other's, so a burst converges on what it is shooting at rather than at one
## figure of it.
func _aim(from: CutsceneSide, at: CutsceneSide, progress: float, style: BattleStyle) -> void:
	var barrels := from.muzzle_points()
	var origin := (
		from.position + barrels[barrels.size() - 1]
		if not barrels.is_empty()
		else from.position + from.center_point()
	)
	_fx.volley_p = progress
	_fx.volley_style = style
	_fx.volley_figures = maxi(barrels.size(), 1)
	_fx.volley_from = origin
	_fx.volley_to = at.position + at.center_point()


## Lights every standing figure's barrel on the firing side.
func _flash_barrels(side: CutsceneSide, style: BattleStyle) -> void:
	var points := PackedVector2Array()
	for at in side.muzzle_points():
		points.append(side.position + at)
	_fx.muzzles = points
	_fx.muzzle_radius = style.muzzle


## Fires the shot and explosion sounds as their beats come up. Silent during a
## fast-forward — skipping past four beats should not play four sounds at once —
## and silent for a posed still, which has no beats to cross.
func _sound() -> void:
	if not _playing:
		return
	if _atk_style.fires():
		_cue(&"atk_fire", _beats.atk_fire, _atk_style.sfx)
	if _def_style.fires():
		_cue(&"def_fire", _beats.def_fire, _def_style.sfx)
	_cue(&"def_death", _beats.def_death.x, &"explosion")
	_cue(&"atk_death", _beats.atk_death.x, &"explosion")


func _cue(key: StringName, at: float, sfx: StringName) -> void:
	if at <= 0.0 or _cues.has(key) or _t < at:
		return
	_cues[key] = true
	if not _skipping:
		Sfx.play(sfx)


# --- curves ------------------------------------------------------------------


## Where `_t` sits inside a beat window, 0 -> 1. A zero-length window — a beat
## this exchange does not have — is always 0, which is what switches its whole
## branch of the frame off.
func _window(span: Vector2) -> float:
	if span.y <= span.x:
		return 0.0
	return clampf((_t - span.x) / (span.y - span.x), 0.0, 1.0)


## The window surplus figures topple over: it opens just after the round lands
## and closes with the impact, leaving room for the per-figure stagger.
static func _topple(impact: Vector2) -> Vector2:
	if impact.y <= impact.x:
		return Vector2.ZERO
	return Vector2(impact.x + 0.06, impact.y + 0.1)


## The window a damage callout is shown over: it outlives the impact, and a
## death holds it until the explosion has finished.
static func _callout(impact: Vector2, death: Vector2) -> Vector2:
	if impact.y <= impact.x:
		return Vector2.ZERO
	var end := (death.y if death.y > death.x else impact.y) + 0.3
	return Vector2(impact.x + 0.08, end)


## Pull back, then thrust, then settle — the recoil every volley opens with.
static func _lunge(ready: float) -> float:
	if ready <= 0.0:
		return 0.0
	return CutsceneFx.ramp(ready, [0.0, 0.4, 0.7, 1.0], [0.0, -7.0, 13.0, 5.0])


## HP holds for the first third of the impact, then runs down to the number the
## sim already committed. Rounded to whole displayed HP so the pips and the
## squad can never disagree about how many are left.
static func _tick(before: int, after: int, progress: float) -> int:
	if progress <= 0.0:
		return before
	return roundi(lerpf(before, after, clampf((progress - 0.35) / 0.65, 0.0, 1.0)))


## A jolt that is strongest as its window opens and gone a third of the way in.
static func _decay(progress: float) -> float:
	if progress <= 0.0 or progress >= 1.0:
		return 0.0
	return maxf(0.0, 1.0 - progress / 0.35)


## True for the few frames a barrel is alight after `at`.
func _flashing(at: float) -> bool:
	return at > 0.0 and _t >= at and _t < at + 0.09


## Just above a side's squad, in the overlay's coordinates — where that side's
## damage callout is anchored. Taken from the middle of a *full* squad, so the
## number does not drift sideways as figures fall out from under it.
static func _head_of(side: CutsceneSide) -> Vector2:
	return side.position + side.center_point() + Vector2(0.0, -56.0)


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
	_atk = CutsceneSide.new()
	_def = CutsceneSide.new()
	_fx = CutsceneFx.new()
	_band.add_child(_atk)
	_band.add_child(_def)
	_band.add_child(_fx)
	_top_bar = _new_bar()
	_bottom_bar = _new_bar()
	_root.resized.connect(_layout)


func _new_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.055, 0.063, 0.078)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	return bar


## Sizes the band and its halves off the viewport rather than off constants, so
## the cut-in still frames correctly if the base resolution ever changes.
func _layout() -> void:
	_view = _root.get_viewport_rect().size
	_bar_h = roundf(_view.y * BAR_RATIO)
	var band := Vector2(_view.x, _view.y - _bar_h * 2.0)
	_dim.position = Vector2.ZERO
	_dim.size = _view
	_band.position = Vector2(0.0, _bar_h)
	_band.size = band
	_band.pivot_offset = band * 0.5
	_atk.size = Vector2(band.x * 0.5, band.y)
	_def.size = _atk.size
	_fx.position = Vector2.ZERO
	_fx.size = band
	_top_bar.position = Vector2.ZERO
	_bottom_bar.position = Vector2(0.0, _view.y - _bar_h)
