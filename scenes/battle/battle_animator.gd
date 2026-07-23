class_name BattleAnimator
extends RefCounted
## Plays the battle scene's animations: unit movement, the combat exchange,
## the turn banner, camera shake, and the cursor pulse, with the sound effects
## that go with them.
##
## Every method here animates something that has *already* been decided. The
## animator never chooses a gameplay outcome, applies a command, or reads a
## rule — it is handed a result and shows it. Its awaitable methods let Battle
## hold the interaction flow still until an animation finishes.
##
## Depends on BattleView to find sprites; never on Battle. Tweens need a Node
## to live on, so the scene root is passed in as a plain Node.
##
## Every duration it waits is a GameSpeed tier's, asked of `Settings` at the
## moment the animation starts rather than cached at scene load, so a speed
## changed mid-match lands on the very next move. The sprite it hands durations
## to derives nothing, and BattleAiRunner paces its turn off the same answer. No
## literal seconds below: a tween timed by a number written here would ignore the
## player's setting forever.

## The two durations that deliberately do *not* follow the setting: the shake is
## impact feedback and the pulse is idle UI, and neither is gameplay theatre.
## Named rather than written inline so the exception is visibly meant, and so
## "no bare seconds in a battle tween" stays a grep anyone can run.
const SHAKE_STEP_SECONDS := 0.04
const CURSOR_PULSE_SECONDS := 0.4
## Two cut-ins closer together than this are treated as one run of fighting, and
## each one after the first is tightened (plan BA4, risk R1). Comfortably longer
## than BattleAiRunner.COMMAND_DELAY, which is what makes a computer's turn
## qualify; a human picks a unit, moves it and opens a menu between attacks, so
## an ordinary player's turn never does.
const CUT_IN_STREAK_GAP_MS := 1600
## How far the tightening goes: full ceremony at the start of a run, and by the
## fourth attack in a row a cut-in that plays a third faster with most of its
## closing hold gone. The volley and the impact keep their length throughout.
const CUT_IN_MAX_STREAK := 4
const CUT_IN_STREAK_SPEED := 0.11
const CUT_IN_STREAK_TAIL := 0.22
## The board's flinch as the frame is taken over: a short zoom toward the cell
## that is about to be struck. The cursor is already parked there by both call
## sites, and the camera follows the cursor, so there is nothing to pan.
const PUNCH_ZOOM := 1.14
const PUNCH_SECONDS := 0.11

## Assigned by Battle before first use, like BattleView's nodes.
var node: Node
var view: BattleView
var camera: Camera2D
var cursor: Sprite2D
var turn_banner: PanelContainer
var banner_label: Label
var power_banner: CommanderPowerBanner
## The full-screen battle cut-in. Every resolved attack goes through it when the
## player has it on and both sides are visible; see `animate_combat`.
var cutscene: CombatCutscene
## True for a run that exists to be photographed. Suppresses the two open-ended
## animations — see `shake_camera` and `start_cursor_pulse` — and the cut-in.
var capturing := false

var _banner_tween: Tween
var _power_banner_tween: Tween
## When the last cut-in ended, and how many have run back to back since the
## fighting started. Held as elapsed time rather than as a per-turn counter
## somebody has to remember to reset: there is no lifecycle to get wrong, and a
## fast pace cannot leak out of a computer's turn into the player's next one.
var _last_cut_in_ms := -CUT_IN_STREAK_GAP_MS
var _cut_in_streak := 0

# --- movement ----------------------------------------------------------------


