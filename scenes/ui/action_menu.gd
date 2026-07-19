class_name ActionMenu
extends PanelContainer
## Minimal AW-style action menu (M2: Wait / Cancel; Fire etc. arrive in M3).
## The battle scene opens it with a list of actions; it emits the chosen id.
## Keyboard: cursor up/down + confirm/cancel. Mouse: click a row.

signal action_chosen(action: StringName)

## Row artwork is authored at the atlas's own resolution (64px for the unit
## sprites), which would dwarf a 10px label, so every icon is capped to one
## world tile wide. Aspect ratio is preserved, so square art lands at 16x16.
const ICON_PX := 16

@onready var rows: VBoxContainer = %MenuRows

var _ids: Array[StringName] = []
var _labels: Array[String] = []
var _disabled: Array[bool] = []
var _index := 0


## actions: [{id: StringName, label: String, disabled?: bool, icon?: Texture2D}, ...]
## At least one entry must be enabled (menus always include Cancel).
## `icon` draws to the left of the label; rows that omit it in an illustrated
## menu get a spacer so every label still starts in the same column.
func open(actions: Array[Dictionary], screen_pos: Vector2) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_ids.clear()
	_labels.clear()
	_disabled.clear()
	var spacer := _spacer_icon(actions)
	for entry: Dictionary in actions:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_constant_override("icon_max_width", ICON_PX)
		button.icon = entry.get("icon", spacer)
		var id: StringName = entry.id
		var is_disabled: bool = entry.get("disabled", false)
		button.disabled = is_disabled
		button.pressed.connect(func() -> void: choose(id))
		rows.add_child(button)
		_ids.append(id)
		_labels.append(entry.label)
		_disabled.append(is_disabled)
	_index = -1
	_step_index(1)
	_update_labels()
	position = screen_pos
	show()
	_clamp_to_view()


func close() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cursor_up", true):
		_step_index(-1)
		_update_labels()
	elif event.is_action_pressed(&"cursor_down", true):
		_step_index(1)
		_update_labels()
	elif event.is_action_pressed(&"confirm"):
		choose(_ids[_index])
	elif event.is_action_pressed(&"cancel"):
		choose(&"cancel")
	else:
		return
	get_viewport().set_input_as_handled()


## Public so scripted drivers (screenshot demos) exercise the same path as
## the buttons and keyboard.
func choose(id: StringName) -> void:
	var i := _ids.find(id)
	if i >= 0 and _disabled[i]:
		return
	action_chosen.emit(id)


## Transparent stand-in the size icons are capped to, so icon-less rows keep
## their labels in the same column. Null when no row has an icon at all: plain
## verb menus then draw exactly as they did before.
func _spacer_icon(actions: Array[Dictionary]) -> Texture2D:
	if not actions.any(func(entry: Dictionary) -> bool: return entry.get("icon") != null):
		return null
	var image := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)


## Advances the highlight, skipping disabled rows.
func _step_index(delta: int) -> void:
	for attempt in _ids.size():
		_index = wrapi(_index + delta, 0, _ids.size())
		if not _disabled[_index]:
			return


func _update_labels() -> void:
	for i in rows.get_child_count():
		var button := rows.get_child(i) as Button
		button.text = ("> " if i == _index else "  ") + _labels[i]


func _clamp_to_view() -> void:
	# Size is only valid one frame after the buttons were added.
	await get_tree().process_frame
	if not visible:
		return
	var view := get_viewport().get_visible_rect().size
	var max_pos := (view - size - Vector2(4, 4)).max(Vector2(4, 4))
	position = position.clamp(Vector2(4, 4), max_pos)
