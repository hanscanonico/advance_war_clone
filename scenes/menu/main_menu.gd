extends Control
## Main menu: pick a map and match options, choose commanders on the dedicated
## selection page, then hand off to the battle scene through MatchConfig.
##
## The two compact CO dropdowns are gone: "1 Player" and "2 Player" now open the
## CommanderSelectPanel (readiness plan G2), which is shown *over* this menu so
## the map and fog choices survive a Back. Nothing reaches MatchConfig until both
## commanders are confirmed there. "Continue" bypasses selection entirely — a
## saved match restores its own commanders (plan R5).

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

@onready var center: CenterContainer = $Center
@onready var map_option: OptionButton = %MapOption
@onready var fog_check: CheckButton = %FogCheck
@onready var one_player_button: Button = %OnePlayerButton
@onready var two_player_button: Button = %TwoPlayerButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton

## The roster in dropdown order, parsed once at load so the tooltips can quote
## real numbers off the board rather than a hand-kept table.
var _maps: Array[MapData] = []
var _select_panel: CommanderSelectPanel
## The AI sides the chosen mode will play; carried across the selection page so
## `confirmed` knows whether it was a one-player or hot-seat start.
var _pending_ai_teams: Array[int] = []


func _ready() -> void:
	_populate_maps()
	_select_panel = CommanderSelectPanel.new()
	add_child(_select_panel)
	_select_panel.confirmed.connect(_on_selection_confirmed)
	_select_panel.cancelled.connect(_on_selection_cancelled)
	continue_button.visible = SaveGame.has_save()
	one_player_button.pressed.connect(_open_select.bind([2] as Array[int]))
	two_player_button.pressed.connect(_open_select.bind([] as Array[int]))
	continue_button.pressed.connect(_continue)
	quit_button.pressed.connect(get_tree().quit)
	one_player_button.grab_focus()

	# Dev captures of the selection page: `--co-select` opens it on the Red slot,
	# `--co-select=blue` advances to the Blue slot. An ordinary capture (no such
	# flag) photographs the menu itself.
	var select_mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--co-select" or arg.begins_with("--co-select="):
			select_mode = arg.get_slice("=", 1) if arg.contains("=") else "red"
	if select_mode != "":
		_open_select([2] as Array[int])
		if select_mode == "blue":
			_select_panel.debug_advance_to_blue()
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


## Opens the selection page for the chosen mode, hiding the menu behind it so no
## focus or click leaks through to the buttons underneath.
func _open_select(ai_teams: Array[int]) -> void:
	_pending_ai_teams = ai_teams
	center.hide()
	_select_panel.begin(not ai_teams.is_empty())


func _on_selection_confirmed(red_id: StringName, blue_id: StringName) -> void:
	_start(_pending_ai_teams, false, {1: red_id, 2: blue_id})


func _on_selection_cancelled() -> void:
	center.show()
	one_player_button.grab_focus()


func _continue() -> void:
	# The saved match applies its own map, commanders and AI sides.
	_start([] as Array[int], true, {})


## `load_save` resumes the saved match (its own map, commanders and AI sides
## apply, so the dropdowns above are ignored).
func _start(ai_teams: Array[int], load_save: bool, commanders: Dictionary) -> void:
	var map := _map_at(map_option.selected)
	if map != null:
		MatchConfig.map_path = map.source_path
	MatchConfig.ai_teams = ai_teams
	MatchConfig.fog_enabled = fog_check.button_pressed
	MatchConfig.commanders = commanders
	MatchConfig.load_save = load_save
	get_tree().change_scene_to_file(BATTLE_SCENE)
