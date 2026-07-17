extends PanelContainer
## AW-style corner panel showing the hovered tile's terrain stats.
## Flips to the other bottom corner when the cursor gets close (set_side).

const TEAM_NAMES := {0: "Neutral", 1: "Red Army", 2: "Blue Army"}
const CLASS_LABELS: Array = [
	[TerrainType.FOOT, "Foot"],
	[TerrainType.BOOT, "Boot"],
	[TerrainType.TIRES, "Tires"],
	[TerrainType.TREADS, "Treads"],
]

@onready var name_label: Label = %NameLabel
@onready var def_label: Label = %DefLabel
@onready var move_label: Label = %MoveLabel
@onready var owner_label: Label = %OwnerLabel


func show_terrain(terrain: TerrainType, owner_team: int) -> void:
	name_label.text = terrain.display_name
	def_label.text = "DEF %d" % terrain.defense_stars
	var parts := PackedStringArray()
	for pair: Array in CLASS_LABELS:
		var cost: int = terrain.move_cost(pair[0])
		parts.append("%s %s" % [pair[1], "-" if cost == TerrainType.IMPASSABLE else str(cost)])
	move_label.text = "  ".join(parts)
	owner_label.visible = terrain.is_property
	owner_label.text = TEAM_NAMES.get(owner_team, "Team %d" % owner_team)


func set_side(on_right: bool) -> void:
	var preset := Control.PRESET_BOTTOM_RIGHT if on_right else Control.PRESET_BOTTOM_LEFT
	set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 8)
