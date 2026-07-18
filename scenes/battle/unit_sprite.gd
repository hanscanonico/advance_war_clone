class_name UnitSprite
extends Sprite2D
## Visual for one Unit. Position and tint always derive from the sim state
## via refresh(); the battle scene tweens `position` only for move previews.

const TILE := 16
## The units atlas is drawn at 4x the world grid so the PixVoxel art keeps its
## detail; the sprite is scaled back down to cover exactly one cell. Grid maths
## everywhere else still speaks in TILE.
const SPRITE_PX := 64
const SPRITE_SCALE := float(TILE) / float(SPRITE_PX)
const UNITS_ATLAS_PATH := "res://assets/tiles/units_atlas.png"
const ACTED_TINT := Color(0.55, 0.55, 0.55)

var unit: Unit
## Team whose turn it is. Only that team's units grey out when exhausted;
## `acted` on the waiting team is stale until its own turn readies it.
var active_team: int = 0

@onready var hp_label: Label = $HpLabel


func setup(p_unit: Unit, p_active_team: int) -> void:
	unit = p_unit
	active_team = p_active_team
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UNITS_ATLAS_PATH)
	atlas.region = Rect2(
		unit.type.atlas_col * SPRITE_PX, unit.team * SPRITE_PX, SPRITE_PX, SPRITE_PX
	)
	texture = atlas
	scale = Vector2.ONE * SPRITE_SCALE
	# The badge is authored against the world grid, so undo the sprite's scale
	# rather than letting it shrink with the art. Its offset is authored in the
	# same units and needs the same treatment, or the badge creeps toward centre.
	hp_label.scale = Vector2.ONE / SPRITE_SCALE
	hp_label.position /= SPRITE_SCALE
	refresh()


func set_active_team(team: int) -> void:
	active_team = team
	refresh()


## Re-syncs position, visibility, acted tint, and HP badge from the sim
## state. Carried units are hidden until dropped.
func refresh() -> void:
	position = Vector2(unit.cell * TILE) + Vector2(TILE, TILE) / 2.0
	visible = unit.carrier == null
	modulate = ACTED_TINT if unit.acted and unit.team == active_team else Color.WHITE
	hp_label.visible = unit.displayed_hp() < 10
	hp_label.text = str(unit.displayed_hp())


## Quick white flash when taking a hit. Awaitable.
func flash_hit() -> void:
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(4.0, 4.0, 4.0), 0.08)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.12)
	await tween.finished


## Fade out and free. Awaitable; the caller must drop its reference first.
func die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	await tween.finished
	queue_free()
