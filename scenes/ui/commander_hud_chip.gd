class_name CommanderHudChip
extends PanelContainer
## The compact battle-HUD identity of the side in hand: a portrait, the
## commander's name and Command Power, and a charge meter whose colour and label
## say which of four states it is in — charging, ready, active, or (for a side
## playing without a power) hidden entirely, so the HUD looks exactly as it did
## before commanders existed.
##
## The same "portrait + faction tint + exact power copy" treatment as the full
## card and the activation banner, at chip density (plan G1's "one component,
## three densities"). All styling comes from CommanderVisuals; the numbers come
## straight from the live CommanderState. Presentation only — the Fire button is
## wired by Battle to PowerCommand, which stays the single authority on legality.

const _READY := Color(0.957, 0.745, 0.196)
const _ACTIVE := Color(0.451, 0.808, 0.435)
const _PORTRAIT := 40

## Wired by Battle to _fire_command_power. Lives in the chip so the fire control
## sits with the readiness it reflects.
var fire_button: Button

var _built := false
var _field: Panel
var _portrait: TextureRect
var _name_label: Label
var _sub_label: Label
var _meter: ProgressBar
var _state_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(210, 0)
	add_theme_stylebox_override(
		"panel", _box(Color(0.141, 0.165, 0.180), CommanderVisuals.HARD_BORDER)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_field = Panel.new()
	_field.custom_minimum_size = Vector2(_PORTRAIT, _PORTRAIT + 4)
	_field.clip_contents = true
	row.add_child(_field)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.add_child(_portrait)

	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", 1)
	data.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(data)

	_name_label = _mono(9, Color.WHITE)
	data.add_child(_name_label)
	_sub_label = _mono(7, Color(0.678, 0.706, 0.722))
	data.add_child(_sub_label)

	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(0, 8)
	_meter.max_value = 1.0
	_meter.step = 0.001
	_meter.show_percentage = false
	_meter.add_theme_stylebox_override("background", _flat(Color(0.067, 0.082, 0.094)))
	data.add_child(_meter)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	_state_label = _mono(7, Color(0.847, 0.863, 0.875))
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_state_label)
	fire_button = Button.new()
	fire_button.text = "FIRE"
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.add_theme_font_size_override("font_size", 7)
	foot.add_child(fire_button)
	data.add_child(foot)

	_built = true


## Brings the chip in step with the side in hand. `is_ai` greys the Fire button
## for a computer commander (it fills its meter but the click would be refused),
## matching the old text HUD.
func update_state(co_state: CommanderState, is_ai: bool) -> void:
	if not _built:
		return
	var commander := co_state.type
	if not commander.has_power():
		hide()
		return
	show()
	var theme := CommanderVisuals.theme_for(commander)
	_field.add_theme_stylebox_override("panel", _flat(theme.color))
	_portrait.texture = CommanderVisuals.portrait_for(commander)
	_name_label.text = commander.display_name.to_upper()
	_sub_label.text = "%s · %s" % [theme.display, commander.power_name]

	if co_state.power_active:
		_meter.value = 1.0
		_set_fill(_ACTIVE)
		_state_label.text = "ACTIVE — %s" % commander.power_name
	elif co_state.is_ready():
		_meter.value = 1.0
		_set_fill(_READY)
		_state_label.text = "READY"
	else:
		_meter.value = co_state.charge_ratio()
		_set_fill(theme.color_light)
		_state_label.text = "%d / %d" % [co_state.charge, commander.power_cost]

	fire_button.visible = co_state.is_ready() and not is_ai
	fire_button.disabled = not co_state.is_ready() or is_ai


func _set_fill(color: Color) -> void:
	_meter.add_theme_stylebox_override("fill", _flat(color))


func _mono(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(bg)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(5)
	return box
