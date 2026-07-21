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
## A submerged boat is drawn faint for its own side. The enemy does not see it
## at all — that is Vision's answer, arriving here as `fogged`.
const DIVED_ALPHA := 0.5
## HpLabel's offset in unit_sprite.tscn, in world-grid units.
const HP_LABEL_OFFSET := Vector2(1, 0)
## FuelLabel sits opposite it, on the other side of the sprite.
const FUEL_LABEL_OFFSET := Vector2(-8, 0)

var unit: Unit
## Team whose turn it is. Only that team's units grey out when exhausted;
## `acted` on the waiting team is stale until its own turn readies it.
var active_team: int = 0
## True when the viewing team may not see this unit. BattleView owns the answer
## — `Vision` decides it — and the sprite only remembers it. Held rather than
## re-derived so that every redraw honours it: a sprite that worked visibility
## out for itself would un-hide a fogged enemy on the next refresh.
var fogged: bool = false

@onready var hp_label: Label = $HpLabel
@onready var fuel_label: Label = $FuelLabel


func setup(p_unit: Unit, p_active_team: int) -> void:
	unit = p_unit
	active_team = p_active_team
	texture = texture_for(p_unit.type, p_unit.team)
	scale = Vector2.ONE * SPRITE_SCALE
	# The badges are authored against the world grid, so undo the sprite's scale
	# rather than letting them shrink with the art. Their offsets are authored in
	# the same units and need the same treatment, or a badge creeps toward centre.
	hp_label.scale = Vector2.ONE / SPRITE_SCALE
	hp_label.position = HP_LABEL_OFFSET / SPRITE_SCALE
	fuel_label.scale = Vector2.ONE / SPRITE_SCALE
	fuel_label.position = FUEL_LABEL_OFFSET / SPRITE_SCALE
	refresh()


## Atlas region for one unit kind in one team's colours, at the atlas's own
## SPRITE_PX resolution. Static so menus can show the same artwork the board
## does without instancing a sprite; callers that draw it outside the world
## grid size it themselves.
static func texture_for(type: UnitType, team: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UNITS_ATLAS_PATH)
	atlas.region = Rect2(type.atlas_col * SPRITE_PX, team * SPRITE_PX, SPRITE_PX, SPRITE_PX)
	return atlas


func set_active_team(team: int) -> void:
	active_team = team
	refresh()


## Re-syncs position, visibility, acted tint, and HP badge from the sim
## state. Carried units are hidden until dropped, and so is anything the
## viewing team may not see — see `fogged`.
func refresh() -> void:
	position = Vector2(unit.cell * TILE) + Vector2(TILE, TILE) / 2.0
	visible = unit.carrier == null and not fogged
	var tint := ACTED_TINT if unit.acted and unit.team == active_team else Color.WHITE
	tint.a *= DIVED_ALPHA if unit.dived else 1.0
	modulate = tint
	hp_label.visible = unit.displayed_hp() < 10
	hp_label.text = str(unit.displayed_hp())
	fuel_label.visible = unit.running_dry()


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
