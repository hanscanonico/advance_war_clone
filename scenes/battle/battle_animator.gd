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

const MOVE_STEP_SECONDS := 0.06
const BANNER_SECONDS := 1.2
## How long the Command Power activation card holds before it slides away. Inside
## the plan's 0.9-1.2 s window.
const POWER_BANNER_SECONDS := 1.1

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

var _banner_tween: Tween
var _power_banner_tween: Tween

# --- movement ----------------------------------------------------------------


## Tweens a sprite along a path without touching the sim. Awaitable.
func animate_path(sprite: UnitSprite, path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	Sfx.play(&"move", -6.0)
	var tween := node.create_tween()
	for i in range(1, path.size()):
		tween.tween_property(sprite, "position", BattleView.cell_center(path[i]), MOVE_STEP_SECONDS)
	await tween.finished


# --- combat ------------------------------------------------------------------


## Plays out one already-resolved exchange: the hit, the shake, whichever side
## died, and the counter. Awaitable, so the flow resumes once the dust settles.
func animate_combat(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	var defender_sprite := view.sprite_for(defender)
	var attacker_sprite := view.sprite_for(attacker)
	view.refresh_sprite(attacker)  # snap to the committed destination
	Sfx.play(&"shot")
	await defender_sprite.flash_hit()
	shake_camera()
	if result.defender_died:
		Sfx.play(&"explosion")
		view.release_sprite(defender)
		await defender_sprite.die()
	else:
		view.refresh_sprite(defender)
	if result.countered:
		Sfx.play(&"shot")
		await attacker_sprite.flash_hit()
	if result.attacker_died:
		view.release_sprite(attacker)
		await attacker_sprite.die()
	else:
		view.refresh_sprite(attacker)
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
	_banner_tween.tween_interval(BANNER_SECONDS)
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
	_power_banner_tween.tween_interval(POWER_BANNER_SECONDS)
	_power_banner_tween.tween_callback(power_banner.hide)


# --- camera and cursor -------------------------------------------------------


## Brief camera jitter on combat hits. Presentation-only randomness: this
## must never touch game.rng, which is reserved for deterministic sim luck.
##
## Skipped while capturing: the shake is still mid-tween when a frame is taken,
## so it offsets the whole board by a few pixels and makes two otherwise
## identical captures differ everywhere — noise that would hide a real
## rendering regression.
func shake_camera(strength: float = 3.0) -> void:
	if capturing:
		return
	var tween := node.create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, 0.04)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.04)


## Skipped while capturing, for the same reason as `shake_camera`: a loop has
## no settled state, so every frame catches it at a different phase.
func start_cursor_pulse() -> void:
	if capturing:
		return
	var tween := node.create_tween().set_loops()
	(
		tween
		. tween_property(cursor, "scale", Vector2(1.15, 1.15), 0.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	tween.tween_property(cursor, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
