class_name CommanderInfoSheet
extends Control
## The in-battle commander reference: both sides' full cards, opened from the
## battle menu rather than a hover tooltip (readiness plan G3). Showing both is
## deliberate and safe — a commander's identity and doctrine are match metadata,
## not a fog-hidden unit position, so nothing here leaks what the viewer cannot
## see on the board.
##
## Reuses the same CommanderCard the selection page does; the only thing new is a
## RED/BLUE header over each. Pure presentation — it reads the two CommanderTypes
## and closes itself; Battle owns when it opens and blocks board input while it is
## up.

signal closed

const RED_TEAM := Color(0.859, 0.290, 0.231)
const BLUE_TEAM := Color(0.220, 0.396, 0.847)

var _built := false
var _red_card: CommanderCard
var _blue_card: CommanderCard
var _close_button: Button


func _ready() -> void:
	_build()
	hide()


## Shows both sides' cards and takes focus, so a controller or keyboard can close
## it without reaching for the mouse.
func open(red_co: CommanderType, blue_co: CommanderType) -> void:
	if not _built:
		_build()
	_red_card.bind(red_co)
	_blue_card.bind(blue_co)
	show()
	_close_button.grab_focus.call_deferred()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.086, 0.106, 0.118, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	center.add_child(rows)

	var title := Label.new()
	title.text = "COMMANDERS"
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	rows.add_child(cards)
	_red_card = _titled_card(cards, "RED ARMY", RED_TEAM)
	_blue_card = _titled_card(cards, "BLUE ARMY", BLUE_TEAM)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.add_theme_font_size_override("font_size", 11)
	_close_button.pressed.connect(_emit_close)
	rows.add_child(_close_button)


func _titled_card(parent: Node, title: String, color: Color) -> CommanderCard:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	parent.add_child(column)

	var header := PanelContainer.new()
	var header_box := StyleBoxFlat.new()
	header_box.bg_color = color
	header.add_theme_stylebox_override("panel", header_box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	margin.add_child(label)
	header.add_child(margin)
	column.add_child(header)

	var card := CommanderCard.new()
	column.add_child(card)
	return card


func _shortcut_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_emit_close()
		accept_event()


func _emit_close() -> void:
	hide()
	closed.emit()
