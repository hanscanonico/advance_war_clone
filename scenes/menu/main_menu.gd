extends Control
## Main menu: pick a map and match options, then hand off to the battle
## scene through the MatchConfig autoload.

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const MAPS_DIR := "res://maps"

@onready var map_option: OptionButton = %MapOption
@onready var fog_check: CheckButton = %FogCheck
@onready var one_player_button: Button = %OnePlayerButton
@onready var two_player_button: Button = %TwoPlayerButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton

var _map_paths: Array[String] = []


func _ready() -> void:
	_populate_maps()
	continue_button.visible = SaveGame.has_save()
	one_player_button.pressed.connect(_start.bind([2] as Array[int], false))
	two_player_button.pressed.connect(_start.bind([] as Array[int], false))
	continue_button.pressed.connect(_start.bind([] as Array[int], true))
	quit_button.pressed.connect(get_tree().quit)
	one_player_button.grab_focus()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			ScreenshotUtil.capture_and_quit(self, arg.get_slice("=", 1))


func _populate_maps() -> void:
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		push_error("main menu: cannot open %s" % MAPS_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list .txt files with a .remap suffix.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".txt"):
			continue
		_map_paths.append(MAPS_DIR.path_join(name))
		map_option.add_item(name.trim_suffix(".txt").capitalize())
	if map_option.item_count > 0:
		map_option.selected = 0


## `load_save` resumes the saved match (its own map and AI sides apply).
func _start(ai_teams: Array[int], load_save: bool) -> void:
	if not _map_paths.is_empty():
		MatchConfig.map_path = _map_paths[map_option.selected]
	MatchConfig.ai_teams = ai_teams
	MatchConfig.fog_enabled = fog_check.button_pressed
	MatchConfig.load_save = load_save
	get_tree().change_scene_to_file(BATTLE_SCENE)
