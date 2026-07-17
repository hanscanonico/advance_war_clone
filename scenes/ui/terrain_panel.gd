class_name TerrainPanel
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
@onready var unit_label: Label = %UnitLabel


func show_terrain(terrain: TerrainType, owner_team: int, capture_left: int = -1) -> void:
	name_label.text = terrain.display_name
	def_label.text = "DEF %d" % terrain.defense_stars
	var parts := PackedStringArray()
	for pair: Array in CLASS_LABELS:
		var cost: int = terrain.move_cost(pair[0])
		parts.append("%s %s" % [pair[1], "-" if cost == TerrainType.IMPASSABLE else str(cost)])
	move_label.text = "  ".join(parts)
	owner_label.visible = terrain.is_property
	var owner_text: String = TEAM_NAMES.get(owner_team, "Team %d" % owner_team)
	if capture_left >= 0:
		owner_text += "  (capture: %d left)" % capture_left
	owner_label.text = owner_text


## Shows the hovered unit's line, or hides it when unit is null.
func show_unit(unit: Unit) -> void:
	unit_label.visible = unit != null
	if unit == null:
		return
	var team_name: String = TEAM_NAMES.get(unit.team, "Team %d" % unit.team)
	var suffix := " (acted)" if unit.acted else ""
	unit_label.text = "%s - HP %d - %s%s" % [
		unit.type.display_name, unit.displayed_hp(), team_name, suffix,
	]


func set_side(on_right: bool) -> void:
	var preset := Control.PRESET_BOTTOM_RIGHT if on_right else Control.PRESET_BOTTOM_LEFT
	set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 8)