## Tweens a sprite along a path without touching the sim. Awaitable.
##
## Instant sets the destination and returns in the same frame — a path the flow
## already walks, since a one-cell "move" has always returned without a tween.
func animate_path(sprite: UnitSprite, path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	Sfx.play(&"move", -6.0)
	var tier := Settings.speed
	if tier.instant:
		sprite.position = BattleView.cell_center(path[path.size() - 1])
		return
	var tween := node.create_tween()
	for i in range(1, path.size()):
		var step := BattleView.cell_center(path[i])
		tween.tween_property(sprite, "position", step, tier.move_step_seconds())
	await tween.finished


# --- combat ------------------------------------------------------------------


## Plays out one already-resolved exchange: the hit, the shake, whichever side
## died, and the counter. Awaitable, so the flow resumes once the dust settles.
##
## Two bodies, one contract. With battle animations on, the exchange plays as the
## full-screen cut-in and the map is brought back into step underneath; with them
## off — or while capturing, when the viewer cannot see both combatants, or at the
## Instant tier where there is nothing to watch — the on-map version below runs,
## byte-for-byte as it always did. Either way this returns exactly once, which is
## what both call sites hold their flow on.
##
## Under Instant that on-map flash, fade and shake all fall away but the sounds
## stay: an attack the player triggered has to register even when there is
## nothing to see.
func animate_combat(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	var defender_sprite := view.sprite_for(defender)
	var attacker_sprite := view.sprite_for(attacker)
	view.refresh_sprite(attacker)  # snap to the committed destination
	if _cut_in_applies(attacker, defender):
		_pace_cut_in()
		var resting := camera.zoom
		await _punch_camera()
		await cutscene.play(result, attacker, defender, camera, resting)
		camera.zoom = resting  # safety net: the cut-in already eased it home on the wipe
		_last_cut_in_ms = Time.get_ticks_msec()
		_sync_aftermath()
		return
	Sfx.play(&"shot")
	await flash_hit(defender_sprite)
	shake_camera()
	if result.defender_died:
		Sfx.play(&"explosion")
		view.release_sprite(defender)
		await fade_out(defender_sprite)
	else:
		view.refresh_sprite(defender)
	if result.countered:
		Sfx.play(&"shot")
		await flash_hit(attacker_sprite)
	if result.attacker_died:
		view.release_sprite(attacker)
		await fade_out(attacker_sprite)
	else:
		view.refresh_sprite(attacker)
	view.sync_sprites()


## The white hit flash, at the active tier's pace. Awaitable.
func flash_hit(sprite: UnitSprite) -> void:
	var tier := Settings.speed
	await sprite.flash_hit(tier.flash_in_seconds(), tier.flash_out_seconds())


## Fades a sprite out and frees it, at the active tier's pace. Awaitable, and
## the single place a death fade's length is decided — Battle's Join merge fades
## a sprite outside combat entirely and comes through here for that reason.
func fade_out(sprite: UnitSprite) -> void:
	await sprite.die(Settings.speed.death_fade_seconds())


## Whether this exchange gets the cut-in.
##
## The visibility half is the point of the gate: under fog an exchange the
## viewer cannot see would otherwise parade two hidden units across the screen,
## so it stays on the map path, which already draws fogged units correctly. The
## question goes to the view, which asks `Vision` — no second opinion on who can
## see what lives here (plan R6).
##
## Instant is out too: that tier exists to skip the theatre, so a full-screen
## cut-in playing on its own clock would defeat it — the exchange stays on the
## map path, which under Instant collapses to just the sounds.
func _cut_in_applies(attacker: Unit, defender: Unit) -> bool:
	if cutscene == null or capturing or not Settings.battle_animations:
		return false
	if Settings.speed.instant:
		return false
	return view.can_see_unit(attacker) and view.can_see_unit(defender)


## Sets how much ceremony this cut-in gets, from how long it has been since the
## last one (plan BA4). Two seconds a battle is charming for ten battles and a
## chore for two hundred — R1, the plan's own named risk — and a computer turn
## that opens fire five times is exactly where that bites. So a run of attacks
## tightens as it goes: faster overall, and most of the closing hold cut away.
##
## What is *not* touched is the volley, the impact and the HP tick. Those carry
## the information; trimming them would make the cut-in shorter and worse, which
## is the wrong trade at any speed.
func _pace_cut_in() -> void:
	var gap := Time.get_ticks_msec() - _last_cut_in_ms
	_cut_in_streak = (
		mini(_cut_in_streak + 1, CUT_IN_MAX_STREAK) if gap < CUT_IN_STREAK_GAP_MS else 0
	)
	cutscene.speed = 1.0 + _cut_in_streak * CUT_IN_STREAK_SPEED
	cutscene.tail_scale = maxf(0.0, 1.0 - _cut_in_streak * CUT_IN_STREAK_TAIL)


## A short zoom onto the cell about to be struck, so the board flinches before
## the frame is taken away from it. Awaited, then left punched in: the cut-in
## covers the map for its whole run and, handed the camera and this resting zoom,
## eases it home over the closing wipe so the board is already at rest the moment
## it is uncovered — see CombatCutscene._restore_zoom.
func _punch_camera() -> void:
	var tween := node.create_tween()
	(
		tween
		. tween_property(camera, "zoom", camera.zoom * PUNCH_ZOOM, PUNCH_SECONDS)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## The map beats the cut-in stands in for. Both sides have already been shown
## dying on screen, so there is no fade left to play: this only brings the board
## back into step with a sim that has moved on — dropping the sprites of units
## the exchange removed (cargo that went down with a transport included) and
## redrawing the survivors.
func _sync_aftermath() -> void:
	view.sync_sprites()


# --- banner ------------------------------------------------------------------


## Shows the banner immediately and cancels any pending auto-hide.
func _set_banner(text: String) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner_label.text = text
	turn_banner.show()
	turn_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func show_banner(text: String) -> void:
	_set_banner(text)
	_banner_tween = node.create_tween()
	_banner_tween.tween_interval(Settings.speed.banner_seconds())
	_banner_tween.tween_callback(turn_banner.hide)


## Dismisses the banner now, cancelling any pending auto-hide.
func hide_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	turn_banner.hide()


## The Command Power activation card: portrait, power name, and exact effect text,
## faction-tinted. Shown when a power fires (player or AI, both through Battle's
## _announce_power) and auto-hidden after a beat. While capturing it holds, so a
## screenshot of the same activation is the same frame — the whole reason the two
## open-ended animations above are suppressed for captures.
func show_power_banner(commander: CommanderType) -> void:
	if _power_banner_tween != null and _power_banner_tween.is_valid():
		_power_banner_tween.kill()
	power_banner.bind(commander)
	power_banner.show()
	power_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if capturing:
		return
	_power_banner_tween = node.create_tween()
	_power_banner_tween.tween_interval(Settings.speed.power_banner_seconds())
	_power_banner_tween.tween_callback(power_banner.hide)


# --- camera and cursor -------------------------------------------------------


## Brief camera jitter on combat hits. Presentation-only randomness: this
## must never touch game.rng, which is reserved for deterministic sim luck.
##
## Skipped while capturing: the shake is still mid-tween when a frame is taken,
## so it offsets the whole board by a few pixels and makes two otherwise
## identical captures differ everywhere — noise that would hide a real
## rendering regression.
##
## Skipped under Instant too, which is the one tier where it is theatre rather
## than feedback: there is no hit animation left for it to punctuate.
func shake_camera(strength: float = 3.0) -> void:
	if capturing or Settings.speed.instant:
		return
	var tween := node.create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, SHAKE_STEP_SECONDS)
	tween.tween_property(camera, "offset", Vector2.ZERO, SHAKE_STEP_SECONDS)


## Skipped while capturing, for the same reason as `shake_camera`: a loop has
## no settled state, so every frame catches it at a different phase.
func start_cursor_pulse() -> void:
	if capturing:
		return
	var tween := node.create_tween().set_loops()
	(
		tween
		. tween_property(cursor, "scale", Vector2(1.15, 1.15), CURSOR_PULSE_SECONDS)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween
		. tween_property(cursor, "scale", Vector2.ONE, CURSOR_PULSE_SECONDS)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
