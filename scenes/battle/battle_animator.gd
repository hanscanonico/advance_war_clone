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
## Every duration it waits belongs to a GameSpeed tier, and `speed()` is where
## the presentation layer asks which one — the sprite it hands durations to
## derives nothing, and BattleAiRunner paces its turn off the same answer. No
## literal seconds below: a tween timed by a number written here would ignore the
## player's setting forever.

## The two durations that deliberately do *not* follow the setting: the shake is
## impact feedback and the pulse is idle UI, and neither is gameplay theatre.
## Named rather than written inline so the exception is visibly meant, and so
## "no bare seconds in a battle tween" stays a grep anyone can run.
const SHAKE_STEP_SECONDS := 0.04
const CURSOR_PULSE_SECONDS := 0.4

## Assigned by Battle before first use, like BattleView's nodes.
var node: Node
var view: BattleView
var camera: Camera2D
var cursor: Sprite2D
var turn_banner: PanelContainer
var banner_label: Label
var power_banner: CommanderPowerBanner
## True for a run that exists to be photographed. Suppresses the two open-ended
## animations — see `shake_camera` and `start_cursor_pulse`.
var capturing := false
## Set only by a run that pins its own pace and ignores the device preference —
## captures do, because a screenshot must not depend on which machine took it.
var speed_override: GameSpeed

var _banner_tween: Tween
var _power_banner_tween: Tween

# --- pacing ------------------------------------------------------------------


## The tier every duration here is read from. Asked at each use rather than
## cached at scene start, so a speed changed from the in-battle menu takes
## effect on the very next animation.
func speed() -> GameSpeed:
	return speed_override if speed_override != null else Settings.speed


# --- movement ----------------------------------------------------------------


## Tweens a sprite along a path without touching the sim. Awaitable.
##
## Instant sets the destination and returns in the same frame — a path the flow
## already walks, since a one-cell "move" has always returned without a tween.
func animate_path(sprite: UnitSprite, path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	Sfx.play(&"move", -6.0)
	var tier := speed()
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
## Under Instant the flash, fade and shake all fall away but the sounds stay: an
## attack the player triggered has to register even when there is nothing to see.
func animate_combat(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	var defender_sprite := view.sprite_for(defender)
	var attacker_sprite := view.sprite_for(attacker)
	view.refresh_sprite(attacker)  # snap to the committed destination
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
	var tier := speed()
	await sprite.flash_hit(tier.flash_in_seconds(), tier.flash_out_seconds())


## Fades a sprite out and frees it, at the active tier's pace. Awaitable, and
## the single place a death fade's length is decided — Battle's Join merge fades
## a sprite outside combat entirely and comes through here for that reason.
func fade_out(sprite: UnitSprite) -> void:
	await sprite.die(speed().death_fade_seconds())


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
	_banner_tween.tween_interval(speed().banner_seconds())
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
	_power_banner_tween.tween_interval(speed().power_banner_seconds())
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
	if capturing or speed().instant:
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
