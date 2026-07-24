class_name BattleZoom
extends RefCounted
## Owns the battle camera's zoom: the current level, its clamp against the view's
## minimum, and the keyboard zoom steps. Battle decides when to zoom and the view
## owns the camera itself — this sits between them, split out of battle.gd so the
## interaction flow could shed a responsibility (the gdlintrc line ratchet).
##
## Semantics are unchanged from when this lived in Battle: the floor is the view's
## min_zoom ceil'd to two decimals, the ceiling is MAX_ZOOM, and each key press
## steps the level by STEP.

const MAX_ZOOM := 5.0
const STEP := 1.0

var _view: BattleView
var _zoom := 2.0
var _min_zoom := 1.0


func _init(view: BattleView) -> void:
	_view = view


## How far the player may zoom out depends on the viewport, so the clamp is
## worked out here; the view owns the camera itself.
func setup() -> void:
	_min_zoom = _view.min_zoom()
	set_zoom(_zoom)


func set_zoom(zoom: float) -> void:
	# The floor itself is capped at MAX_ZOOM: on a map tiny enough that even the
	# whole-map zoom exceeds it, clampf(min > max) would return the floor and the
	# zoom keys would oscillate between it and MAX_ZOOM. Such a map pins here.
	var floor_zoom := minf(ceilf(_min_zoom * 100.0) / 100.0, MAX_ZOOM)
	_zoom = clampf(zoom, floor_zoom, MAX_ZOOM)
	_view.set_zoom(_zoom)


## The keyboard zoom steps. Returns true when it consumed the event, so the input
## handler stops there — the two branches this replaced sat first in that chain
## and swallowed the event the same way.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"zoom_in"):
		set_zoom(_zoom + STEP)
		return true
	if event.is_action_pressed(&"zoom_out"):
		set_zoom(_zoom - STEP)
		return true
	return false
