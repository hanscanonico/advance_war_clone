class_name UnitSprite
extends Sprite2D
## Visual for one Unit. Position and tint always derive from the sim state
## via refresh(); the battle scene tweens `position` only for move previews.

const TILE := 16
const UNITS_ATLAS_PATH := "res://assets/tiles/units_atlas.png"
const ACTED_TINT := Color(0.55, 0.55, 0.55)

var unit: Unit

@onready var hp_label: Label = $HpLabel


func setup(p_unit: Unit) -> void:
	unit = p_unit
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UNITS_ATLAS_PATH)
	atlas.region = Rect2(unit.type.atlas_col * TILE, unit.team * TILE, TILE, TILE)
	texture = atlas
	refresh()


## Re-syncs position, acted tint, and HP badge from the sim state.
func refresh() -> void:
	position = Vector2(unit.cell * TILE) + Vector2(TILE, TILE) / 2.0
	modulate = ACTED_TINT if unit.acted else Color.WHITE
	hp_label.visible = unit.displayed_hp() < 10
	hp_label.text = str(unit.displayed_hp())
