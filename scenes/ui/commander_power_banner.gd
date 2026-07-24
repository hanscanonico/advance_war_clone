class_name CommanderPowerBanner
extends PanelContainer
## The Command Power activation card: a portrait, the general's spoken line, the
## power's name, and its exact effect text, faction-tinted, shown center-screen
## for a beat when a power fires. The third and largest density of the shared
## card component (plan G1); it reads the same CommanderType and CommanderVisuals
## as the select card and HUD chip, so the three never disagree about a
## commander's face, colour, or copy.
##
## The quote is the card's headline and reads as the portrait speaking (plan PQ1:
## face left, words right — a quote never appears without the bust beside it).
## Lines rotate per side by activation count, never by RNG, so a replayed match
## speaks the same words and a captured activation is always the same frame. A
## commander with no quotes gets today's card unchanged: label hidden, power name
## back at full size.
##
## Pure presentation, and deliberately inert as far as the sim is concerned: it is
## populated from the already-fired PowerCommand's event and only *shows* what the
## power did. It may briefly gate input while it holds, but it never owns or
## alters simulation state — save/replay determinism stays entirely in core/.

## The headline hierarchy: with a quote on the card the power name steps down so
## the general's words lead; without one it keeps the size it always had.
const _QUOTE_SIZE := 16
const _POWER_NAME_SIZE := 22
const _POWER_NAME_QUOTED_SIZE := 13

var _built := false
## Activations announced so far, per team — the rotation index for the next
## quote. Scene-lifetime state: a loaded save restarts the rotation, which is
## cosmetic by construction.
var _spoken: Dictionary = {}
var _field: Panel
var _portrait: TextureRect
var _eyebrow: Label
var _quote: Label
var _power_name: Label
var _power_text: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_stylebox_override(
		"panel", _box(CommanderVisuals.PAPER, CommanderVisuals.HARD_BORDER, 4)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	# A fixed-size portrait field: an explicit height so the portrait fills it, and
	# a width the HBox will not stretch (it has no expand flag).
	_field = Panel.new()
	_field.custom_minimum_size = Vector2(104, 108)
	_field.clip_contents = true
	row.add_child(_field)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.add_child(_portrait)

	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4)
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wrap := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + edge, 14)
	wrap.add_child(copy)
	row.add_child(wrap)

	_eyebrow = _mono(9, Color(0.431, 0.463, 0.482))
	copy.add_child(_eyebrow)
	# A fixed wrap width for the two autowrap Labels, so each computes a sane min
	# height instead of reporting the pathological "one word per line" height
	# that would balloon the whole banner.
	_quote = Label.new()
	_quote.custom_minimum_size = Vector2(300, 0)
	_quote.add_theme_font_size_override("font_size", _QUOTE_SIZE)
	_quote.add_theme_color_override("font_color", CommanderVisuals.PAPER_INK)
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_quote)
	_power_name = _mono(_POWER_NAME_SIZE, Color(0.667, 0.224, 0.184))
	copy.add_child(_power_name)
	_power_text = Label.new()
	_power_text.custom_minimum_size = Vector2(300, 0)
	_power_text.add_theme_font_size_override("font_size", 11)
	_power_text.add_theme_color_override("font_color", CommanderVisuals.PAPER_INK)
	_power_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_power_text)

	_built = true


func bind(commander: CommanderType, team: int) -> void:
	if not _built:
		_build()
	var theme := CommanderVisuals.theme_for(commander)
	add_theme_stylebox_override("panel", _box(CommanderVisuals.PAPER, theme.color_dark, 4))
	_field.add_theme_stylebox_override("panel", _flat(theme.color))
	_portrait.texture = CommanderVisuals.portrait_for(commander)
	_eyebrow.text = "%s · COMMAND POWER" % commander.display_name.to_upper()
	var line := _next_quote(commander, team)
	_quote.visible = not line.is_empty()
	_quote.text = "“%s”" % line
	_power_name.text = commander.power_name.to_upper()
	_power_name.add_theme_font_size_override(
		"font_size", _POWER_NAME_SIZE if line.is_empty() else _POWER_NAME_QUOTED_SIZE
	)
	_power_name.add_theme_color_override("font_color", theme.color_dark)
	_power_text.text = commander.power_text


## The next line in this side's rotation. Activation count picks quotes in
## order — deliberately not randf(), in the tradition of shake_camera's note
## about game.rng: a replayed match must speak the same words, and the scenario
## gallery's activation #1 must always photograph the same frame.
func _next_quote(commander: CommanderType, team: int) -> String:
	if commander.power_quotes.is_empty():
		return ""
	var count: int = _spoken.get(team, 0)
	_spoken[team] = count + 1
	return commander.power_quotes[count % commander.power_quotes.size()]


func _mono(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := _flat(bg)
	box.border_color = border
	box.set_border_width_all(width)
	return box
