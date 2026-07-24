class_name CommanderCard
extends PanelContainer
## The full commander card: a large portrait establishes identity, then the name,
## doctrine, and Command Power follow in a strict vertical hierarchy — the
## "face before rules" reading order the supplied Claude card sheet is built on.
##
## Every value it shows is bound straight from the sim-side CommanderType
## (display_name, faction, doctrine_text, power_quotes, power_name, power_text,
## power_cost, power_duration); nothing is duplicated here, so the card can
## never drift from the numbers the rules actually use. All styling — the faction field colour,
## the emblem, the portrait — comes from CommanderVisuals, the one authority on
## it. The card itself is pure presentation and never touches core/.
##
## Built in code rather than a .tscn: the layout is regular and data-driven, and
## the repo would rather not hand-maintain scene-graph plumbing for it.

const _NAME_SIZE := 15
const _MICRO_SIZE := 8
const _BODY_SIZE := 10
const _POWER_NAME_SIZE := 12
const _PORTRAIT_H := 96

var _commander: CommanderType
var _built := false

var _field: Panel
var _portrait: TextureRect
var _emblem: TextureRect
var _name_band: PanelContainer
var _name_label: Label
var _quote_label: Label
var _doctrine_label: Label
var _power_box: PanelContainer
var _power_cost_label: Label
var _power_name_label: Label
var _power_text_label: Label


func _ready() -> void:
	_build()
	if _commander != null:
		_apply()


## Points the card at a commander (or CommanderType.neutral() for "No Commander").
## Safe to call before the node enters the tree; the card applies it once built.
func bind(commander: CommanderType) -> void:
	_commander = commander
	if _built:
		_apply()


func _build() -> void:
	custom_minimum_size = Vector2(158, 0)
	add_theme_stylebox_override("panel", _hard_box(CommanderVisuals.HARD_BORDER, 3))

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)

	# --- portrait stage: faction field, portrait, emblem pin ---
	# A plain Panel, not a PanelContainer: the latter force-stretches every child
	# to fill it, which would blow the little emblem up over the whole portrait.
	_field = Panel.new()
	_field.custom_minimum_size = Vector2(0, _PORTRAIT_H)
	_field.clip_contents = true
	rows.add_child(_field)

	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.add_child(_portrait)

	_emblem = TextureRect.new()
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_emblem.position = Vector2(6, 6)
	_emblem.size = Vector2(22, 22)
	_field.add_child(_emblem)

	# --- name band ---
	# A PanelContainer, so its stylebox paints the faction-dark band behind the
	# name (a MarginContainer draws no background).
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", _NAME_SIZE)
	_name_band = PanelContainer.new()
	_name_band.add_child(_pad(_name_label, 6, 3))
	rows.add_child(_name_band)

	# --- rules copy on paper ---
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 5)
	var copy_wrap := _paper_panel(copy, 8, 7)
	rows.add_child(copy_wrap)

	# The general's signature line — power_quotes[0], the same words the
	# activation banner opens with on a first firing (power-quotes plan PQ2), so
	# the select screen introduces the character the battle then delivers.
	_quote_label = Label.new()
	_quote_label.add_theme_font_size_override("font_size", _BODY_SIZE)
	_quote_label.add_theme_color_override("font_color", Color(0.408, 0.443, 0.471))
	_quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_quote_label)

	_doctrine_label = _labelled_block(copy, "DOCTRINE")

	_power_box = PanelContainer.new()
	_power_box.add_theme_stylebox_override("panel", _hard_box(Color(0.196, 0.227, 0.251), 2))
	copy.add_child(_power_box)
	var power_rows := VBoxContainer.new()
	power_rows.add_theme_constant_override("separation", 1)
	_power_box.add_child(power_rows)

	var power_head := _pad(null, 5, 3)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	var head_label := _mono("COMMAND POWER", _MICRO_SIZE, Color(0.949, 0.957, 0.961))
	head_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_cost_label = _mono("", _MICRO_SIZE, Color(0.957, 0.745, 0.196))
	head_row.add_child(head_label)
	head_row.add_child(_power_cost_label)
	power_head.add_child(head_row)  # power_head is a MarginContainer
	power_rows.add_child(power_head)

	_power_name_label = _mono("", _POWER_NAME_SIZE, Color(0.667, 0.224, 0.184))
	power_rows.add_child(_pad(_power_name_label, 6, 0))

	_power_text_label = Label.new()
	_power_text_label.add_theme_font_size_override("font_size", _BODY_SIZE)
	_power_text_label.add_theme_color_override("font_color", CommanderVisuals.PAPER_INK)
	_power_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_rows.add_child(_pad(_power_text_label, 6, 4))

	_built = true


func _apply() -> void:
	var theme := CommanderVisuals.theme_for(_commander)
	_field.add_theme_stylebox_override("panel", _flat_box(theme.color))
	_portrait.texture = CommanderVisuals.portrait_for(_commander)
	if theme.key == CommanderVisuals.NEUTRAL_KEY:
		_emblem.texture = null
		_emblem.visible = false
	else:
		_emblem.texture = CommanderVisuals.emblem_for(_commander)
		_emblem.visible = true

	_name_label.text = _commander.display_name
	_name_label.add_theme_color_override("font_color", theme.ink)
	_name_band.add_theme_stylebox_override("panel", _flat_box(theme.color_dark))

	_quote_label.visible = not _commander.power_quotes.is_empty()
	if _quote_label.visible:
		_quote_label.text = "“%s”" % _commander.power_quotes[0]

	_doctrine_label.text = (
		_commander.doctrine_text
		if not _commander.doctrine_text.is_empty()
		else "Plays by the standard rules — no passive doctrine."
	)

	if _commander.has_power():
		_power_box.visible = true
		_power_cost_label.text = "%s  %d" % [_duration_tag(), _commander.power_cost]
		_power_name_label.text = _commander.power_name
		_power_text_label.text = _commander.power_text
	else:
		_power_box.visible = false


## Whether the power lasts only the owner's turn or through the round — the one
## number a player needs beyond cost to weigh timing.
func _duration_tag() -> String:
	return "ROUND" if _commander.power_duration == CommanderType.Duration.ROUND else "THIS TURN"


# --- small builders ----------------------------------------------------------


## A "MICRO-LABEL / body text" pair, returning the body Label for later binding.
func _labelled_block(parent: Node, micro: String) -> Label:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	block.add_child(_mono(micro, _MICRO_SIZE, Color(0.408, 0.443, 0.471)))
	var body := Label.new()
	body.add_theme_font_size_override("font_size", _BODY_SIZE)
	body.add_theme_color_override("font_color", CommanderVisuals.PAPER_INK)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(body)
	return body


func _mono(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## Wraps `child` (may be null) in a MarginContainer with even h/v padding.
func _pad(child: Control, h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	if child != null:
		margin.add_child(child)
	return margin


func _paper_panel(child: Control, h: int, v: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_box(CommanderVisuals.PAPER))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_pad(child, h, v))
	return panel


func _flat_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


func _hard_box(border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CommanderVisuals.PAPER
	box.border_color = border
	box.set_border_width_all(width)
	return box
