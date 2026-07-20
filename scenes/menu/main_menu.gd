extends Control
## Main menu: pick a map, commanders and match options, then hand off to the
## battle scene through the MatchConfig autoload.

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

@onready var map_option: OptionButton = %MapOption
@onready var red_co_option: OptionButton = %RedCoOption
@onready var blue_co_option: OptionButton = %BlueCoOption
@onready var fog_check: CheckButton = %FogCheck
@onready var one_player_button: Button = %OnePlayerButton
@onready var two_player_button: Button = %TwoPlayerButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton

## The roster in dropdown order, parsed once at load so the tooltips can quote
## real numbers off the board rather than a hand-kept table.
var _maps: Array[MapData] = []
## Commander ids in dropdown order, shared by both sides.
var _commander_ids: Array[StringName] = []
var _commander_db: CommanderDB


func _ready() -> void:
	_commander_db = CommanderDB.load_default()
	_populate_maps()
	_populate_commanders()
	continue_button.visible = SaveGame.has_save()
	one_player_button.pressed.connect(_start.bind([2] as Array[int], false))
	two_player_button.pressed.connect(_start.bind([] as Array[int], false))
	continue_button.pressed.connect(_start.bind([] as Array[int], true))
	quit_button.pressed.connect(get_tree().quit)
	one_player_button.grab_focus()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			ScreenshotUtil.capture_and_quit(self, arg.get_slice("=", 1))


## Smallest board first, so item 0 — the option the menu opens on — is the
## quickest match rather than whichever filename happened to sort first.
func _populate_maps() -> void:
	_maps = MapCatalog.ordered(TerrainDB.load_default())
	if _maps.is_empty():
		push_error("main menu: no maps found in %s" % MapCatalog.MAPS_DIR)
		return
	for map in _maps:
		map_option.add_item(MapCatalog.display_name(map.source_path))
	map_option.selected = 0
	map_option.item_selected.connect(_on_map_selected)
	_refresh_map_tooltip()


func _on_map_selected(_index: int) -> void:
	_refresh_map_tooltip()


## Size and property count read off the board itself; the blurb is the map
## file's first comment line. Same reasoning as the commander tooltips below —
## the 640x360 viewport has no room for a description beside the dropdown.
func _refresh_map_tooltip() -> void:
	var map := _map_at(map_option.selected)
	if map == null:
		map_option.tooltip_text = ""
		return
	map_option.tooltip_text = (
		"%d×%d · %d properties\n%s"
		% [map.width, map.height, map.property_cells().size(), map.description]
	)


func _map_at(index: int) -> MapData:
	if index < 0 or index >= _maps.size():
		return null
	return _maps[index]


## Both dropdowns list every general, neutral first, so "No Commander" stays the
## default and the menu opens on the match this game has always played.
##
## What each one actually does rides in the tooltip rather than in a blurb on
## the menu: the design viewport is 640x360, and a doctrine plus a power
## description for two sides is more text than that has room for without
## pushing the start buttons off the bottom.
func _populate_commanders() -> void:
	for commander in _commander_db.all():
		_commander_ids.append(commander.id)
		red_co_option.add_item(commander.display_name)
		blue_co_option.add_item(commander.display_name)
	red_co_option.selected = 0
	blue_co_option.selected = 0
	red_co_option.item_selected.connect(_on_commander_selected.bind(red_co_option))
	blue_co_option.item_selected.connect(_on_commander_selected.bind(blue_co_option))
	_refresh_tooltip(red_co_option)
	_refresh_tooltip(blue_co_option)


func _on_commander_selected(_index: int, option: OptionButton) -> void:
	_refresh_tooltip(option)


func _refresh_tooltip(option: OptionButton) -> void:
	var commander := _commander_at(option.selected)
	if not commander.has_power():
		option.tooltip_text = "No commander: the standard rules, and no Command Power."
		return
	option.tooltip_text = (
		"%s\n%s\n\n%s: %s"
		% [commander.faction, commander.doctrine_text, commander.power_name, commander.power_text]
	)


func _commander_at(index: int) -> CommanderType:
	if index < 0 or index >= _commander_ids.size():
		return CommanderType.neutral()
	return _commander_db.by_id(_commander_ids[index])


## `load_save` resumes the saved match (its own map, commanders and AI sides
## apply, so the dropdowns above are ignored).
func _start(ai_teams: Array[int], load_save: bool) -> void:
	var map := _map_at(map_option.selected)
	if map != null:
		MatchConfig.map_path = map.source_path
	MatchConfig.ai_teams = ai_teams
	MatchConfig.fog_enabled = fog_check.button_pressed
	MatchConfig.commanders = {
		1: _commander_at(red_co_option.selected).id,
		2: _commander_at(blue_co_option.selected).id,
	}
	MatchConfig.load_save = load_save
	get_tree().change_scene_to_file(BATTLE_SCENE)
