class_name TerrainPanel
extends PanelContainer
## AW-style corner panel for the hovered tile. A unit on the tile is the
## headline card; terrain drops to a compact card below it.
## Flips to the other bottom corner when the cursor gets close (set_side).

const ACTED_TINT := Color(0.62, 0.62, 0.62)
const MAX_DEFENSE_STARS := 4
const TERRAIN_ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"
## Terrain atlas cell size; mirrors BattleView.TERRAIN_PX rather than
## coupling the UI panel to the battle scene for one constant.
const TERRAIN_PX := 64
const CLASS_LABELS: Array = [
	[TerrainType.FOOT, "Foot"],
	[TerrainType.BOOT, "Boot"],
	[TerrainType.TIRES, "Tires"],
	[TerrainType.TREADS, "Treads"],
	[TerrainType.AIR, "Air"],
	[TerrainType.SHIP, "Ship"],
	[TerrainType.LANDER, "Lander"],
]

## How each side is named and tinted. Battle resolves it once and BattleView
## hands it over (see BattleView.setup); the panel names the hovered unit's side
## and the tile's owner through it instead of a private Red/Blue table.
var identity: SideIdentity

@onready var unit_rows: VBoxContainer = %UnitRows
@onready var unit_icon: TextureRect = %UnitIcon
@onready var unit_name_label: Label = %UnitNameLabel
@onready var unit_team_label: Label = %UnitTeamLabel
@onready var unit_hp_label: Label = %UnitHpLabel
@onready var unit_supply_label: Label = %UnitSupplyLabel
@onready var unit_extra_label: Label = %UnitExtraLabel
@onready var separator: HSeparator = %Separator
@onready var terrain_icon: TextureRect = %TerrainIcon
@onready var name_label: Label = %NameLabel
@onready var def_label: Label = %DefLabel
@onready var move_label: Label = %MoveLabel
@onready var owner_label: Label = %OwnerLabel


func _ready() -> void:
	set_side(false)  # apply the min-size preset before the first hover


## Single entry point per hovered tile; unit is null on empty or fogged tiles.
## `carrying` names the cargo when the unit is a loaded transport. The acted
## dim and "Waited" badge apply only to `active_team`'s own units, matching
## the map sprite's tint.
func show_tile(
	terrain: TerrainType,
	owner_team: int,
	active_team: int,
	capture_left: int = -1,
	unit: Unit = null,
	carrying: String = ""
) -> void:
	_show_unit(unit, carrying, active_team)
	_show_terrain(terrain, owner_team, capture_left, unit)


func _show_unit(unit: Unit, carrying: String, active_team: int) -> void:
	unit_rows.visible = unit != null
	separator.visible = unit != null
	if unit == null:
		return
	unit_icon.texture = UnitSprite.texture_for(unit.type, identity.atlas_row(unit.team))
	unit_name_label.text = unit.type.display_name
	unit_team_label.text = identity.display_name(unit.team)
	# The lighter shade of the side's theme, so a dark faction (Iron slate) still
	# reads against the panel the way the old pastel team tints did.
	unit_team_label.add_theme_color_override("font_color", identity.theme(unit.team).color_light)
	unit_hp_label.text = "HP %d/10" % unit.displayed_hp()
	var supply := "Fuel %d/%d" % [unit.fuel, unit.type.max_fuel]
	if unit.type.max_ammo > 0:
		supply += "   Ammo %d/%d" % [unit.ammo, unit.type.max_ammo]
	unit_supply_label.text = supply
	var waited := unit.acted and unit.team == active_team
	var extras := PackedStringArray()
	if unit.type.min_range > 1:
		extras.append("Rng %d-%d" % [unit.type.min_range, unit.type.max_range])
	if unit.dived:
		extras.append("Dived")
	if unit.running_dry():
		extras.append("Low fuel")
	if carrying != "":
		extras.append("Carrying %s" % carrying)
	if waited:
		extras.append("Waited")
	unit_extra_label.visible = not extras.is_empty()
	unit_extra_label.text = "  ".join(extras)
	unit_rows.modulate = ACTED_TINT if waited else Color.WHITE


func _show_terrain(terrain: TerrainType, owner_team: int, capture_left: int, unit: Unit) -> void:
	terrain_icon.texture = _terrain_texture(terrain, owner_team)
	name_label.text = terrain.display_name
	def_label.text = "DEF %s" % _stars(terrain.defense_stars)
	move_label.text = _move_costs(terrain, unit)
	owner_label.visible = terrain.is_property
	var owner_text: String = identity.display_name(owner_team)
	if capture_left >= 0:
		owner_text += "  (capture: %d left)" % capture_left
	owner_label.text = owner_text


## Occupied tile: only the occupant's move class matters, and it is always a real
## cost — nothing stands where it cannot go. Empty tile: the planning row, listing
## the classes that can actually enter.
##
## Listing only those, rather than every class with a dash for the rest, is what
## keeps the row readable now that there are more classes than the four the game
## shipped with: a mountain says "Foot 2  Boot 1  Air 1", and what is missing is
## as legible as what is there.
func _move_costs(terrain: TerrainType, unit: Unit) -> String:
	var parts := PackedStringArray()
	for pair: Array in CLASS_LABELS:
		var move_class: StringName = pair[0]
		if unit != null and unit.type.move_class != move_class:
			continue
		var cost: int = terrain.move_cost(move_class)
		if cost == TerrainType.IMPASSABLE:
			continue
		parts.append("%s %d" % [pair[1], cost])
	if parts.is_empty():
		return "Impassable"
	return "  ".join(parts)


func _stars(count: int) -> String:
	if count <= 0:
		return "0"
	var filled := mini(count, MAX_DEFENSE_STARS)
	return "★".repeat(filled) + "☆".repeat(MAX_DEFENSE_STARS - filled)


## The same artwork the board draws: one cell of the terrain atlas, with the
## owner-coloured row for properties (rows 1+ exist only when team_tinted).
func _terrain_texture(terrain: TerrainType, owner_team: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(TERRAIN_ATLAS_PATH)
	# The owner's resolved faction row, so the panel draws a captured property in
	# the same colour the board does — a neutral owner and a plain tile both fall
	# to row 0 through the resolver.
	var row: int = identity.atlas_row(owner_team) if terrain.team_tinted else 0
	atlas.region = Rect2(terrain.atlas_col * TERRAIN_PX, row * TERRAIN_PX, TERRAIN_PX, TERRAIN_PX)
	return atlas


func set_side(on_right: bool) -> void:
	var preset := Control.PRESET_BOTTOM_RIGHT if on_right else Control.PRESET_BOTTOM_LEFT
	set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 8)
