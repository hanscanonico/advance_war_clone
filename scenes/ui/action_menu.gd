class_name ActionMenu
extends PanelContainer
## Minimal AW-style action menu (M2: Wait / Cancel; Fire etc. arrive in M3).
## The battle scene opens it with a list of actions; it emits the chosen id.
## Keyboard: cursor up/down + confirm/cancel. Mouse: click a row.

signal action_chosen(action: StringName)

@onready var rows: VBoxContainer = %MenuRows

var _ids: Array[StringName] = []
var _labels: Array[String] = []
var _disabled: Array[bool] = []
var _index := 0


## actions: [{id: StringName, label: String, disabled?: bool}, ...]
## At least one entry must be enabled (menus always include Cancel).
func open(actions: Array[Dictionary], screen_pos: Vector2) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_ids.clear()
	_labels.clear()
	_disabled.clear()
	for entry: Dictionary in actions:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 10)
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
	action_chosen.emit(id)


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
